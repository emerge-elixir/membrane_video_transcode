# Changelog

## 0.1.0 - 2026-09-28

Initial Hex release.

- H.264 Annex B and H.265 access-unit decoder elements for Membrane.
- Selectable VAAPI, V4L2 Request, V4L2 M2M, and software FFmpeg backends.
- Copied raw video output or bounded, leased NV12 DMA-BUF VideoInterop frames with sync-file fences.
- Runtime-configurable pipeline instrumentation.
- Nerves cross-compilation support, including Raspberry Pi-patched FFmpeg integration.
  Raspberry Pi target builds and hardware decoding are unvalidated in this release.

This release is Linux-only and builds its Rust NIF from source against system FFmpeg.
Encoding, composed transcoding, and display/presentation sinks are not included.
