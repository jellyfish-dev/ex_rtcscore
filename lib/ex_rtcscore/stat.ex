defmodule ExRTCScore.Stat do
  @moduledoc """
  Struct describing the input parameters necessary to calculate the score:
  * `:track_config` - Struct with the video/audio track parameters
  * `:packet_loss` - Packet loss in percent (0-100)
  * `:bitrate` - Bitrate in bits per second
  * `:round_trip_time` - Round trip time in milliseconds
  * `:buffer_delay` - Buffer delay in milliseconds
  """

  use Bunch.Access

  alias ExRTCScore.Config

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
  @spec fill_defaults(t()) :: t()
  def fill_defaults(%__MODULE__{} = stat) do
    %config_module{} = stat.track_config

    Map.update!(stat, :track_config, &config_module.fill_defaults/1)
  end
end
