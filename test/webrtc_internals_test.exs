defmodule WebRTCInternalsTest do
  use ExUnit.Case

  alias ExRTCScore.WebRTCInternals

  @fixtures_dir "test/fixtures"

  test "correctly parse and score sample webrtc internals dump" do
    report = get_report("sample-webrtc-internals-dump.txt")

    [peer_id] = report.peer_scores |> Map.keys()

    for {kind, report} <- report.peer_scores[peer_id] do
      assert_peer_score(kind, report, score_mean_lo: 3.0, score_mean_hi: 4.0)
    end
  end

  test "correctly parse and score webrtc dump with sus tracks" do
    report = get_report("internals-dump-chrome.txt")

    peer_ids = report.peer_scores |> Map.keys()

    for peer_id <- peer_ids do
      for {kind, report} <- report.peer_scores[peer_id] do
        assert_peer_score(kind, report, score_mean_lo: 3.5, score_mean_hi: 4.5)
      end
    end
  end

  test "correctly parse and score get_stats dump from testRTC" do
    report = get_report("test-rtc-dump.json")

    [peer_id] = report.peer_scores |> Map.keys()

    for {kind, report} <- report.peer_scores[peer_id] do
      assert_peer_score(kind, report, score_mean_lo: 3.5, score_mean_hi: 4.5)
    end
  end

  defp get_report(filename) do
    @fixtures_dir
    |> Path.join(filename)
    |> WebRTCInternals.generate_report()
  end

  defp assert_peer_score(_kind, report, opts) do
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
    assert report.score.mean >= opts[:score_mean_lo]
    assert report.score.mean <= opts[:score_mean_hi]

    for {stat, score} <- Enum.zip(report.stats, report.score.values) do
      assert ExRTCScore.score(stat) == score
    end
  end
end
