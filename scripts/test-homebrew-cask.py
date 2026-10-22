#!/usr/bin/env python3
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
RENDERER = ROOT / "scripts/render-homebrew-cask.py"
TEMPLATE = ROOT / "packaging/homebrew/filbert.rb"
WORKFLOW = ROOT / ".github/workflows/release.yml"

SHA_A = "a" * 64
SHA_B = "b" * 64


def cask_job(workflow):
    match = re.search(r"\n  publish-homebrew-cask:\n(.*?)(?=\n  [a-z-]+:\n|\Z)", workflow, re.DOTALL)
    if not match:
        raise AssertionError("release.yml has no publish-homebrew-cask job")
    return match.group(1)


class RendererTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        self.cask = self.root / "Casks/filbert.rb"

    def tearDown(self):
        self.directory.cleanup()

    def run_renderer(self, version, sha256, template=TEMPLATE):
        return subprocess.run(
            [
                sys.executable,
                str(RENDERER),
                "--template", str(template),
                "--version", version,
                "--sha256", sha256,
                "--existing", str(self.cask),
                "--output", str(self.cask),
            ],
            capture_output=True,
            text=True,
        )

    def render_successfully(self, version, sha256):
        result = self.run_renderer(version, sha256)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.strip()

    def test_first_render_writes_the_cask(self):
        self.assertEqual(self.render_successfully("1.2.3", SHA_A), "update")

        cask = self.cask.read_text()
        self.assertIn('version "1.2.3"', cask)
        self.assertIn(f'sha256 "{SHA_A}"', cask)
        self.assertNotRegex(cask, r"@[A-Z0-9_]+@")

    def test_newer_version_replaces_the_cask(self):
        self.render_successfully("1.2.3", SHA_A)

        self.assertEqual(self.render_successfully("1.10.0", SHA_B), "update")
        self.assertIn('version "1.10.0"', self.cask.read_text())

    def test_older_version_never_replaces_the_cask(self):
        self.render_successfully("1.10.0", SHA_A)

        self.assertEqual(self.render_successfully("1.9.9", SHA_B), "skip")
        self.assertIn('version "1.10.0"', self.cask.read_text())

    def test_same_version_with_a_new_hash_replaces_the_cask(self):
        self.render_successfully("1.2.3", SHA_A)

        self.assertEqual(self.render_successfully("1.2.3", SHA_B), "update")
        self.assertIn(f'sha256 "{SHA_B}"', self.cask.read_text())

    def test_identical_render_is_skipped(self):
        self.render_successfully("1.2.3", SHA_A)
        before = self.cask.stat().st_mtime_ns

        self.assertEqual(self.render_successfully("1.2.3", SHA_A), "skip")
        self.assertEqual(self.cask.stat().st_mtime_ns, before)

    def test_rejects_versions_that_are_not_plain_semver(self):
        for version in ("v1.2.3", "1.2", "1.2.3-beta.1", "1.2.3+build", "01.2.3", ""):
            with self.subTest(version=version):
                result = self.run_renderer(version, SHA_A)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(self.cask.exists())

    def test_rejects_malformed_hashes(self):
        for sha256 in ("A" * 64, "a" * 63, "g" * 64, ""):
            with self.subTest(sha256=sha256):
                result = self.run_renderer("1.2.3", sha256)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(self.cask.exists())

    def test_rejects_a_template_with_an_unknown_placeholder(self):
        template = self.root / "template.rb"
        template.write_text(TEMPLATE.read_text() + '# @UNKNOWN@\n')

        result = self.run_renderer("1.2.3", SHA_A, template=template)

        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.cask.exists())

    def test_rejects_an_existing_cask_without_one_version(self):
        self.cask.parent.mkdir(parents=True)
        self.cask.write_text('cask "filbert" do\nend\n')

        result = self.run_renderer("1.2.3", SHA_A)

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.cask.read_text(), 'cask "filbert" do\nend\n')


class CaskTemplateTests(unittest.TestCase):
    def test_hands_updates_to_sparkle(self):
        template = TEMPLATE.read_text()

        self.assertIn("auto_updates true", template)
        self.assertIn('url "https://victorhqc.github.io/filbert/appcast.xml"', template)
        self.assertIn("strategy :sparkle", template)

    def test_installs_the_released_arm64_dmg(self):
        template = TEMPLATE.read_text()

        self.assertIn(
            "https://github.com/victorhqc/filbert/releases/download/"
            "v#{version}/Filbert-#{version}-arm64.dmg",
            template,
        )
        self.assertIn("depends_on arch: :arm64", template)
        self.assertIn("depends_on macos: :sonoma", template)

    def test_zap_keeps_the_claude_code_helper(self):
        zap = TEMPLATE.read_text().split("zap trash:", 1)[1]

        self.assertIn('"~/.cache/filbert"', zap)
        self.assertIn('"~/Library/Logs/Filbert"', zap)
        self.assertNotIn("~/.claude", zap)


class WorkflowTests(unittest.TestCase):
    def test_cask_job_runs_only_after_a_successful_release(self):
        job = cask_job(WORKFLOW.read_text())

        self.assertIn("needs: release", job)
        self.assertIn("needs.release.result == 'success'", job)

    def test_cask_job_isolates_the_deploy_key(self):
        workflow = WORKFLOW.read_text()
        job = cask_job(workflow)

        self.assertIn("environment: homebrew-tap", job)
        self.assertIn("contents: read", job)
        self.assertNotIn("contents: write", job)
        self.assertIn('[[ -n "$HOMEBREW_TAP_DEPLOY_KEY" ]]', job)
        self.assertNotIn("APPLE_", job)
        self.assertNotIn("SPARKLE_", job)
        self.assertEqual(workflow.count("HOMEBREW_TAP_DEPLOY_KEY: ${{"), job.count("HOMEBREW_TAP_DEPLOY_KEY: ${{"))

    def test_cask_job_hashes_the_published_release_asset(self):
        job = cask_job(WORKFLOW.read_text())

        self.assertIn('gh release download "$TAG_NAME"', job)
        self.assertIn('--pattern "$dmg.sha256"', job)
        self.assertIn('shasum -a 256 "$assets/$dmg"', job)
        self.assertNotIn("releases/latest", job)

    def test_cask_job_audits_before_it_pushes(self):
        job = cask_job(WORKFLOW.read_text())

        audit = job.index("brew audit --cask --strict --online")
        push = job.index("git -C \"$TAP_DIR\" push")
        self.assertLess(job.index("brew style"), push)
        self.assertLess(audit, push)
        self.assertIn("StrictHostKeyChecking=yes", job)


if __name__ == "__main__":
    unittest.main()
