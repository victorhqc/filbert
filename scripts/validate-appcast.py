#!/usr/bin/env python3
import argparse
import xml.etree.ElementTree as ElementTree

SPARKLE_NAMESPACE = "http://www.andymatuschak.org/xml-namespaces/sparkle"


def fail(message):
    raise SystemExit(message)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--appcast", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--download-url", required=True)
    args = parser.parse_args()

    try:
        appcast_data = open(args.appcast, encoding="utf-8").read()
        root = ElementTree.fromstring(appcast_data)
    except (ElementTree.ParseError, OSError) as error:
        fail(f"Could not parse appcast: {error}")

    if "<!-- sparkle-signatures:" not in appcast_data or "edSignature:" not in appcast_data:
        fail("Appcast is not signed with an EdDSA feed signature")

    sparkle = f"{{{SPARKLE_NAMESPACE}}}"
    items = root.findall("./channel/item")
    if len(items) != 1:
        fail(f"Expected one generated appcast item, found {len(items)}")

    item = items[0]
    enclosure = item.find("enclosure")
    if enclosure is None:
        fail("Appcast item is missing its enclosure")
    release_notes = item.findtext(f"{sparkle}releaseNotesLink")
    required = {
        "sparkle:version": enclosure.get(f"{sparkle}version"),
        "sparkle:shortVersionString": enclosure.get(f"{sparkle}shortVersionString"),
        "sparkle:edSignature": enclosure.get(f"{sparkle}edSignature"),
        "pubDate": item.findtext("pubDate"),
        "release notes": item.findtext("description") or release_notes,
    }
    missing = [name for name, value in required.items() if not value]
    if missing:
        fail(f"Appcast is missing required fields: {', '.join(missing)}")

    if enclosure.get(f"{sparkle}version") != args.version:
        fail("Appcast sparkle:version does not match the release version")
    if enclosure.get(f"{sparkle}shortVersionString") != args.version:
        fail("Appcast sparkle:shortVersionString does not match the release version")
    if enclosure.get("url") != args.download_url:
        fail("Appcast enclosure URL is not the exact release asset URL")

    try:
        length = int(enclosure.get("length", ""))
    except ValueError:
        fail("Appcast enclosure length is not an integer")
    if length <= 0:
        fail("Appcast enclosure length must be positive")

    if not enclosure.get("type"):
        fail("Appcast enclosure is missing its MIME type")


if __name__ == "__main__":
    main()
