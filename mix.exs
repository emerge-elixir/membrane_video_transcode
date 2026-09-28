defmodule MembraneVideoTranscode.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/emerge-elixir/membrane_video_transcode"

  def project do
    [
      app: :membrane_video_transcode,
      version: @version,
      elixir: "~> 1.17",
      name: "Membrane Video Transcode",
      description:
        "Hardware-aware H.264 and H.265 decoding for Membrane with raw video and leased DMA-BUF output.",
      source_url: @source_url,
      package: package(),
      docs: docs(),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      rustler_opts: configure_rustler_cross_compile(System.get_env("NERVES_SDK_SYSROOT"))
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:membrane_core, "~> 1.2"},
      {:membrane_h264_format, "~> 0.6"},
      {:membrane_h265_format, "~> 0.2"},
      {:membrane_raw_video_format, "~> 0.4"},
      {:rustler, "~> 0.38.0", runtime: false},
      {:telemetry, "~> 1.0"},
      {:video_interop, "~> 0.1.0"}
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url},
      files: [
        "lib",
        "native/video_decoder/src",
        "native/video_decoder/Cargo.toml",
        "native/video_decoder/Cargo.lock",
        ".formatter.exs",
        "mix.exs",
        "README.md",
        "LICENSE",
        "CHANGELOG.md",
        "docs"
      ]
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: ["README.md", "CHANGELOG.md", "docs/rpi5_support.md", "docs/releasing.md"],
      groups_for_modules: [
        Decoders: [Membrane.H264.Decoder, Membrane.H265.Decoder],
        Instrumentation: [
          Membrane.Instrumentation,
          Membrane.Instrumentation.FrameTrace,
          Membrane.Instrumentation.Reporter,
          Membrane.Instrumentation.TraceToken
        ]
      ]
    ]
  end

  @nerves_rust_target_triple_mapping %{
    "armv6-nerves-linux-gnueabihf" => "arm-unknown-linux-gnueabihf",
    "armv7-nerves-linux-gnueabihf" => "armv7-unknown-linux-gnueabihf",
    "aarch64-nerves-linux-gnu" => "aarch64-unknown-linux-gnu",
    "x86_64-nerves-linux-musl" => "x86_64-unknown-linux-musl"
  }

  defp configure_rustler_cross_compile(nil), do: []

  defp configure_rustler_cross_compile(_target) do
    cc = System.get_env("CC")

    if cc do
      target_triple =
        cc
        |> Path.basename()
        |> String.split("-")
        |> Enum.drop(-1)
        |> Enum.join("-")
        |> then(&Map.get(@nerves_rust_target_triple_mapping, &1))

      upcase_target_triple =
        target_triple
        |> String.upcase()
        |> String.replace("-", "_")

      [
        target: target_triple,
        features: ["rpi"],
        env: [
          {"CARGO_TARGET_#{upcase_target_triple}_LINKER", cc},
          {"HOST_FFMPEG_DIR", System.get_env("NERVES_TOOLCHAIN")},
          {"FFMPEG_DIR", System.get_env("NERVES_SDK_SYSROOT") <> "/usr"},
          {"CFLAGS", ""},
          {"CC", ""}
        ]
      ]
    end
  end
end
