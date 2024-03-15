defmodule ExRTCScore.WebRTCInternals.Report do
  @moduledoc """
  TODO WRITEME
  """

  alias ExRTCScore.WebRTCInternals.TrackReport

  @type peer_score :: %{video: TrackReport.t() | nil, audio: TrackReport.t() | nil}

  @type t :: %__MODULE__{
          peer_scores: %{String.t() => peer_score()}
        }

  @enforce_keys [
    :peer_scores
  ]

  defstruct @enforce_keys
end
