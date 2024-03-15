defmodule ExRTCScore.Stat do
  @moduledoc """
  TODO rewriteme
  Struct describing the input parameters necessary to calculate the score:
  * `:packet_loss` - Packet loss in percent (0-100)
  * `:bitrate` - Bitrate in bits per second
  * `:track_config` - Struct with the video/audio track parameters
  * `:round_trip_time` - Round trip time in milliseconds (default: `50`)
  * `:buffer_delay` - Buffer delay in milliseconds (default: `50`)
  """

  use Bunch.Access

  alias ExRTCScore.{Config, Utils}

  @defaults %{
    packet_loss: nil,
    bitrate: nil,
    round_trip_time: 50,
    buffer_delay: 50
  }

  @type t :: %__MODULE__{
          track_config: Config.Video.t() | Config.Audio.t(),
          packet_loss: number() | nil,
          bitrate: number() | nil,
          round_trip_time: number() | nil,
          buffer_delay: number() | nil
        }

  @enforce_keys [
    :track_config
  ]

  defstruct @enforce_keys ++
              [
                packet_loss: nil,
                bitrate: nil,
                round_trip_time: nil,
                buffer_delay: nil
              ]

  @doc false
  @spec normalise(t()) :: t()
  def normalise(%__MODULE__{} = stat) do
    %config_module{} = stat.track_config

    stat
    |> Utils.put_defaults_if_nil(@defaults)
    |> Map.update!(:track_config, &config_module.normalise/1)
  end
end
