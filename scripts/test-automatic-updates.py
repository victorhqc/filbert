#!/usr/bin/env python3
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
VALIDATOR = ROOT / "scripts/validate-appcast.py"
WORKFLOW = ROOT / ".github/workflows/release.yml"
SPARKLE_NAMESPACE = "http://www.andymatuschak.org/xml-namespaces/sparkle"


class AutomaticUpdatesTests(unittest.TestCase):
    def test_stable_release_workflow_gates_prereleases_and_drafts(self):
        workflow = WORKFLOW.read_text()

        self.assertIn("github.event.release.prerelease", workflow)
        self.assertIn("github.event.release.draft", workflow)
        self.assertIn("needs: release", workflow)
        self.assertIn("actions/deploy-pages@v4", workflow)

    def test_workflow_uses_exact_tag_asset_url_and_private_key_stdin(self):
        workflow = WORKFLOW.read_text()

        self.assertIn("--download-url-prefix", workflow)
        self.assertIn("releases/download/${TAG_NAME}/", workflow)
        self.assertIn("SPARKLE_PRIVATE_KEY", workflow)
        self.assertIn("--ed-key-file -", workflow)
        self.assertIn('[[ -n "$SPARKLE_PRIVATE_KEY" ]]', workflow)
        self.assertIn("SURequireSignedFeed", (ROOT / "packaging/Info.plist").read_text())
        self.assertNotIn("echo \"$SPARKLE_PRIVATE_KEY\"", workflow)
        self.assertNotIn("releases/latest", workflow)

    def test_validator_accepts_required_appcast_fields(self):
        appcast = self._write_appcast(
            f"""<?xml version="1.0"?>
            <!-- sparkle-signatures:
            edSignature: feed-signature
            length: 1
            -->
            <rss xmlns:sparkle="{SPARKLE_NAMESPACE}">
              <channel>
                <item>
                  <description><![CDATA[Release notes]]></description>
                  <pubDate>Tue, 01 Jan 2030 00:00:00 GMT</pubDate>
                  <enclosure
                    url="https://github.com/victorhqc/filbert/releases/download/v1.2.3/Filbert-1.2.3-arm64.dmg"
                    length="12"
                    type="application/octet-stream"
                    sparkle:edSignature="signature"
                    sparkle:version="1.2.3"
                    sparkle:shortVersionString="1.2.3"
                  />
                </item>
              </channel>
            </rss>
            """
        )
        result = self._run_validator(appcast)

        self.assertEqual(result.returncode, 0, result.stderr)

    def test_validator_rejects_wrong_tag_asset_url(self):
        appcast = self._write_appcast(
            f"""<?xml version="1.0"?>
            <!-- sparkle-signatures:
            edSignature: feed-signature
            length: 1
            -->
            <rss xmlns:sparkle="{SPARKLE_NAMESPACE}">
              <channel>
                <item>
                  <description>Release notes</description>
                  <pubDate>Tue, 01 Jan 2030 00:00:00 GMT</pubDate>
                  <enclosure
                    url="https://github.com/victorhqc/filbert/releases/download/latest/Filbert-1.2.3-arm64.dmg"
                    length="12"
                    type="application/octet-stream"
                    sparkle:edSignature="signature"
                    sparkle:version="1.2.3"
                    sparkle:shortVersionString="1.2.3"
                  />
                </item>
              </channel>
            </rss>
            """
        )
        result = self._run_validator(appcast)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("exact release asset URL", result.stderr)

    def _write_appcast(self, content):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        path = Path(directory.name) / "appcast.xml"
        path.write_text(content)
        return path

    def _run_validator(self, appcast):
        expected_url = (
            "https://github.com/victorhqc/filbert/releases/download/"
            "v1.2.3/Filbert-1.2.3-arm64.dmg"
        )
        return subprocess.run(
            [
                sys.executable,
                str(VALIDATOR),
                "--appcast",
                str(appcast),
                "--version",
                "1.2.3",
                "--download-url",
                expected_url,
            ],
            capture_output=True,
            text=True,
            check=False,
        )


if __name__ == "__main__":
    unittest.main()
