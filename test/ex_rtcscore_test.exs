defmodule ExRTCScoreTest do
  use ExUnit.Case

  alias ExRTCScore.{Config, Stat}

  describe "video score" do
    test "is very high in perfect conditions" do
      stat = %Stat{
        bitrate: 13_000_000,
        packet_loss: 0,
        buffer_delay: 0,
        track_config: %Config.Video{
          codec: :h264,
          width: 1280,
          height: 720,
          framerate: 30.0
        }
      }

      assert ExRTCScore.score(stat) >= 4.75
      assert ExRTCScore.score(stat) <= 5.0
    end

    test "is average on average bitrate conditions" do
      stat = %Stat{
        bitrate: 400_000,
        packet_loss: 0,
        buffer_delay: 0,
        track_config: %Config.Video{codec: :h264}
      }

      assert ExRTCScore.score(stat) >= 3.0
      assert ExRTCScore.score(stat) <= 4.0
    end
  end
end
