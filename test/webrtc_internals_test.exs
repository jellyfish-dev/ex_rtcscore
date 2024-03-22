defmodule WebRTCInternalsTest do
  use ExUnit.Case

  alias ExRTCScore.WebRTCInternals

  @fixtures_dir "test/fixtures"

  test "correctly parse and score sample webrtc internals dump" do
    report =
      @fixtures_dir
      |> Path.join("sample-webrtc-internals-dump.txt")
      |> WebRTCInternals.generate_report()

    [peer_id] = report.peer_scores |> Map.keys()

    for {_kind, report} <- report.peer_scores[peer_id] do
      refute is_nil(report)

      for stat <- report.stats do
        for field <- Map.keys(stat) do
          refute is_nil(stat[field])
        end

        for field <- Map.keys(stat.track_config) do
          # ATM we don't parse these two fields, so they will always be `nil`
          if field not in [:red, :expected_framerate],
            do: refute(is_nil(stat.track_config[field]))
        end
      end

      refute is_nil(report.score)
      assert length(report.score.values) == length(report.stats)
      assert report.score.mean >= 3.0
      assert report.score.mean <= 4.0

      for {stat, score} <- Enum.zip(report.stats, report.score.values) do
        assert ExRTCScore.score(stat) == score
      end
    end
  end
end
