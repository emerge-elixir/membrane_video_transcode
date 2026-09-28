# Membrane Video Transcode

[![Hex.pm](https://img.shields.io/hexpm/v/membrane_video_transcode.svg)](https://hex.pm/packages/membrane_video_transcode)
[![HexDocs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/membrane_video_transcode)
[![CI](https://img.shields.io/badge/CI-GitHub_Actions-2088FF?logo=githubactions&logoColor=white)](https://github.com/emerge-elixir/membrane_video_transcode/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/emerge-elixir/membrane_video_transcode.svg)](https://github.com/emerge-elixir/membrane_video_transcode/blob/main/LICENSE)

Membrane Video Transcode provides video decoding for the
[Membrane Framework](https://membrane.stream).

It turns H.264 and H.265 streams into decoded frames using FFmpeg, with either a software
or hardware decoder. You can receive ordinary raw video buffers, or pass hardware-backed
frames to another consumer without copying them into Elixir binaries.

Decoding and presentation are separate concerns. This package does not open displays or
perform DRM/KMS modesetting. To display frames, pair it with a consumer and a transport such as
[`membrane_video_interop`](https://github.com/emerge-elixir/membrane_video_interop).

## Project status

The initial `0.1.0` release provides decoding only. Encoding and composed decode/encode
transcoding are not implemented yet.

This is a **Linux-only, source-built package**. It compiles a Rust NIF against your system
FFmpeg libraries; precompiled NIFs, macOS, and Windows are not currently supported.

**Raspberry Pi support is unvalidated in `0.1.0`.** The build integration is included, but
Raspberry Pi target builds and hardware decoding are not qualified for this release.

## Installation

Add `membrane_video_transcode` to your dependencies:

```elixir
def deps do
  [
    {:membrane_video_transcode, "~> 0.1.0"}
  ]
end
```

Until the initial Hex release is published, use a Git dependency instead:

```elixir
{:membrane_video_transcode, github: "emerge-elixir/membrane_video_transcode"}
```

`video_interop` is included as a dependency. Source, parser, pacing, and sink plugins are
separate dependencies that you add according to your pipeline. A transport or renderer is
not required for raw output.

This package defines `Membrane.H264.Decoder`, `Membrane.H265.Decoder`, and
`Membrane.Instrumentation`. Do not combine it with other packages that define the same modules.

### Native build requirements

Before compiling the package, install:

- Elixir 1.17 or later and a compatible Erlang/OTP release. Development uses `.tool-versions`.
- Rust/Cargo 1.91 or later (Rust 2024 edition).
- A C compiler, `pkg-config`, and Clang/libclang for bindgen.
- FFmpeg development headers and shared libraries, including `libavcodec`, `libavformat`,
  `libavutil`, `libavdevice`, `libavfilter`, `libswresample`, and `libswscale`.

For example, on Ubuntu 24.04 (FFmpeg 6.1), after installing Elixir/Erlang and Rust:

```sh
sudo apt-get update
sudo apt-get install build-essential pkg-config clang libclang-dev \
  libavcodec-dev libavformat-dev libavutil-dev libavdevice-dev \
  libavfilter-dev libswresample-dev libswscale-dev
mix deps.get
mix compile
```

If FFmpeg is installed outside the system prefix, configure `PKG_CONFIG_PATH` (or the Rust
FFmpeg bindings' `FFMPEG_DIR`) and the runtime library search path. Your deployed application
also needs compatible FFmpeg shared libraries; this package does not bundle them.

Hardware decoding additionally needs the appropriate kernel/userspace drivers and permission
to access the render or video device.

## Decoding a video

The building blocks are `Membrane.H264.Decoder` and `Membrane.H265.Decoder`. Place a decoder
after a parser in your Membrane pipeline so that it receives complete access units rather
than arbitrary chunks of a file. H.264 input must also use Annex B stream structure.

Let's start with copied raw frames, which do not require a GPU:

```elixir
%Membrane.H264.Decoder{
  output: :raw,
  decoder: :software,
  output_format: :NV12
}
```

`output: :raw` produces binary buffer payloads described by a `%Membrane.RawVideo{}` stream
format. `output_format` chooses the copied frame's pixel format. Here we use NV12; other
options include I420, RGB, BGRA, and RGBA.

For an H.265 stream, use the other decoder with the same options:

```elixir
%Membrane.H265.Decoder{
  output: :raw,
  decoder: :software,
  output_format: :NV12
}
```

These structs configure elements inside a pipeline; they do not read a file or start decoding
on their own. The source, parser, and downstream consumer are still up to your application.

## Choosing a decoder backend

Once the basic pipeline is in place, choose a backend that matches your deployment:

| Backend | Use |
| --- | --- |
| `:software` | Copied raw output without a hardware decoder. Cannot produce DMA-BUF storage. |
| `:vaapi` | Linux GPU decoding through a render node, such as `/dev/dri/renderD128`. Recommended for desktop hardware. |
| `:v4l2request` | Requires matching FFmpeg codecs and target hardware. |
| `:v4l2m2m` | Requires matching FFmpeg codecs and target hardware. |
| `:auto` | Probes hardware codecs before falling back to the software decoder. |

Prefer an explicit backend when you know the target hardware. In particular, software fallback
cannot satisfy a request for DMA-BUF output.

## Passing decoded frames to a consumer

Raw output is convenient when your next element expects binary data. When a consumer can work
with hardware-backed frames, use `output: :dmabuf` instead. This is the default output mode.

The decoder then emits leased `%VideoInterop.Frame{}` values directly as Membrane buffer
payloads. The current format is NV12 DMA-BUF with a uniform modifier and a concrete
`%VideoInterop.SyncFile{}` acquire fence.

Here is a pipeline fragment that decodes an H.264 file with VAAPI and hands the frames to a
consumer. It additionally requires the file source, H.264 parser, realtimer, and
[`membrane_video_interop`](https://github.com/emerge-elixir/membrane_video_interop) transport
plugins. `consumer` is your application's consumer handle.

```elixir
child(:file, %Membrane.File.Source{
  location: "clip.h264",
  content_format: Membrane.H264
})
|> child(:parser, %Membrane.H264.Parser{
  output_alignment: :au,
  output_stream_structure: :annexb,
  generate_best_effort_timestamps: %{framerate: {24, 1}}
})
|> child(:realtimer, Membrane.Realtimer)
|> child(:decoder, %Membrane.H264.Decoder{
  output: :dmabuf,
  decoder: :vaapi,
  hw_device: "/dev/dri/renderD128",
  max_in_flight: 4
})
|> child(:sink, %Membrane.VideoInterop.Sink{
  submit: {MyConsumer, :submit, [consumer]},
  target: :preview
})
```

The parser produces access units and timestamps. The realtimer paces file input before hardware
decode so leased surfaces are not decoded far ahead of playback. The decoder uses the selected
render node, with at most four outstanding frame leases.

The sink calls `MyConsumer.submit(frame, :preview, consumer)`. Your callback must consume the
frame before returning normally: either transfer it to another VideoInterop consumer or release
it with `VideoInterop.release/1` when you are done. Holding a frame also holds its native storage,
so releasing frames is part of the consumer's responsibility.

The decoder exports the DMA-BUF reservation fence with `DMA_BUF_IOCTL_EXPORT_SYNC_FILE` after
each decoded frame is received. Native frame storage and the acquire fence remain alive until
the lease is released. Descriptor file descriptors are local to one OS process.

## Cross-compiling for Nerves

When `NERVES_SDK_SYSROOT` is set, the package maps the Nerves C compiler prefix to a Rust target
and passes the target linker and FFmpeg paths to Rustler. The current mapping includes the
standard ARMv6, ARMv7, AArch64, and x86_64 Nerves targets.

For Raspberry Pi, the integration expects the `ffmpeg-rpi` libraries and headers supplied by
`colibri-cam/nerves_system_gs`, or an equivalent patched FFmpeg build with V4L2 Request, DRM,
and SAND support. Nerves cross-compilation enables the crate's `rpi` feature, which forwards to
`ffmpeg-next/rpi`. That feature exposes the patched pixel formats; it does not supply FFmpeg.
Stock upstream FFmpeg is not a substitute for this target contract.

Raspberry Pi remains **unvalidated for `0.1.0`**, not a release blocker. See the
[Raspberry Pi 5 guide](docs/rpi5_support.md) for build requirements and a future qualification
checklist.

## Instrumentation and development

`Membrane.Instrumentation` provides runtime-configurable pipeline instrumentation. See the
[API documentation](https://hexdocs.pm/membrane_video_transcode/Membrane.Instrumentation.html)
for the available session and tracing functions.

The [release checklist](docs/releasing.md) covers tests, native checks, and package validation.
Release history is tracked in the [changelog](CHANGELOG.md).

## License

Apache-2.0; see [LICENSE](https://github.com/emerge-elixir/membrane_video_transcode/blob/main/LICENSE).
FFmpeg and other native dependencies have their own licenses. Review the licenses and build
options of the libraries you distribute, particularly GPL or nonfree FFmpeg configurations.
