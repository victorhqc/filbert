#!/usr/bin/env python3
"""Validates Sources/App/Resources/ReleaseHighlights.json.

With --require-version, the file must have an entry for that version. With
--appcast-notes, writes that entry as the Markdown notes Sparkle shows before
an update. The notes come only from the checked-in file.
"""
import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_HIGHLIGHTS = ROOT / "Sources/App/Resources/ReleaseHighlights.json"
DEFAULT_LANGUAGES = ROOT / "Sources/App/SupportedLanguage.swift"
RELEASE_URL = "https://github.com/victorhqc/filbert/releases/tag/v{version}"

VERSION_PATTERN = re.compile(r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$")
LANGUAGE_PATTERN = re.compile(r'SupportedLanguage\(code:\s*"([^"]+)"')
MARKUP_PATTERN = re.compile(r"[*_`#<>\[\]|]|https?://")
SENTENCE_BREAK_PATTERN = re.compile(r"[.!?]\s+\S")
MAX_ITEMS = 5
MAX_ENGLISH_LENGTH = 140
KINDS = ("feature", "fix")
SOURCE_LANGUAGE = "en"


def load_languages(path):
    languages = LANGUAGE_PATTERN.findall(Path(path).read_text())
    if SOURCE_LANGUAGE not in languages:
        raise SystemExit(f"{path} lists no {SOURCE_LANGUAGE} language")
    return languages


def parse_version(version):
    match = VERSION_PATTERN.match(version) if isinstance(version, str) else None
    return tuple(int(part) for part in match.groups()) if match else None


def validate_text(location, language, value):
    if not isinstance(value, str) or not value.strip():
        return [f"{location} has no {language} text"]
    errors = []
    if value != value.strip():
        errors.append(f"{location} {language} text has surrounding spaces")
    if "\n" in value or "\r" in value:
        errors.append(f"{location} {language} text has a line break")
    if MARKUP_PATTERN.search(value):
        errors.append(f"{location} {language} text has Markdown, HTML, or a link")
    if language == SOURCE_LANGUAGE:
        if len(value) > MAX_ENGLISH_LENGTH:
            errors.append(
                f"{location} English text is longer than {MAX_ENGLISH_LENGTH} characters"
            )
        if not value.endswith((".", "!", "?")) or SENTENCE_BREAK_PATTERN.search(value):
            errors.append(f"{location} English text is not one sentence")
    return errors


def validate_item(location, item, languages):
    if not isinstance(item, dict) or set(item) != {"kind", "text"}:
        return [f"{location} must have exactly kind and text"]
    errors = []
    if item["kind"] not in KINDS:
        errors.append(f"{location} kind must be one of {', '.join(KINDS)}")
    text = item["text"]
    if not isinstance(text, dict):
        return errors + [f"{location} text must be an object"]
    extra = sorted(set(text) - set(languages))
    if extra:
        errors.append(f"{location} has unsupported languages: {', '.join(extra)}")
    for language in languages:
        errors += validate_text(location, language, text.get(language))
    return errors


def validate(entries, languages):
    if not isinstance(entries, list):
        return ["The highlights file must be a list of versions"]
    errors = []
    previous = None
    for index, entry in enumerate(entries):
        location = f"Entry {index}"
        if not isinstance(entry, dict) or set(entry) != {"version", "items"}:
            errors.append(f"{location} must have exactly version and items")
            continue
        version = parse_version(entry["version"])
        if version is None:
            errors.append(f"{location} version must be a plain X.Y.Z version")
            continue
        location = f"Version {entry['version']}"
        if previous is not None and version >= previous:
            errors.append(f"{location} must come after a newer version, with no duplicates")
        previous = version
        items = entry["items"]
        if not isinstance(items, list) or len(items) > MAX_ITEMS:
            errors.append(f"{location} must have a list of 0 to {MAX_ITEMS} items")
            continue
        for item_index, item in enumerate(items):
            errors += validate_item(f"{location} item {item_index}", item, languages)
    return errors


def find_entry(entries, version):
    return next((entry for entry in entries if entry["version"] == version), None)


def render_appcast_notes(entry):
    version = entry["version"]
    lines = [f"## What's new in Filbert {version}", ""]
    sections = (("feature", "New features"), ("fix", "Bug fixes"))
    for kind, heading in sections:
        texts = [item["text"][SOURCE_LANGUAGE] for item in entry["items"] if item["kind"] == kind]
        if texts:
            lines += [f"### {heading}", ""] + [f"- {text}" for text in texts] + [""]
    if not entry["items"]:
        lines += ["This version has no new features or fixes to highlight.", ""]
    lines.append(f"[Full release notes]({RELEASE_URL.format(version=version)})")
    return "\n".join(lines) + "\n"


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--file", default=str(DEFAULT_HIGHLIGHTS))
    parser.add_argument("--languages-from", default=str(DEFAULT_LANGUAGES))
    parser.add_argument("--require-version", help="fail unless this X.Y.Z version has an entry")
    parser.add_argument("--appcast-notes", help="write the required version's Sparkle notes here")
    args = parser.parse_args(argv)

    if args.appcast_notes and not args.require_version:
        parser.error("--appcast-notes needs --require-version")

    try:
        entries = json.loads(Path(args.file).read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise SystemExit(f"Could not read {args.file}: {error}")

    errors = validate(entries, load_languages(args.languages_from))
    if errors:
        raise SystemExit("Invalid release highlights:\n" + "\n".join(f"- {e}" for e in errors))

    if args.require_version:
        entry = find_entry(entries, args.require_version)
        if entry is None:
            raise SystemExit(
                f"{args.file} has no entry for {args.require_version}. "
                "Run the release-highlights skill and merge its change before publishing."
            )
        if args.appcast_notes:
            Path(args.appcast_notes).write_text(render_appcast_notes(entry))

    print(f"Release highlights are valid ({len(entries)} versions)")


if __name__ == "__main__":
    sys.exit(main())
