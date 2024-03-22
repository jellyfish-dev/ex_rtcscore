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
  """

  alias ExRTCScore.Stat

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
          score: Score.t() | nil
        }

  @enforce_keys [
    :peer_id,
    :track_id,
    :kind,
    :start_time,
    :end_time,
    :stats
  ]

  defstruct @enforce_keys ++ [score: nil]
end
