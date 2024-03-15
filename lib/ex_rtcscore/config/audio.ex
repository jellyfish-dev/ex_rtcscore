defmodule ExRTCScore.Config.Audio do
  @moduledoc """
  TODO rewriteme
  Struct describing the audio parameters:
  * `:fec` - Whether OPUS forward error correction is enabled (default: `true`)
  * `:dtx` - Whether OPUS discontinuous transmission is enabled (default: `false`)
  * `:red` - Whether redundant encoding is enabled (default: `false`)
  """

  use Bunch.Access
  alias ExRTCScore.Utils

  @defaults %{
    fec: true,
    dtx: false,
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
  @spec normalise(t()) :: t()
  def normalise(%__MODULE__{} = config) do
    Utils.put_defaults_if_nil(config, @defaults)
  end
end
