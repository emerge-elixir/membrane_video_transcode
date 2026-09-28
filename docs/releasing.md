# Release checklist

Releases are published manually. CI and the commands below do not publish anything unless the
final `mix hex.publish` command is explicitly run.

## Scope and prerequisites

- The first release is `0.1.0`, a source-built, Linux-only decoder package. Do not advertise
  encoders, composed transcoding, macOS/Windows, or precompiled NIFs.
- Raspberry Pi support is **unvalidated in `0.1.0`**. Its build integration remains included,
  but Raspberry Pi target builds, all-features checks, and hardware qualification are not release
  gates for this version. Keep this limitation visible in the README and changelog.
- Use the Elixir/OTP versions in `.tool-versions`, Rust 1.91+, and the native prerequisites in
  the [README](../README.md#native-build-requirements).
- Confirm package ownership/name availability on Hex and access to the GitHub repository.
  Existing modules under `Membrane.*` must not conflict with other plugins in the consuming app.
- Review the Apache-2.0 license and the licenses of any native libraries being distributed.
  FFmpeg is supplied by the system, not bundled in this package.

## Validate the release candidate

1. Set the intended version in `mix.exs` and `native/video_decoder/Cargo.toml`; refresh the
   native lockfile if necessary. Finalize the matching `CHANGELOG.md` entry with the release date.
   Keep the README dependency example in sync with the release series.
2. Fetch dependencies and run the checks from the repository root:

   ```sh
   mix deps.get
   mix format --check-formatted
   mix compile --warnings-as-errors
   mix test
   mix docs --warnings-as-errors

   cargo fmt --manifest-path native/video_decoder/Cargo.toml --all -- --check
   cargo test --manifest-path native/video_decoder/Cargo.toml --locked
   cargo clippy --manifest-path native/video_decoder/Cargo.toml --locked --all-targets -- -D warnings
   cargo build --manifest-path native/video_decoder/Cargo.toml --locked --release

   bash scripts/check_package.sh
   ```

   The package smoke test builds the actual Hex archive, checks required sources and excludes
   compiled artifacts, then compiles an isolated production consumer against its extracted
   contents. It resolves Hex dependencies without the repository's `mix.lock` and loads the NIF
   to initialize/flush/close both software codecs. It needs network access to Hex and crates.io,
   but no hardware device. It does not test actual video decoding or hardware interoperability.

3. On hardware being qualified for this release (excluding Raspberry Pi), decode representative
   H.264/H.265 streams, verify raw output and DMA-BUF import/fence handling, and exercise EOS,
   held-frame backpressure, abandonment, and shutdown. Record the FFmpeg build, GPU/driver,
   kernel, and target tested. CI does not certify VAAPI or V4L2 hardware support.
   The [Raspberry Pi 5 checklist](rpi5_support.md) is retained for future qualification only.
4. Inspect the payload and rendered docs before publishing:

   ```sh
   mix hex.build --unpack --output /tmp/membrane_video_transcode-release
   ```

   Use a fresh output directory. The package must include Elixir source, the native crate source,
   `Cargo.toml`, `Cargo.lock`, README, license, changelog, and guides. It must not contain
   `priv/native` binaries, native `target`, `_build`, `deps`, credentials, or local paths.
   Open `doc/index.html` and check examples, API links, and versioned source links.

## Publish (maintainer only)

After CI and in-scope hardware qualification pass and the release changes are committed
(Raspberry Pi qualification is not required for `0.1.0`):

1. Authenticate using `mix hex.user auth` (never commit credentials), then run
   `mix hex.publish --dry-run`. Some Hex versions require authentication even for a dry run;
   unauthenticated CI validates with `mix hex.build` and `mix docs` instead. The dry run must not
   upload a release.
2. Create and push the matching annotated Git tag, for example `v0.1.0`. ExDoc source links use
   this tag, so it must point to the published commit.
3. Run `mix hex.publish` in the default development environment. Review the package summary and
   confirm interactively. This publishes both the package and the ExDoc documentation.
4. Verify the release on Hex and HexDocs, and install it in a fresh application using only
   `{:membrane_video_transcode, "~> 0.1.0"}`. Compile and run on a supported Linux host.

Do not publish with `MIX_ENV=prod`: ExDoc is a development-only dependency. Do not publish again
just to rerun validation; use `mix hex.publish --dry-run` instead.
