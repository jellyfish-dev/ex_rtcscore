defmodule ExRTCScore.WebRTCInternals.Parser do
  @moduledoc false

  require Logger

  alias ExRTCScore.{Config, Stat, WebRTCInternals}
  alias ExRTCScore.WebRTCInternals.TrackReport

  @video_specific_stats [
    "codecId",
    "framesDecoded",
    "frameHeight",
    "frameWidth"
  ]

  @filter_stats [
                  "bytesReceived",
                  "jitterBufferDelay",
                  "jitterBufferEmittedCount",
                  "kind",
                  "packetsLost",
                  "packetsReceived",
                  "transportId"
                ] ++ @video_specific_stats

  @doc false
  @spec parse(term()) :: WebRTCInternals.t()
  def parse(data) do
    ctx = %{entries_per_second: data["getStats"]["dataFrequency"] || 1}

    Enum.reduce(data["PeerConnections"], %{}, fn {peer_id, %{"stats" => peer_stats}}, acc ->
      rtt_by_transport = parse_rtt(peer_stats)
      ctx = Map.merge(ctx, parse_tracks_info(peer_stats))

      peer_stats
      |> filter_and_parse_entries(ctx)
      |> Enum.reduce(acc, fn {track_id, track_entries}, acc ->
        [track_kind | _rest] = track_kinds = track_entries["kind"]["values"]
        [transport_id | _rest] = transport_ids = track_entries["transportId"]["values"]
        %{"startTime" => start_time, "endTime" => end_time} = track_entries["kind"]

        with true <- Enum.all?(track_kinds, &(&1 == track_kind)),
             true <- Enum.all?(transport_ids, &(&1 == transport_id)),
             {:ok, start_time} <- parse_time(start_time),
             {:ok, end_time} <- parse_time(end_time),
             kind <- parse_kind(track_kind),
             {:ok, track_entries, track_config} <-
               get_entries_and_config(track_entries, kind, ctx) do
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
              stats: statify(track_entries, track_config, rtt_by_transport[transport_id], ctx)
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

  # Get the mapping `transportId => [currentRoundTripTime]`.
  #
  # RTT is measured for candidate pairs, so we need to associate transports
  # with the corresponding measurements at the right moments in time
  defp parse_rtt(peer_entries) do
    # %{transportId => [selectedCandidatePairId]}
    Enum.reduce(peer_entries, %{}, fn {entry_key, entry}, acc ->
      with {transport_id, stat_name} <- parse_entry_key(entry_key),
           true <- stat_type_equals?(entry, stat_name, "transport") do
        peer_entries[transport_id <> "-" <> "selectedCandidatePairId"]["values"]
        |> Jason.decode!()
        |> then(&Map.put(acc, transport_id, &1))
      else
        _any -> acc
      end
    end)
    |> Map.new(fn {transport_id, selected_candidate_pair_id} ->
      # How many values correspond to each candidate pair ID
      rtt_value_counts =
        selected_candidate_pair_id
        |> Enum.group_by(& &1)
        |> Map.new(fn {k, v} -> {k, length(v)} end)

      # Concatenate the correct numbers of values from corresponding candidate pairs
      rtt_values =
        selected_candidate_pair_id
        |> Enum.uniq()
        |> Enum.reduce([], fn candidate_pair_id, acc ->
          peer_entries[candidate_pair_id <> "-" <> "currentRoundTripTime"]["values"]
          |> Jason.decode!()
          |> Enum.take(rtt_value_counts[candidate_pair_id])
          |> then(&(acc ++ &1))
        end)
        # to milliseconds
        |> Enum.map(&(&1 * 1000))

      {transport_id, rtt_values}
    end)
  end

  defp parse_entry_key(entry_key) do
    # Split the key into 2 parts at `-`, but do it from the end
    # (track_id may also contain `-`s)
    [track_id, stat_name] = Regex.run(~r/^(.+)-([^-]+)$/, entry_key, capture: :all_but_first)

    {track_id, stat_name}
  end

  # Get a `MapSet` of inbound RTP track IDs
  # as well as the mapping `codecId => codec_atom`
  defp parse_tracks_info(peer_entries) do
    Enum.reduce(
      peer_entries,
      %{inbound_rtp_tracks: MapSet.new(), codec_by_id: %{}},
      fn {entry_key, entry}, acc ->
        with {track_id, stat_name} <- parse_entry_key(entry_key) do
          cond do
            stat_type_equals?(entry, stat_name, "inbound-rtp") ->
              %{acc | inbound_rtp_tracks: MapSet.put(acc.inbound_rtp_tracks, track_id)}

            stat_type_equals?(entry, stat_name, "codec") ->
              [mimetype | _rest] =
                peer_entries[track_id <> "-" <> "mimeType"]["values"]
                |> Jason.decode!()

              codec = mimetype |> String.downcase() |> parse_mimetype()

              %{acc | codec_by_id: Map.put(acc.codec_by_id, track_id, codec)}

            true ->
              acc
          end
        else
          _any -> acc
        end
      end
    )
  end

  defp stat_type_equals?(entry, stat_name, expected_type) do
    (stat_name == "type" and
       entry["values"] |> Jason.decode!() |> Enum.all?(&(&1 == expected_type))) or
      entry["statsType"] == expected_type
  end

  # Take only selected stats from `inbound-rtp` tracks
  defp filter_and_parse_entries(peer_entries, ctx) do
    Enum.reduce(peer_entries, %{}, fn {entry_key, entry}, acc ->
      with {track_id, stat_name} <- parse_entry_key(entry_key),
           true <- MapSet.member?(ctx.inbound_rtp_tracks, track_id),
           true <- stat_name in @filter_stats do
        acc
        |> Map.put_new(track_id, %{})
        |> put_in([track_id, stat_name], Map.update!(entry, "values", &Jason.decode!/1))
      else
        _any -> acc
      end
    end)
  end

  defp statify(entries, track_config, rtt_values, ctx) do
    stat_count = Enum.min(for {_k, v} <- entries, do: length(v["values"]))

    %Stat{track_config: track_config}
    |> List.duplicate(stat_count)
    |> update_stats(:bitrate, calculate_bitrate(entries, ctx))
    |> update_stats(:packet_loss, calculate_packet_loss(entries))
    |> update_stats(:buffer_delay, calculate_buffer_delay(entries, ctx))
    |> update_stats(:round_trip_time, rtt_values)
    |> then(
      &if(match?(%Config.Video{}, track_config),
        do: update_stats(&1, :framerate, calculate_framerate(entries, ctx)),
        else: &1
      )
    )
    |> then(
      &Enum.reduce(entries, &1, fn {stat_name, entry}, stats ->
        update_stats(stats, stat_name, entry["values"])
      end)
    )
  end

  defp calculate_bitrate(entries, ctx),
    do: calculate_simple_deltas(entries, "bytesReceived", ctx, &(&1 * 8))

  defp calculate_framerate(entries, ctx),
    do: calculate_simple_deltas(entries, "framesDecoded", ctx)

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
        packet_loss = if all > 0, do: lost_delta * 100 / all, else: 0

        {packet_loss, {lost, received}}
      end)

    packet_loss_values
  end

  defp calculate_buffer_delay(entries, ctx) do
    {buffer_delay_values, _acc} =
      Enum.zip(
        entries["jitterBufferDelay"]["values"],
        entries["jitterBufferEmittedCount"]["values"]
      )
      |> Enum.map_reduce({0, 0}, fn {delay, count}, {previous_delay, previous_count} ->
        delay_delta = delay - previous_delay
        count_delta = count - previous_count

        buffer_delay =
          if count_delta > 0,
            do: delay_delta * 1000 / count_delta / ctx.entries_per_second,
            else: 0

        {buffer_delay, {delay, count}}
      end)

    buffer_delay_values
  end

  defp calculate_simple_deltas(entries, stat_name, ctx, transform \\ & &1) do
    {values, _acc} =
      Enum.map_reduce(entries[stat_name]["values"], 0, fn current, previous ->
        delta = (current - previous) / ctx.entries_per_second

        {transform.(delta), current}
      end)

    values
  end

  defp update_stats(stats, stat_name, values) do
    stats
    |> Enum.zip(values)
    |> Enum.map(&update_stat(&1, stat_name))
  end

  defp update_stat({stat, value}, "frameHeight"),
    do: put_in(stat, [:track_config, :height], value)

  defp update_stat({stat, value}, "frameWidth"), do: put_in(stat, [:track_config, :width], value)

  defp update_stat({stat, value}, :framerate),
    do: put_in(stat, [:track_config, :framerate], value)

  defp update_stat({stat, value}, :bitrate), do: %{stat | bitrate: value}
  defp update_stat({stat, value}, :packet_loss), do: %{stat | packet_loss: value}
  defp update_stat({stat, value}, :buffer_delay), do: %{stat | buffer_delay: value}
  defp update_stat({stat, value}, :round_trip_time), do: %{stat | round_trip_time: value}

  defp update_stat({stat, _value}, _other), do: stat

  defp get_entries_and_config(entries, kind, ctx) do
    with [codec_id | _rest] <- entries["codecId"]["values"] do
      entries =
        if kind == :audio,
          do: Map.drop(entries, @video_specific_stats),
          else: entries

      {:ok, entries, get_track_config(kind, codec_id, ctx)}
    else
      _any -> :error
    end
  end

  defp get_track_config(:video, codec_id, ctx) do
    %Config.Video{
      codec: ctx.codec_by_id[codec_id]
    }
  end

  defp get_track_config(:audio, codec_id, _ctx) do
    %Config.Audio{
      fec: String.contains?(codec_id, "useinbandfec=1"),
      dtx: String.contains?(codec_id, "usedtx=1")
    }
  end

  defp parse_kind("video"), do: :video
  defp parse_kind("audio"), do: :audio
  defp parse_kind(other), do: raise("Unknown kind of track: #{inspect(other)}")

  defp parse_time(time) when is_number(time), do: DateTime.from_unix(round(time), :millisecond)

  defp parse_time(time) do
    with {:ok, datetime, _offset} <- DateTime.from_iso8601(time), do: {:ok, datetime}
  end

  defp parse_mimetype("audio/opus"), do: :opus
  defp parse_mimetype("video/h264"), do: :h264
  defp parse_mimetype("video/vp8"), do: :vp8
  defp parse_mimetype("video/vp9"), do: :vp9
  defp parse_mimetype("video/av1"), do: :av1
  defp parse_mimetype(other), do: raise("Unknown mimetype: #{inspect(other)}")
end
