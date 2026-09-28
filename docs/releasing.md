# Release checklist

Releases follow the same tag-gated Hex publishing flow as the Emerge video-interop libraries.
Pushing a `v*` tag to `emerge-elixir/membrane_video_transcode` runs the full CI matrix, validates
the release tag, and publishes the package and documentation through the GitHub `hex` environment.
Branch pushes, pull requests, forks, and `workflow_dispatch` runs only validate; they do not publish.

The pipeline in `.github/workflows/ci.yml` is:

1. `check`: formatting, Elixir/Rust builds and tests, docs, and the isolated Hex consumer smoke test.
2. `release-tag`: require the exact checked-out tag to match both Mix and Cargo versions and a
   dated changelog entry.
3. `publish-hex`: wait for any `hex` environment approval, revalidate the tag, build the package
   and docs, then publish them separately using `HEX_API_KEY`. Releases for the same tag are
   serialized and are not cancelled by newer runs.

This is a source-only Hex release. There are no precompiled NIF assets or crates.io publishing jobs.

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

## One-time GitHub setup

- Create a GitHub Actions environment named `hex`, matching the sibling Emerge libraries.
- Configure required reviewers if releases should wait for maintainer approval. Restrict the
  environment's deployment policy to release tags (`v*`); the workflow also checks the repository
  and requires a tag-push event.
- Store a Hex publishing key as the environment secret `HEX_API_KEY` (a repository secret with
  the same name also works). Grant it publishing access for this package; never commit it.
- Protect release tags against deletion or movement. The workflow checks out the triggering commit
  and verifies that the release tag still points to it, including after an approval wait.

The workflow's `GITHUB_TOKEN` needs only `contents: read`. It does not need a Cargo registry token
or GitHub release write access. Environment reviewers and secrets must be configured in GitHub;
the workflow file cannot create them.

## Validate the release candidate

1. Set the intended version in `mix.exs` and `native/video_decoder/Cargo.toml`; refresh the
   native lockfile if necessary. Replace the unreleased `CHANGELOG.md` heading with a dated entry
   in the format `## 0.1.0 - YYYY-MM-DD`, using the intended version and actual release date.
   Keep the README dependency example in sync with the release series. An unreleased heading
   intentionally blocks publication.
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

## Publish a tagged release (maintainer only)

After CI and in-scope hardware qualification pass and the release changes are committed
(Raspberry Pi qualification is not required for `0.1.0`):

1. Create an annotated tag on the reviewed release commit and validate it locally:

   ```sh
   git tag -a v0.1.0 -m "Release 0.1.0"
   bash scripts/check_release.sh v0.1.0
   ```

   Use the intended release version. ExDoc source links use this tag, so it must point to the
   published commit. The validation script does not publish anything.
2. Push the tag with `git push origin v0.1.0`. **This starts the publishing pipeline.** The tag
   must pass the complete CI matrix and the release-version/changelog gate before publishing.
3. Review the tagged CI run and approve the `hex` environment deployment if required. Without
   configured reviewers, publication proceeds automatically after validation. CI publishes to
   public Hex with `mix hex.publish package --yes`, followed by `mix hex.publish docs --yes`.
4. Verify the release on Hex and HexDocs, and install it in a fresh application using only
   `{:membrane_video_transcode, "~> 0.1.0"}`. Compile and run on a supported Linux host.

Do not move a published tag or publish locally while its CI release job is running. Version bumps,
changelog dates, hardware qualification, and any configured approval remain maintainer actions.

## Recovery and local dry runs

Failures before publication can be corrected before tagging, or retried using GitHub's failed-job
rerun for a transient failure. The manual `workflow_dispatch` trigger only reruns validation; it
is not a way to bypass the release gates.

If the package was published but the documentation step failed, do not blindly rerun the package
publication. Check out the exact release tag, fetch dependencies, regenerate the docs, and publish
only the docs with `mix hex.publish docs` using maintainer authentication. Check Hex first when a
publish step's result is uncertain.

For local validation without uploading, use `mix hex.publish --dry-run`. Some Hex versions require
`mix hex.user auth` even for a dry run; unauthenticated CI uses `mix hex.build` and `mix docs`.
Never commit credentials. Do not publish with `MIX_ENV=prod`: ExDoc is a development-only dependency.
