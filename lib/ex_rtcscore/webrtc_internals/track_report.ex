defmodule ExRTCScore.WebRTCInternals.TrackReport do
  @moduledoc """
  Struct containing the parsed track statistics:
  TODO WRITEME
  """

  alias ExRTCScore.Stat

  defmodule Score do
    @moduledoc """
    TODO WRITEME
    """

    @type t :: %__MODULE__{
            mean: number(),
            q1: number(),
            median: number(),
            q3: number()
          }

    @enforce_keys [:mean, :q1, :median, :q3]

    defstruct @enforce_keys

    @spec new([number()]) :: t()
    def new(values) do
      n = length(values)
      ord_values = Enum.sort(values)

      %__MODULE__{
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
          start_time: String.t(),
          end_time: String.t(),
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
