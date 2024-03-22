defmodule ExRTCScoreTest do
  use ExUnit.Case

  alias ExRTCScore.{Config, Stat}

  @default_video_stat %Stat{
    bitrate: 200_000,
    packet_loss: 0,
    buffer_delay: 0,
    round_trip_time: 0,
    track_config: %Config.Video{
      codec: :h264,
      width: 640,
      height: 480,
      framerate: 24
    }
  }

  @default_audio_stat %Stat{
    bitrate: 50_000,
    packet_loss: 0,
    buffer_delay: 0,
    round_trip_time: 0,
    track_config: %Config.Audio{
      fec: true,
      dtx: false,
      red: false
    }
  }

  describe "video score" do
    test "is very high in perfect conditions" do
      assert_video_score_between(
        %{bitrate: 13_000_000},
        %{width: 1280, height: 720, framerate: 30},
        4.75,
        5.0
      )
    end

    test "is average in average bitrate conditions" do
      assert_video_score_between(%{bitrate: 400_000}, %{}, 3.0, 4.0)
    end

    test "is average in average framerate conditions" do
      assert_video_score_between(
        %{bitrate: 400_000},
        %{framerate: 25, expected_framerate: 30},
        3.0,
        4.0
      )
    end

    test "is below average in low bitrate conditions" do
      assert_video_score_between(%{bitrate: 200_000}, %{}, 2.5, 3.5)
    end

    test "is below average in average bitrate, low framerate conditions" do
      assert_video_score_between(
        %{bitrate: 500_000},
        %{framerate: 8, expected_framerate: 25},
        2.0,
        3.0
      )
    end

    test "is 1.0 in worst bitrate conditions" do
      assert_video_score_between(%{bitrate: 1000}, %{}, 1.0, 1.0)
    end

    test "is 1.0 in worst framerate conditions" do
      assert_video_score_between(
        %{bitrate: 10_000_000},
        %{framerate: 1, expected_framerate: 30},
        1.0,
        1.0
      )
    end

    test "is 1.0 if no framerate is received" do
      assert_video_score_between(%{bitrate: 100_000}, %{framerate: 0.0}, 1.0, 1.0)
    end

    test "depends on bitrate" do
      assert score_video_stat(%{bitrate: 100_000}, %{}) <
               score_video_stat(%{bitrate: 200_000}, %{})
    end

    test "depends on codec" do
      assert score_video_stat(%{}, %{codec: :vp8}) < score_video_stat(%{}, %{codec: :vp9})
    end

    test "depends on framerate" do
      assert score_video_stat(%{}, %{framerate: 15, expected_framerate: 30}) <
               score_video_stat(%{}, %{framerate: 15, expected_framerate: 15})
    end

    test "depends on resolution" do
      assert score_video_stat(%{}, %{width: 640, height: 480}) <
               score_video_stat(%{}, %{width: 100, height: 50})
    end
  end

  describe "audio score" do
    test "is very high in perfect conditions" do
      assert_audio_score_between(%{bitrate: 100_000}, %{}, 4.4, 4.5)
    end

    test "is average in average conditions" do
      assert_audio_score_between(%{packet_loss: 10}, %{}, 3.0, 3.5)
    end

    test "is below average with high packet loss" do
      assert_audio_score_between(%{packet_loss: 30}, %{}, 1.5, 2.0)
    end

    test "is near 1.0 with extreme packet loss" do
      assert_audio_score_between(%{packet_loss: 95}, %{}, 1.0, 1.2)
    end

    test "is near 1.0 with 2 seconds delay" do
      assert_audio_score_between(%{round_trip_time: 2_000}, %{}, 1.0, 1.2)
    end

    test "depends on bitrate" do
      assert score_audio_stat(%{bitrate: 50_000}, %{}) <
               score_audio_stat(%{bitrate: 100_000}, %{})
    end

    test "depends on buffer delay" do
      assert score_audio_stat(%{buffer_delay: 100}, %{}) <
               score_audio_stat(%{buffer_delay: 10}, %{})
    end

    test "depends on fec being enabled with packet loss" do
      assert score_audio_stat(%{packet_loss: 10}, %{fec: false}) <
               score_audio_stat(%{packet_loss: 10}, %{fec: true})
    end

    test "depends on red being enabled with packet loss" do
      assert score_audio_stat(%{packet_loss: 10}, %{red: false}) <
               score_audio_stat(%{packet_loss: 10}, %{red: true})
    end

    test "depends on dtx being enabled" do
      assert score_audio_stat(%{bitrate: 10_000}, %{dtx: false}) <
               score_audio_stat(%{bitrate: 10_000}, %{dtx: true})
    end
  end

  defp assert_video_score_between(stat, track_config, lower, upper) do
    score = score_video_stat(stat, track_config)
    assert score >= lower and score <= upper
  end

  defp assert_audio_score_between(stat, track_config, lower, upper) do
    score = score_audio_stat(stat, track_config)
    assert score >= lower and score <= upper
  end

  defp score_video_stat(stat, track_config), do: score_stat(:video, stat, track_config)
  defp score_audio_stat(stat, track_config), do: score_stat(:audio, stat, track_config)

  defp score_stat(kind, stat, track_config) do
    if(kind == :video, do: @default_video_stat, else: @default_audio_stat)
    |> Map.update!(:track_config, &Map.merge(&1, track_config))
    |> Map.merge(stat)
    |> ExRTCScore.score()
  end
end
