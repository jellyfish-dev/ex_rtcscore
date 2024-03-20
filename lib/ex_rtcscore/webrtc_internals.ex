defmodule ExRTCScore.WebRTCInternals do
  @moduledoc """
  Utilities for working with WebRTC Internals JSON dumps.
  """

  alias ExRTCScore.{Config, Utils}
  alias ExRTCScore.WebRTCInternals.{Parser, TrackReport}

  @type peer_score :: %{video: TrackReport.t() | nil, audio: TrackReport.t() | nil}

  @typedoc """
  Struct containing the parsed WebRTC internals JSON dump:
  * `:peer_scores` - Map with peer IDs as keys and `#{inspect(__MODULE__)}.TrackReport`s
    for video and audio tracks (if present) as values
  """
  @type t :: %__MODULE__{
          peer_scores: %{String.t() => peer_score()}
        }

  @enforce_keys [
    :peer_scores
  ]

  defstruct @enforce_keys

  @typedoc """
  Specifies `ExRTCScore.Config` structs with default values for video and audio tracks.
  During scoring, if a `ExRTCScore.Stat`'s `:track_config` has a field set to `nil`,
  a default value specified here will be used instead.
  """
  @type score_ctx :: %{video: Config.Video.t(), audio: Config.Audio.t()}
  @default_score_ctx %{video: %Config.Video{}, audio: %Config.Audio{}}

  @doc """
  Generate a report for inbound RTP tracks from a WebRTC internals JSON dump.
  * `filename` - Path to the JSON file
  * `score_ctx` - Context for scoring the tracks. Possible values are:
    - `:dont_score` - Generate the report, but don't score it
    - `:default` - Generate the report, then call `score_report(report)`
    - `score_ctx` - Generate the report, then call `score_report(report, score_ctx)`

  Refer to `score_report/2` for more details.
  """
  @spec generate_report(String.t(), score_ctx() | :default | :dont_score) :: t() | no_return()
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

  @doc """
  Score a previously generated report.
  * `report` - `#{inspect(__MODULE__)}` struct
  * `score_ctx` - If a `ExRTCScore.Stat`'s `:track_config` has a field set to `nil`,
    a default value specified here will be used instead. If not provided, no defaults will be assumed.

  Caution: **does not** fill the following fields in `:track_config`:
  * video tracks - `:expected_framerate`
  * audio tracks - `:red`
  """
  @spec score_report(t(), score_ctx()) :: t()
  def score_report(report, score_ctx \\ @default_score_ctx) do
    Map.new(report.peer_scores, fn {peer_id, peer_score} ->
      {peer_id,
       Map.new(peer_score, fn
         {kind, nil} -> {kind, nil}
         {kind, track_report} -> {kind, score_track_report(track_report, score_ctx)}
       end)}
    end)
    |> then(&%{report | peer_scores: &1})
  end

  defp score_track_report(report, score_ctx) do
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
