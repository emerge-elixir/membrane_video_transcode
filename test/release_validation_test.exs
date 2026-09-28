defmodule ReleaseValidationTest do
  use ExUnit.Case, async: true

  @moduletag :tmp_dir

  setup %{tmp_dir: dir} do
    File.mkdir_p!(Path.join(dir, "scripts"))
    File.mkdir_p!(Path.join(dir, "native/video_decoder"))

    File.cp!(
      Path.expand("../scripts/check_release.sh", __DIR__),
      Path.join(dir, "scripts/check_release.sh")
    )

    File.write!(Path.join(dir, "mix.exs"), "  @version \"0.1.0\"\n")

    File.write!(
      Path.join(dir, "native/video_decoder/Cargo.toml"),
      "[package]\nversion = \"0.1.0\"\n"
    )

    File.write!(Path.join(dir, "CHANGELOG.md"), "# Changelog\n\n## 0.1.0 - 2026-09-07\n")
    git!(dir, ["init", "--quiet"])
    git!(dir, ["add", "."])
    git!(dir, ["commit", "--quiet", "-m", "Release fixture"])
    git!(dir, ["tag", "-a", "v0.1.0", "-m", "Release 0.1.0"])
    :ok
  end

  test "accepts matching versions and a dated changelog at an annotated tag", %{tmp_dir: dir} do
    assert {output, 0} = check_release(dir)
    assert output =~ "Validated release v0.1.0"
  end

  test "also accepts lightweight release tags", %{tmp_dir: dir} do
    git!(dir, ["tag", "-d", "v0.1.0"])
    git!(dir, ["tag", "v0.1.0"])
    assert {_, 0} = check_release(dir)
  end

  test "rejects branch names and tags that do not match the package version", %{tmp_dir: dir} do
    for ref <- ["main", "0.1.0", "v0.2.0"] do
      assert {output, 1} = check_release(dir, ref)
      assert output =~ "must equal v0.1.0"
    end
  end

  test "rejects mismatched Mix and Cargo versions", %{tmp_dir: dir} do
    File.write!(
      Path.join(dir, "native/video_decoder/Cargo.toml"),
      "[package]\nversion = \"0.2.0\"\n"
    )

    assert {output, 1} = check_release(dir)
    assert output =~ "Mix version 0.1.0 does not match Cargo version 0.2.0"
  end

  test "rejects missing manifest versions", %{tmp_dir: dir} do
    File.write!(Path.join(dir, "mix.exs"), "")
    assert {output, 1} = check_release(dir)
    assert output =~ "Failed to resolve Mix/Cargo project versions"
  end

  test "rejects missing tags", %{tmp_dir: dir} do
    git!(dir, ["tag", "-d", "v0.1.0"])
    assert {output, 1} = check_release(dir)
    assert output =~ "Checked-out commit is not exact release tag v0.1.0"
  end

  test "rejects a release tag pointing at another commit", %{tmp_dir: dir} do
    git!(dir, ["commit", "--allow-empty", "-m", "After release"])
    assert {output, 1} = check_release(dir)
    assert output =~ "Checked-out commit is not exact release tag v0.1.0"
  end

  test "rejects undated, malformed, or wrong-version changelog headings", %{tmp_dir: dir} do
    for heading <- [
          "## 0.1.0 (unreleased)",
          "## 0.1.0 - 2026-9-7",
          "## 0.1.0 - 2026-09-07 (unreleased)",
          "## 0.2.0 - 2026-09-07",
          "## 0x1x0 - 2026-09-07"
        ] do
      File.write!(Path.join(dir, "CHANGELOG.md"), heading <> "\n")
      assert {output, 1} = check_release(dir)
      assert output =~ "CHANGELOG.md must contain: ## 0.1.0 - YYYY-MM-DD"
    end
  end

  defp check_release(dir, tag \\ "v0.1.0") do
    System.cmd("bash", [Path.join(dir, "scripts/check_release.sh"), tag], stderr_to_stdout: true)
  end

  defp git!(dir, args) do
    config = [
      "-c",
      "user.name=Release Test",
      "-c",
      "user.email=release@example.invalid",
      "-c",
      "commit.gpgsign=false",
      "-c",
      "tag.gpgsign=false"
    ]

    assert {_, 0} = System.cmd("git", config ++ args, cd: dir, stderr_to_stdout: true)
  end
end
