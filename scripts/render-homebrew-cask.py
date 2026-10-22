#!/usr/bin/env python3
"""Renders the Filbert Homebrew cask for one stable release.

Prints `update` after writing the cask, or `skip` when the tap already holds
a newer version or the same rendered file.
"""
import argparse
import os
import re
import tempfile
from pathlib import Path

STABLE_VERSION = re.compile(r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
PLACEHOLDER = re.compile(r"@[A-Z0-9_]+@")
CASK_VERSION = re.compile(r'^\s*version "([^"]+)"\s*$', re.MULTILINE)


def fail(message):
    raise SystemExit(message)


def version_key(version):
    match = STABLE_VERSION.fullmatch(version)
    if not match:
        fail(f"Not a plain X.Y.Z version: {version}")
    return tuple(int(part) for part in match.groups())


def render(template, version, sha256):
    version_key(version)
    if not SHA256.fullmatch(sha256):
        fail(f"Not a lowercase SHA-256 hex digest: {sha256}")
    rendered = template.replace("@VERSION@", version).replace("@SHA256@", sha256)
    leftover = PLACEHOLDER.search(rendered)
    if leftover:
        fail(f"Template has an unknown placeholder: {leftover.group()}")
    return rendered


def existing_version(cask):
    versions = CASK_VERSION.findall(cask)
    if len(versions) != 1:
        fail("The existing cask must declare exactly one version")
    return versions[0]


def decide(rendered, version, existing):
    if existing is None:
        return "update"
    if rendered == existing:
        return "skip"
    if version_key(version) < version_key(existing_version(existing)):
        return "skip"
    return "update"


def write_atomically(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
    try:
        with os.fdopen(descriptor, "w") as handle:
            handle.write(content)
        os.chmod(temporary, 0o644)
        os.replace(temporary, path)
    except BaseException:
        os.unlink(temporary)
        raise


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--template", required=True, type=Path)
    parser.add_argument("--version", required=True)
    parser.add_argument("--sha256", required=True)
    parser.add_argument("--existing", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    rendered = render(args.template.read_text(), args.version, args.sha256)
    existing = args.existing.read_text() if args.existing.exists() else None
    decision = decide(rendered, args.version, existing)
    if decision == "update":
        write_atomically(args.output, rendered)
    print(decision)


if __name__ == "__main__":
    main()
