defmodule ExRTCScore.WebRTCInternals do
  @moduledoc """
  TODO WRITEME
  """

  alias ExRTCScore.{Config, Utils}
  alias ExRTCScore.WebRTCInternals.{Parser, Report, TrackReport}

  @type score_ctx :: %{video: Config.Video.t(), audio: Config.Audio.t()}
  @default_score_ctx %{video: %Config.Video{}, audio: %Config.Audio{}}

  @doc "Generate `TrackReport`s for inbound RTP tracks from a WebRTC internals JSON dump"
  @spec generate_report(String.t(), score_ctx() | :default | :dont_score) ::
          Report.t() | no_return()
  def generate_report(filename, score_ctx \\ :default) do
    filename
    |> File.read!()
    |> Jason.decode!()
    |> Parser.parse()
    |> then(
      &case score_ctx do
        :dont_score -> &1
        :default -> score_report(&1)
        ctx -> score_report(&1, ctx)
      end
    )
  end

  @spec score_report(Report.t(), score_ctx()) :: Report.t()
  def score_report(report, score_ctx \\ @default_score_ctx) do
    Map.new(report.peer_scores, fn {peer_id, peer_score} ->
      {peer_id,
       Map.new(peer_score, fn
         {kind, nil} -> {kind, nil}
         {kind, report} -> {kind, do_score(report, score_ctx)}
       end)}
    end)
    |> then(&%{report | peer_scores: &1})
  end

  defp do_score(report, score_ctx) do
    report.stats
    |> Enum.map(fn stat ->
      stat
      |> Map.update!(:track_config, &Utils.put_defaults_if_nil(&1, score_ctx[report.kind]))
      |> ExRTCScore.score()
    end)
    |> TrackReport.Score.new()
    |> then(&Map.put(report, :score, &1))
  end
end
