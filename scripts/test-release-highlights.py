#!/usr/bin/env python3
import copy
import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
VALIDATOR = ROOT / "scripts/validate-release-highlights.py"
APPCAST_VALIDATOR = ROOT / "scripts/validate-appcast.py"
RELEASE_WORKFLOW = ROOT / ".github/workflows/release.yml"
CI_WORKFLOW = ROOT / ".github/workflows/ci.yml"
BUILD_SCRIPT = ROOT / "scripts/build-dmg.sh"
HIGHLIGHTS = ROOT / "Sources/App/Resources/ReleaseHighlights.json"
SPARKLE_NAMESPACE = "http://www.andymatuschak.org/xml-namespaces/sparkle"

_spec = importlib.util.spec_from_file_location("validate_release_highlights", VALIDATOR)
highlights = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(highlights)

LANGUAGES = highlights.load_languages(highlights.DEFAULT_LANGUAGES)


def item(kind="feature", english="Filbert shows a new thing."):
    return {"kind": kind, "text": {language: english for language in LANGUAGES}}


def entry(version="1.2.3", items=None):
    return {"version": version, "items": [item()] if items is None else items}


class ReleaseHighlightsTests(unittest.TestCase):
    def test_languages_come_from_the_app(self):
        self.assertEqual(LANGUAGES[0], "en")
        self.assertIn("zh-Hant", LANGUAGES)
        self.assertEqual(len(LANGUAGES), len(set(LANGUAGES)))

    def test_checked_in_file_is_valid(self):
        entries = json.loads(HIGHLIGHTS.read_text())

        self.assertEqual(highlights.validate(entries, LANGUAGES), [])

    def test_valid_entries_pass(self):
        entries = [entry("1.2.4", [item(), item("fix", "A crash is gone.")]), entry("1.2.3", [])]

        self.assertEqual(highlights.validate(entries, LANGUAGES), [])

    def test_versions_must_be_plain_unique_and_newest_first(self):
        cases = {
            "v1.2.3": "plain X.Y.Z",
            "1.2": "plain X.Y.Z",
            "1.2.3-beta": "plain X.Y.Z",
        }
        for version, message in cases.items():
            with self.subTest(version=version):
                self.assertIn(message, " ".join(highlights.validate([entry(version)], LANGUAGES)))

        for versions in (["1.2.3", "1.2.4"], ["1.2.3", "1.2.3"]):
            with self.subTest(versions=versions):
                errors = highlights.validate([entry(v) for v in versions], LANGUAGES)
                self.assertIn("newer version", " ".join(errors))

    def test_an_entry_has_at_most_five_items(self):
        errors = highlights.validate([entry(items=[item()] * 6)], LANGUAGES)

        self.assertIn("0 to 5 items", " ".join(errors))

    def test_items_need_a_known_kind_and_every_language(self):
        unknown = item()
        unknown["kind"] = "chore"
        missing = item()
        del missing["text"]["ja"]
        extra = item()
        extra["text"]["fr"] = "Bonjour."
        empty = item()
        empty["text"]["ru"] = " "

        cases = {
            "kind must be one of": unknown,
            "no ja text": missing,
            "unsupported languages: fr": extra,
            "no ru text": empty,
        }
        for message, bad in cases.items():
            with self.subTest(message=message):
                errors = highlights.validate([entry(items=[bad])], LANGUAGES)
                self.assertIn(message, " ".join(errors))

    def test_english_is_one_short_plain_sentence(self):
        cases = {
            "not one sentence": "Filbert is faster. It is also nicer.",
            "not one sentence ": "Filbert is faster",
            "longer than 140": "Filbert " + "really " * 30 + "works.",
            "Markdown, HTML, or a link": "See **bold** text.",
            "Markdown, HTML, or a link ": "See https://example.com now.",
            "line break": "Filbert is\nfaster.",
        }
        for message, english in cases.items():
            with self.subTest(english=english):
                errors = highlights.validate([entry(items=[item(english=english)])], LANGUAGES)
                self.assertIn(message.strip(), " ".join(errors))

    def test_appcast_notes_list_features_then_fixes_with_the_release_link(self):
        notes = highlights.render_appcast_notes(
            entry("1.2.3", [item("fix", "A crash is gone."), item(english="A new row.")])
        )

        self.assertLess(notes.index("### New features"), notes.index("### Bug fixes"))
        self.assertIn("- A new row.", notes)
        self.assertIn("- A crash is gone.", notes)
        self.assertIn("https://github.com/victorhqc/filbert/releases/tag/v1.2.3", notes)
        self.assertNotIn("SHA-256", notes)

    def test_an_empty_entry_still_has_notes(self):
        notes = highlights.render_appcast_notes(entry("1.2.3", []))

        self.assertIn("no new features or fixes", notes)

    def test_cli_requires_an_entry_for_the_release_version(self):
        path = self._write_json([entry("1.2.3")])

        missing = self._run(["--file", str(path), "--require-version", "1.2.4"])
        present = self._run(["--file", str(path), "--require-version", "1.2.3"])

        self.assertNotEqual(missing.returncode, 0)
        self.assertIn("no entry for 1.2.4", missing.stderr)
        self.assertEqual(present.returncode, 0, present.stderr)

    def test_cli_writes_appcast_notes(self):
        path = self._write_json([entry("1.2.3")])
        notes = path.parent / "notes.md"

        result = self._run([
            "--file", str(path), "--require-version", "1.2.3", "--appcast-notes", str(notes),
        ])

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("- Filbert shows a new thing.", notes.read_text())

    def test_cli_rejects_an_invalid_file(self):
        bad = copy.deepcopy(entry())
        bad["items"][0]["kind"] = "chore"
        result = self._run(["--file", str(self._write_json([bad]))])

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Invalid release highlights", result.stderr)

    def test_appcast_validator_requires_every_highlight(self):
        notes = self._write_text("## What's new\n\n- A new row.\n- Filbert's crash is gone.\n")
        embedded = self._appcast(
            "<h2>What&#39;s new</h2><ul><li>A new row.</li><li>Filbert&#39;s crash is gone.</li></ul>"
        )
        partial = self._appcast("<ul><li>A new row.</li></ul>")

        accepted = self._run_appcast_validator(embedded, notes)
        rejected = self._run_appcast_validator(partial, notes)

        self.assertEqual(accepted.returncode, 0, accepted.stderr)
        self.assertNotEqual(rejected.returncode, 0)
        self.assertIn("missing highlights", rejected.stderr)

    def test_release_workflow_checks_highlights_before_the_build(self):
        workflow = RELEASE_WORKFLOW.read_text()

        check = workflow.index('validate-release-highlights.py --require-version "$VERSION"')
        build = workflow.index("scripts/build-dmg.sh --version")
        self.assertLess(check, build)

    def test_release_workflow_embeds_and_verifies_the_appcast_notes(self):
        workflow = RELEASE_WORKFLOW.read_text()
        appcast_step = workflow[workflow.index("Generate and validate stable appcast"):]

        self.assertIn('notes="dist/Filbert-${VERSION}-arm64.appcast-notes.md"', appcast_step)
        self.assertIn('--release-notes "$notes"', appcast_step)

    def test_signed_build_writes_appcast_notes_from_the_checked_in_file(self):
        script = BUILD_SCRIPT.read_text()

        self.assertIn('--appcast-notes "$appcast_notes_path"', script)
        self.assertIn('appcast_notes_path="${dmg_path%.dmg}.appcast-notes.md"', script)

    def test_ci_runs_these_tests(self):
        self.assertIn("python3 scripts/test-release-highlights.py", CI_WORKFLOW.read_text())

    def _appcast(self, description):
        return self._write_text(
            f"""<?xml version="1.0"?>
            <rss xmlns:sparkle="{SPARKLE_NAMESPACE}">
              <channel>
                <item>
                  <description><![CDATA[{description}]]></description>
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
            """,
            name="appcast.xml",
        )

    def _run_appcast_validator(self, appcast, notes):
        return subprocess.run(
            [
                sys.executable,
                str(APPCAST_VALIDATOR),
                "--appcast", str(appcast),
                "--version", "1.2.3",
                "--download-url",
                "https://github.com/victorhqc/filbert/releases/download/v1.2.3/Filbert-1.2.3-arm64.dmg",
                "--release-notes", str(notes),
            ],
            capture_output=True,
            text=True,
            check=False,
        )

    def _run(self, arguments):
        return subprocess.run(
            [sys.executable, str(VALIDATOR)] + arguments,
            capture_output=True,
            text=True,
            check=False,
        )

    def _write_json(self, value):
        return self._write_text(json.dumps(value), name="ReleaseHighlights.json")

    def _write_text(self, content, name="notes.md"):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        path = Path(directory.name) / name
        path.write_text(content)
        return path


if __name__ == "__main__":
    unittest.main()
