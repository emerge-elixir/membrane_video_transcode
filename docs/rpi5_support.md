# Raspberry Pi 5 Decoder Support

**Raspberry Pi support is unvalidated in `0.1.0`.** The build integration is included, but
Raspberry Pi target builds and hardware decoding have not been qualified for this release.
The requirements and checklist below are retained for future validation, not as release gates.

`membrane_video_transcode` remains codec-only: display, DRM/KMS, and presentation concerns belong to
consumers outside this package.

## Build requirements

- Cross-compile `native/video_decoder` for `aarch64-unknown-linux-gnu` when the target system uses
  the standard 64-bit Raspberry Pi kernel.
- Use the `ffmpeg-rpi` libraries and headers supplied by `colibri-cam/nerves_system_gs`, or an
  equivalent Raspberry Pi-patched FFmpeg build, through the Nerves sysroot. Stock upstream FFmpeg
  does not currently provide the same V4L2 Request, DRM PRIME, and Raspberry Pi pixel-format
  contract.
- Build `ffmpeg-rpi` with V4L2 Request, DRM, and SAND support. Enable any V4L2 M2M codec used by a
  selected deployment backend as well.
- Keep the `video-interop` Rust source aligned with the Elixir `video_interop` dependency.

## Runtime contract

Select `:v4l2request` or `:v4l2m2m` explicitly after confirming the codec exposed by the target
FFmpeg build. DMA-BUF output must satisfy the same contract as VAAPI output:

- NV12 `%VideoInterop.Format{}` stream format;
- `%VideoInterop.Frame{}` buffer payloads;
- complete DMA-BUF allocation sizes and exact planes;
- one uniform explicit modifier per stream;
- a concrete acquire sync-file exported from the DMA-BUF reservation object;
- one bounded lease that retires all native frame, descriptor, and synchronization resources.

The `rpi` Cargo feature forwards to `ffmpeg-next/rpi`. This is required when compiling against
`ffmpeg-rpi` headers so `ffmpeg-next` recognizes the additional SAND and RPI4 pixel formats. The
feature does not build or install FFmpeg; the Nerves system must supply the matching patched
libraries. It also does not add display or scanout behavior.

## Future qualification

These checks are not required for the `0.1.0` release. When qualifying Raspberry Pi support in a
future release, use the patched target FFmpeg headers/libraries, not stock desktop FFmpeg.
`--all-features` enables `rpi`, which references SAND/RPI4 pixel formats absent from upstream
FFmpeg. A desktop build failure due to these missing formats is not target qualification.

Run Clippy in the target build environment with its linker/sysroot configured:

```sh
cargo clippy --manifest-path native/video_decoder/Cargo.toml --locked \
  --all-targets --all-features -- -D warnings
```

On physical Raspberry Pi 5 hardware:

1. Decode both H.264 and H.265 fixtures with the selected backend.
2. Validate every stream format and frame with `VideoInterop.validate/1`.
3. Confirm the advertised modifier imports on the intended consumer GPU.
4. Release every frame and verify the decoder lease owner drains at EOS and shutdown.
5. Exercise held-frame backpressure and abandonment without leaking DMA-BUF or sync-file FDs.
6. Run `cargo test`, Clippy with warnings denied, a release build, and the Elixir test suite against
   the target FFmpeg build.
