#!/usr/bin/env bash
# Build the actual Hex payload and consume it without checkout artifacts or config.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

mix hex.build --output "$work_dir/package.tar"
mkdir "$work_dir/envelope" "$work_dir/package"
tar -xf "$work_dir/package.tar" -C "$work_dir/envelope"
tar -tzf "$work_dir/envelope/contents.tar.gz" > "$work_dir/manifest"

for required in mix.exs LICENSE README.md CHANGELOG.md \
  native/video_decoder/Cargo.toml native/video_decoder/Cargo.lock \
  native/video_decoder/src/lib.rs lib/membrane/h264/decoder.ex lib/membrane/h265/decoder.ex; do
  grep -Fxq "$required" "$work_dir/manifest" || {
    echo "Missing package file: $required" >&2
    exit 1
  }
done

if grep -E '(^|/)(_build|deps|target|priv|\.git)(/|$)|\.(so|dylib|dll|beam)$' "$work_dir/manifest"; then
  echo "Package contains build artifacts or non-source directories" >&2
  exit 1
fi

tar -xzf "$work_dir/envelope/contents.tar.gz" -C "$work_dir/package"
mkdir "$work_dir/consumer"
cd "$work_dir/consumer"

cat > mix.exs <<'ELIXIR'
defmodule PackageSmoke.MixProject do
  use Mix.Project

  def project do
    [
      app: :package_smoke,
      version: "0.0.0",
      deps: [{:membrane_video_transcode, path: "../package"}]
    ]
  end

  def application, do: [extra_applications: [:logger]]
end
ELIXIR

cat > smoke.exs <<'ELIXIR'
alias Membrane.VideoTranscode.Decoder.Native

true = Code.ensure_loaded?(Membrane.H264.Decoder)
true = Code.ensure_loaded?(Membrane.H265.Decoder)

# Exercise NIF loading and both codecs without requiring a GPU or checkout config.
for codec <- [:h264, :h265] do
  decoder = Native.create(codec, :raw, :NV12, "", :software)
  true = is_reference(decoder)
  {:ok, 0, 0, :NV12} = Native.get_metadata(decoder)
  {:ok, [], []} = Native.flush(decoder)
  :ok = Native.close(decoder)
end

{:ok, dispatcher} = Native.start_release_dispatcher()
{:ok, true} = Native.close_release_dispatcher(dispatcher, 1_000)
IO.puts("Hex package consumer smoke test passed")
ELIXIR

# Resolve afresh: a library's mix.lock and config are not inherited by its consumers.
unset MIX_DEPS_PATH MIX_BUILD_PATH MIX_BUILD_ROOT CARGO_TARGET_DIR
export MIX_ENV=prod
mix deps.get
mix compile --warnings-as-errors
mix run --no-compile smoke.exs
