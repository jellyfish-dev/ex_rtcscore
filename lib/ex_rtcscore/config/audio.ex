defmodule ExRTCScore.Config.Audio do
  @moduledoc """
  Struct describing the audio parameters:
  * `:fec` - Whether OPUS forward error correction is enabled
  * `:dtx` - Whether OPUS discontinuous transmission is enabled
  * `:red` - Whether redundant encoding is enabled.
    During scoring, if set to `nil`, defaults to `false`.
  """

  use Bunch.Access
  alias ExRTCScore.Utils

  @defaults %{
    red: false
  }

  @type t :: %__MODULE__{
          fec: boolean() | nil,
          dtx: boolean() | nil,
          red: boolean() | nil
        }

  @enforce_keys []

  defstruct @enforce_keys ++
              [
                fec: nil,
                dtx: nil,
                red: nil
              ]

  @doc false
  @spec fill_defaults(t()) :: t()
  def fill_defaults(%__MODULE__{} = config) do
    Utils.put_defaults_if_nil(config, @defaults)
  end
end
