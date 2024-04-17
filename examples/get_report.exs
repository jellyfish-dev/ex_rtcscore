# A sample script for scoring a webrtc-internals dump

alias ExRTCScore.WebRTCInternals
alias ExRTCScore.Config

filename = System.argv() |> hd()

defmodule Utils do
  def format_duration(seconds) do
    min = div(seconds, 60)
    sec = rem(seconds, 60) |> Integer.to_string() |> String.pad_leading(2, "0")

    "#{min}:#{sec} min"
  end

  def get_median(track_report, metric) do
    entries =
      Enum.map(track_report.stats, fn stat ->
        Map.get(stat, metric)
      end)

    Enum.at(entries, length(entries) |> div(2))
  end
end

report =
  WebRTCInternals.generate_report(filename, %{
    video: %Config.Video{expected_framerate: 24},
    audio: %Config.Audio{}
  })

scores =
  Map.new(report.peer_scores, fn {track_id, peer_data} ->
    duration =
      DateTime.diff(peer_data.video.end_time, peer_data.video.start_time, :second)
      |> Utils.format_duration()

    rtt = Utils.get_median(peer_data.video, :round_trip_time)

    {track_id,
     Map.new(peer_data, fn {type, track_report} ->
       {type, Map.take(track_report.score, [:median])}
     end)
     |> Map.put(:duration, duration)
     |> Map.put(:rtt, rtt)}
  end)

IO.inspect(scores)
