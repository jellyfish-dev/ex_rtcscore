defmodule ExRTCScore.WebRTCInternals.TrackReport do
  @moduledoc """
  Struct containing the parsed track statistics:
  * `:peer_id` - Peer ID
  * `:track_id` - Track ID
  * `:kind` - Track kind
  * `:start_time` - Timestamp of the first stat entry
  * `:end_time` - Timestamp of the last stat entry
  * `:stats` - List with time range of entries
  * `:score` - Calculated score (default: `nil`)
  * `:latency` - Calculated end-to-end latency estimate (default: `nil`)
  """

  alias ExRTCScore.{Config, Stat, Utils}

  defmodule Score do
    @moduledoc """
    Struct containing the aggregated score:
    * `:values` - Metric values in time
    * `:mean` - Arithmetic mean of the metric values
    * `:q1` - First quartile of the metric values
    * `:median` - Median (second quartile) of the metric values
    * `:q3` - Third quartile of the metric values
    """

    @type t :: %__MODULE__{
            values: [number()],
            mean: number(),
            q1: number(),
            median: number(),
            q3: number()
          }

    @enforce_keys [:values, :mean, :q1, :median, :q3]

    defstruct @enforce_keys

    @spec new([number()]) :: t()
    def new(values) do
      n = length(values)
      ord_values = Enum.sort(values)

      %__MODULE__{
        values: values,
        mean: Float.round(Enum.sum(values) / n, 2),
        q1: Enum.at(ord_values, div(n, 4)),
        median: Enum.at(ord_values, div(n, 2)),
        q3: Enum.at(ord_values, div(3 * n, 4))
      }
    end
  end

  @type t :: %__MODULE__{
          peer_id: String.t(),
          track_id: String.t(),
          kind: :video | :audio,
          start_time: DateTime.t(),
          end_time: DateTime.t(),
          stats: [Stat.t()],
          score: Score.t() | nil,
          latency: Score.t() | nil
        }

  @enforce_keys [
    :peer_id,
    :track_id,
    :kind,
    :start_time,
    :end_time,
    :stats
  ]

  defstruct @enforce_keys ++ [score: nil, latency: nil]

  @doc """
  Score a previously generated track report.
  * `track_report` - `#{inspect(__MODULE__)}` struct
  * `defaults` - If a `ExRTCScore.Stat`'s `:track_config` has a field set to `nil`,
    a default value specified here will be used instead.

  Caution: **does not** fill the following fields in `:track_config`:
  * video tracks - `:expected_framerate`
  * audio tracks - `:red`

  """
  @spec score(t(), Config.Video.t() | Config.Audio.t()) :: t()
  def score(track_report, defaults) do
    track_report.stats
    |> Enum.map(fn stat ->
      stat
      |> Map.update!(:track_config, &Utils.put_defaults_if_nil(&1, defaults))
      |> ExRTCScore.score()
    end)
    |> Score.new()
    |> then(&%{track_report | score: &1})
  end

  @doc """
  Calculate the end-to-end latency estimates and insert them into the previously generated track report.
  * `track_report` - `#{inspect(__MODULE__)}` struct
  * `sender_round_trip_time` - Round trip time (in milliseconds) from the sending side.
    At the moment, only one value may be provided here, which will be used for all stat entries.

  To calculate a single value, use `ExRTCScore.e2e_latency/2`.
  """
  @spec calculate_latency(t(), number()) :: t()
  def calculate_latency(track_report, sender_round_trip_time) do
    track_report.stats
    |> Enum.map(&ExRTCScore.e2e_latency(&1, sender_round_trip_time))
    |> Score.new()
    |> then(&%{track_report | latency: &1})
  end
end
