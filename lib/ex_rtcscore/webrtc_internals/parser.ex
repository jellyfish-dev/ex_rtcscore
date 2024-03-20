defmodule ExRTCScore.WebRTCInternals.Parser do
  @moduledoc false

  require Logger

  alias ExRTCScore.{Config, Stat, WebRTCInternals}
  alias ExRTCScore.WebRTCInternals.TrackReport

  @video_specific_stats [
    "[codec]",
    "[framesDecoded/s]",
    "frameHeight",
    "frameWidth"
  ]

  @filter_stats [
                  "[bytesReceived_in_bits/s]",
                  "[jitterBufferDelay/jitterBufferEmittedCount_in_ms]",
                  "kind",
                  "packetsLost",
                  "packetsReceived",
                  "transportId"
                ] ++ @video_specific_stats

  @doc false
  @spec parse(term()) :: WebRTCInternals.t()
  def parse(data) do
    Enum.reduce(data["PeerConnections"], %{}, fn {peer_id, peer_data}, acc ->
      rtt_by_transport = parse_rtt(peer_data["stats"])

      peer_data["stats"]
      |> filter_and_parse_entries()
      |> Enum.reduce(acc, fn {track_id, track_entries}, acc ->
        [track_kind | _rest] = track_kinds = track_entries["kind"]["values"]
        [transport_id | _rest] = transport_ids = track_entries["transportId"]["values"]
        %{"startTime" => start_time, "endTime" => end_time} = track_entries["kind"]

        with true <- Enum.all?(track_kinds, &(&1 == track_kind)),
             true <- Enum.all?(transport_ids, &(&1 == transport_id)),
             {:ok, start_time, _offset} <- DateTime.from_iso8601(start_time),
             {:ok, end_time, _offset} <- DateTime.from_iso8601(end_time) do
          kind = parse_kind(track_kind)
          {track_entries, track_config} = get_entries_and_config(track_entries, kind)

          acc
          |> Map.put_new(peer_id, %{video: nil, audio: nil})
          |> put_in(
            [peer_id, kind],
            %TrackReport{
              peer_id: peer_id,
              track_id: track_id,
              kind: kind,
              start_time: start_time,
              end_time: end_time,
              stats: statify(track_entries, track_config, rtt_by_transport[transport_id])
            }
          )
        else
          _any ->
            Logger.warning(
              "Unable to parse inbound RTP track #{inspect(track_id)} from peer #{inspect(peer_id)}"
            )

            acc
        end
      end)
    end)
    |> then(&%WebRTCInternals{peer_scores: &1})
  end

  defp parse_rtt(peer_entries) do
    Enum.reduce(peer_entries, %{}, fn {entry_key, entry}, acc ->
      with "transport" <- entry["statsType"],
           [transport_id, stat_name | _rest] <- String.split(entry_key, "-"),
           "selectedCandidatePairId" <- stat_name do
        Map.put(acc, transport_id, entry["values"] |> Jason.decode!())
      else
        _any -> acc
      end
    end)
    |> Map.new(fn {transport_id, current_candidate_pair_id} ->
      rtt_value_counts =
        current_candidate_pair_id
        |> Enum.group_by(& &1)
        |> Map.new(fn {k, v} -> {k, length(v)} end)

      rtt_values =
        current_candidate_pair_id
        |> Enum.uniq()
        |> Enum.reduce([], fn candidate_pair_id, acc ->
          peer_entries[candidate_pair_id <> "-" <> "currentRoundTripTime"]["values"]
          |> Jason.decode!()
          |> Enum.take(rtt_value_counts[candidate_pair_id])
          |> then(&(acc ++ &1))
        end)

      {transport_id, rtt_values}
    end)
  end

  # Take only selected stats from `inbound-rtp` tracks
  defp filter_and_parse_entries(peer_entries) do
    Enum.reduce(peer_entries, %{}, fn {entry_key, entry}, acc ->
      with "inbound-rtp" <- entry["statsType"],
           [track_id, stat_name | _rest] <- String.split(entry_key, "-"),
           true <- stat_name in @filter_stats do
        acc
        |> Map.put_new(track_id, %{})
        |> put_in([track_id, stat_name], Map.update!(entry, "values", &Jason.decode!/1))
      else
        _any -> acc
      end
    end)
  end

  defp statify(entries, track_config, rtt_values) do
    packet_loss_values = calculate_packet_loss(entries)
    stat_count = Enum.min(for {_k, v} <- entries, do: length(v["values"]))

    %Stat{track_config: track_config}
    |> List.duplicate(stat_count)
    |> update_stats(:packet_loss, packet_loss_values)
    |> update_stats(:round_trip_time, rtt_values)
    |> then(
      &Enum.reduce(entries, &1, fn {stat_name, entry}, stats ->
        update_stats(stats, stat_name, entry["values"])
      end)
    )
  end

  # Calculate per-second packet loss
  defp calculate_packet_loss(entries) do
    {packet_loss_values, _acc} =
      Enum.zip(entries["packetsLost"]["values"], entries["packetsReceived"]["values"])
      |> Enum.map_reduce({0, 0}, fn {lost, received}, {previous_lost, previous_received} ->
        # Clamping with 0 because we've observed that this delta can be negative, i.e. when
        # packetsLost.values = [0, 0, 1, 1, 6, 5, 5]
        # (I assume that this happens when lost packets have arrived late)
        lost_delta = max(lost - previous_lost, 0)
        received_delta = received - previous_received
        all = lost_delta + received_delta
        packet_loss = if all != 0, do: lost_delta * 100 / all, else: 0

        {packet_loss, {lost, received}}
      end)

    packet_loss_values
  end

  defp update_stats(stats, stat_name, values) do
    stats
    |> Enum.zip(values)
    |> Enum.map(&update_stat(&1, stat_name))
  end

  defp update_stat({stat, value}, "[codec]"),
    do: put_in(stat, [:track_config, :codec], parse_video_codec(value))

  defp update_stat({stat, value}, "frameHeight"),
    do: put_in(stat, [:track_config, :height], value)

  defp update_stat({stat, value}, "frameWidth"), do: put_in(stat, [:track_config, :width], value)

  defp update_stat({stat, value}, "[framesDecoded/s]"),
    do: put_in(stat, [:track_config, :framerate], value)

  defp update_stat({stat, value}, "[bytesReceived_in_bits/s]"), do: %{stat | bitrate: value}

  defp update_stat({stat, value}, "[jitterBufferDelay/jitterBufferEmittedCount_in_ms]"),
    do: %{stat | buffer_delay: value}

  defp update_stat({stat, value}, :packet_loss), do: %{stat | packet_loss: value}
  # RTT is in seconds, so we have to multiply by 1000
  defp update_stat({stat, value}, :round_trip_time), do: %{stat | round_trip_time: value * 1000}

  defp update_stat({stat, _value}, _other), do: stat

  defp get_entries_and_config(entries, :video) do
    {entries, %Config.Video{}}
  end

  defp get_entries_and_config(entries, :audio) do
    [codec_str | _rest] = entries["[codec]"]["values"]

    {entries |> Map.drop(@video_specific_stats), config_from_opus_params(codec_str)}
  end

  defp config_from_opus_params(codec) do
    %Config.Audio{
      fec: String.contains?(codec, "useinbandfec=1"),
      dtx: String.contains?(codec, "usedtx=1")
    }
  end

  defp parse_kind("video"), do: :video
  defp parse_kind("audio"), do: :audio
  defp parse_kind(other), do: raise("Unknown kind of track: #{inspect(other)}")

  defp parse_video_codec("H264" <> _rest), do: :h264
  defp parse_video_codec("VP8" <> _rest), do: :vp8
  defp parse_video_codec("VP9" <> _rest), do: :vp9
  defp parse_video_codec("AV1" <> _rest), do: :av1
  defp parse_video_codec(other), do: raise("Unknown codec: #{inspect(other)}")
end
