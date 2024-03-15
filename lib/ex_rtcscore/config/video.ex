defmodule ExRTCScore.Config.Video do
  @moduledoc """
  TODO rewriteme
  Struct describing the video parameters:
  * `:codec` - codec used
  * `:width` - width of the received video (default: `640`)
  * `:height` - height of the received video (default: `480`)
  * `:framerate` - framerate of the received video (default: `30.0`)
  * `:expected_framerate` - framerate of the video source (default: `nil`).
    If set to `nil`, will be inferred from `framerate`
  """

  use Bunch.Access
  alias ExRTCScore.Utils

  @defaults %{
    codec: nil,
    width: 640,
    height: 480,
    framerate: 30.0,
    expected_framerate: nil
  }

  @type t :: %__MODULE__{
          codec: :h264 | :vp8 | :vp9 | :av1 | nil,
          width: pos_integer() | nil,
          height: pos_integer() | nil,
          framerate: number() | nil,
          expected_framerate: number() | nil
        }

  @enforce_keys []

  defstruct @enforce_keys ++
              [
                codec: nil,
                width: nil,
                height: nil,
                framerate: nil,
                expected_framerate: nil
              ]

  @doc false
  @spec codec_factor(t()) :: float()
  def codec_factor(%__MODULE__{codec: :h264}), do: 1.0
  def codec_factor(%__MODULE__{codec: :vp8}), do: 1.0
  # assuming approx. 83% of vp8/h264 bitrate for the same quality
  def codec_factor(%__MODULE__{codec: :vp9}), do: 1.2
  # assuming approx. 70% of vp8/h264 bitrate for the same quality
  def codec_factor(%__MODULE__{codec: :av1}), do: 1.43

  @doc false
  @spec normalise(t()) :: t()
  def normalise(%__MODULE__{} = config) do
    config = Utils.put_defaults_if_nil(config, @defaults)

    config
    |> Map.update!(:expected_framerate, fn
      nil -> config.framerate
      framerate -> framerate
    end)
  end
end
