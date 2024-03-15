defmodule ExRTCScore do
  @moduledoc """
  Calculate the mean opinion score (MOS) of a video/audio stream.
  """

  alias ExRTCScore.{Config, Stat}

  @doc """
  Calculate the MOS from the provided parameters.

  Returns a floating point number from the range `[1.0, 5.0]` (both ends inclusive).
  """
  @spec score(Stat.t()) :: float()
  def score(stat) do
    stat
    |> Stat.normalise()
    |> calculate_score()
  end

  # Video score -- MOS calculation based on logarithmic regression
  defp calculate_score(%{track_config: %Config.Video{} = config} = stat) do
    codec_factor = Config.Video.codec_factor(config)
    delay = stat.buffer_delay + stat.round_trip_time / 2

    # These parameters were generated using logarithmic regression
    # on some very limited test data
    # They are based on the bits per pixel per frame metric (bPPPF)
    if stat.bitrate > 0.0 and config.framerate > 0.0 do
      pixels = config.width * config.height
      bits_per_pixel_per_frame = codec_factor * stat.bitrate / (pixels * config.framerate)

      base = clamp(0.56 * :math.log(bits_per_pixel_per_frame) + 5.36, 1.0, 5.0)

      # Consider clamping the thing in :math.log() with 1.0
      (base - 1.9 * :math.log(config.expected_framerate / config.framerate) - 0.002 * delay)
      |> clamp(1.0, 5.0)
      |> Float.round(2)
    else
      1.0
    end
  end

  # Audio score -- MOS calculation based on E-Model algorithm
  defp calculate_score(%{track_config: %Config.Audio{} = config} = stat) do
    # Assume packetisation delay of 20 ms
    delay = 20 + stat.buffer_delay + stat.round_trip_time / 2

    ie =
      cond do
        # Ignore audio bitrate in dtx mode
        config.dtx -> 8
        stat.bitrate > 0.0 -> clamp(55 - 4.6 * :math.log(stat.bitrate), 0, 30)
        true -> 6
      end

    bpl =
      cond do
        # With 2 packets redundancy, should be able to absorb 2 out of 3 packets lost
        # without impact on quality; in this case, we don't want to lower the score too much
        # even with significant loss rate (e.g. 10%)
        config.red -> 90
        config.fec -> 20
        true -> 10
      end

    ipl = ie + (100 - ie) * (stat.packet_loss / (stat.packet_loss + bpl))

    delay_factor =
      if delay > 150.0,
        do: 0.1 * (delay - 150.0),
        else: 0.0

    r0 = 100
    id = 0.03 * delay + delay_factor
    r = clamp(r0 - ipl - id, 0, 100)

    (1 + 0.035 * r + r * (r - 60) * (100 - r) * 7 / 1_000_000)
    |> clamp(1.0, 5.0)
    |> Float.round(2)
  end

  defp clamp(value, lower, upper), do: value |> max(lower) |> min(upper)
end
