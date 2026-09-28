#!/usr/bin/env bash
# Validate the exact tagged source before allowing a Hex release.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

if [[ $# -ne 1 ]]; then
  echo "Usage: bash scripts/check_release.sh <v-prefixed-tag>" >&2
  exit 1
fi

project_version="$(awk -F'"' '/^  @version "/ { print $2; exit }' mix.exs)"
cargo_version="$(awk -F'"' '$0 == "[package]" { in_package=1; next } in_package && /^version = "/ { print $2; exit }' native/video_decoder/Cargo.toml)"

if [[ -z "$project_version" || -z "$cargo_version" ]]; then
  echo "Failed to resolve Mix/Cargo project versions" >&2
  exit 1
fi

if [[ "$project_version" != "$cargo_version" ]]; then
  echo "Mix version ${project_version} does not match Cargo version ${cargo_version}" >&2
  exit 1
fi

expected_tag="v${project_version}"
if [[ "$1" != "$expected_tag" ]]; then
  echo "Release tag $1 must equal ${expected_tag}" >&2
  exit 1
fi

if ! tag_commit="$(git rev-parse --verify "refs/tags/${expected_tag}^{commit}")" ||
   [[ "$tag_commit" != "$(git rev-parse HEAD)" ]]; then
  echo "Checked-out commit is not exact release tag ${expected_tag}" >&2
  exit 1
fi

if ! awk -v version="$project_version" '
  $1 == "##" && $2 == version && $3 == "-" &&
  $4 ~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/ && NF == 4 { found=1 }
  END { exit !found }
' CHANGELOG.md; then
  echo "CHANGELOG.md must contain: ## ${project_version} - YYYY-MM-DD" >&2
  exit 1
fi

echo "Validated release ${expected_tag} at ${tag_commit}"
