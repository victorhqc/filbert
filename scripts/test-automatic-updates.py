#!/usr/bin/env python3
import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
VALIDATOR = ROOT / "scripts/validate-appcast.py"
WORKFLOW = ROOT / ".github/workflows/release.yml"
SPARKLE_NAMESPACE = "http://www.andymatuschak.org/xml-namespaces/sparkle"

_spec = importlib.util.spec_from_file_location("validate_appcast", VALIDATOR)
validate_appcast = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(validate_appcast)

# RFC 8032 section 7.1 test vectors, checked against the validator's own
# Ed25519 implementation before any generated fixtures are trusted.
RFC_VECTORS = [
    (
        "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a",
        "",
        "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155"
        "5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b",
    ),
    (
        "fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025",
        "af82",
        "6291d657deec24024827e69c3abe01a30ce548a284743a445e3680d7db5ac3ac1"
        "8ff9b538d16f290ae67f760984dc6594a7c15e9716ed28dc027beceea1ec40a",
    ),
]

# Fixtures signed with the RFC 8032 vector 1 seed by a scratch signer; the
# validator must verify them through its own Ed25519 implementation.
PUBLIC_KEY = "11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo="
WRONG_PUBLIC_KEY = "xFCY2OIYgaGojaR+QuLgAjAPBWCCFlo9NsFOlO+5EVgkA=="
DMG_BYTES = b"Filbert fake DMG payload for appcast validation\n"
ENCLOSURE_SIG = "zHOTioY9R4ATP6AOAMrOozcFMAAtXRNl0srKRwDJ2uBCCXPQnoPn5UgjL+6xSICHjNfi3MHJjr/nGqysMGWrAg=="
FEED_SIG = "5FYvxgIwX2OlQScvO2PcPkgOgId6lDf6a8hKzZckX3EV/P3rv33yW/EHokSThY8R2weC1C1Xw3FfL1L7n9XbBQ=="


def signed_appcast_bytes(description="Release notes"):
    content = (
        f'<?xml version="1.0"?>\n'
        f'<rss xmlns:sparkle="{SPARKLE_NAMESPACE}">\n'
        f'  <channel>\n'
        f'    <item>\n'
        f'      <description><![CDATA[{description}]]></description>\n'
        f'      <pubDate>Tue, 01 Jan 2030 00:00:00 GMT</pubDate>\n'
        f'      <enclosure\n'
        f'        url="https://github.com/victorhqc/filbert/releases/download/'
        f'v1.2.3/Filbert-1.2.3-arm64.dmg"\n'
        f'        length="{len(DMG_BYTES)}"\n'
        f'        type="application/octet-stream"\n'
        f'        sparkle:edSignature="{ENCLOSURE_SIG}"\n'
        f'        sparkle:version="1.2.3"\n'
        f'        sparkle:shortVersionString="1.2.3"\n'
        f'      />\n'
        f'    </item>\n'
        f'  </channel>\n'
        f'</rss>\n'
    ).encode()
    signing_comment = (
        f"<!-- sparkle-signatures:\n"
        f"edSignature: {FEED_SIG}\n"
        f"length: {len(content)}\n"
        f"-->"
    ).encode()
    return content + signing_comment


class AutomaticUpdatesTests(unittest.TestCase):
    def test_stable_release_workflow_gates_prereleases_and_drafts(self):
        workflow = WORKFLOW.read_text()

        self.assertIn("github.event.release.prerelease", workflow)
        self.assertIn("github.event.release.draft", workflow)
        self.assertIn("needs: release", workflow)
        self.assertIn("actions/deploy-pages@v4", workflow)

    def test_workflow_rejects_prerelease_suffixed_stable_tags(self):
        workflow = WORKFLOW.read_text()

        self.assertIn("no prerelease or build suffix", workflow)

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

    def test_workflow_verifies_signatures_against_the_public_key(self):
        workflow = WORKFLOW.read_text()

        self.assertIn('--public-key "$SPARKLE_PUBLIC_ED_KEY"', workflow)
        self.assertIn('--dmg "$dmg"', workflow)

    def test_ed25519_implementation_matches_rfc8032_vectors(self):
        for public_key_hex, message_hex, signature_hex in RFC_VECTORS:
            public_key = bytes.fromhex(public_key_hex)
            message = bytes.fromhex(message_hex)
            signature = bytes.fromhex(signature_hex)

            self.assertTrue(
                validate_appcast.ed25519_verify(public_key, signature, message),
                f"RFC 8032 vector failed for key {public_key_hex[:16]}…",
            )
            tampered = bytes([message[0] + 1]) + message[1:] if message else b"x"
            self.assertFalse(
                validate_appcast.ed25519_verify(public_key, signature, tampered)
            )

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
                  <sparkle:version>1.2.3</sparkle:version>
                  <sparkle:shortVersionString>1.2.3</sparkle:shortVersionString>
                  <enclosure
                    url="https://github.com/victorhqc/filbert/releases/download/v1.2.3/Filbert-1.2.3-arm64.dmg"
                    length="12"
                    type="application/octet-stream"
                    sparkle:edSignature="signature"
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

    def test_validator_accepts_signed_appcast_and_dmg(self):
        appcast = self._write_bytes(signed_appcast_bytes())
        dmg = self._write_dmg(DMG_BYTES)

        result = self._run_validator(appcast, public_key=PUBLIC_KEY, dmg=dmg)

        self.assertEqual(result.returncode, 0, result.stderr)

    def test_validator_rejects_tampered_dmg(self):
        appcast = self._write_bytes(signed_appcast_bytes())
        dmg = self._write_dmg(DMG_BYTES + b"extra bytes")

        result = self._run_validator(appcast, public_key=PUBLIC_KEY, dmg=dmg)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Enclosure", result.stderr)

    def test_validator_rejects_tampered_feed(self):
        tampered = signed_appcast_bytes().replace(
            b"Release notes", b"Release notex"
        )
        appcast = self._write_bytes(tampered)
        dmg = self._write_dmg(DMG_BYTES)

        result = self._run_validator(appcast, public_key=PUBLIC_KEY, dmg=dmg)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Feed EdDSA signature", result.stderr)

    def test_validator_rejects_signature_made_with_another_key(self):
        appcast = self._write_bytes(signed_appcast_bytes())
        dmg = self._write_dmg(DMG_BYTES)

        result = self._run_validator(
            appcast, public_key=WRONG_PUBLIC_KEY, dmg=dmg
        )

        self.assertNotEqual(result.returncode, 0)

    def _write_appcast(self, content):
        return self._write_bytes(content.encode())

    def _write_bytes(self, content):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        path = Path(directory.name) / "appcast.xml"
        path.write_bytes(content)
        return path

    def _write_dmg(self, content):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        path = Path(directory.name) / "Filbert-1.2.3-arm64.dmg"
        path.write_bytes(content)
        return path

    def _run_validator(self, appcast, public_key=None, dmg=None):
        expected_url = (
            "https://github.com/victorhqc/filbert/releases/download/"
            "v1.2.3/Filbert-1.2.3-arm64.dmg"
        )
        command = [
            sys.executable,
            str(VALIDATOR),
            "--appcast",
            str(appcast),
            "--version",
            "1.2.3",
            "--download-url",
            expected_url,
        ]
        if public_key:
            command += ["--public-key", public_key]
        if dmg:
            command += ["--dmg", str(dmg)]
        return subprocess.run(
            command,
            capture_output=True,
            text=True,
            check=False,
        )


if __name__ == "__main__":
    unittest.main()
