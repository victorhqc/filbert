#!/usr/bin/env python3
"""Validates a generated Sparkle appcast.

With --public-key (and --dmg), also cryptographically verifies Sparkle's
EdDSA signatures: the enclosure signature over the DMG and the feed
signature over the appcast content preceding the signature comment. This
catches a mismatch between the signing key and the key embedded in shipped
apps before the feed is published.
"""
import argparse
import base64
import hashlib
import xml.etree.ElementTree as ElementTree

SPARKLE_NAMESPACE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
FEED_SIGNATURE_PREFIX = b"<!-- sparkle-signatures:\n"
FEED_SIGNATURE_SUFFIX = b"-->"


def fail(message):
    raise SystemExit(message)


# Ed25519 point arithmetic (RFC 8032). Sparkle signs with plain Ed25519 over
# the raw artifact bytes, so verifying needs no external dependencies.
_P = 2**255 - 19
_L = 2**252 + 27742317777372353535851937790883648493
_D = -121665 * pow(121666, _P - 2, _P) % _P
_I = pow(2, (_P - 1) // 4, _P)
_BY = 4 * pow(5, _P - 2, _P) % _P


def _xrecover(y):
    xx = (y * y - 1) * pow(_D * y * y + 1, _P - 2, _P)
    x = pow(xx % _P, (_P + 3) // 8, _P)
    if (x * x - xx) % _P != 0:
        x = x * _I % _P
    if x % 2 != 0:
        x = _P - x
    return x


_BASE = (_xrecover(_BY), _BY, 1, _xrecover(_BY) * _BY % _P)


def _on_curve(point):
    x, y, z, t = point
    return (
        z % _P != 0
        and x * y % _P == z * t % _P
        and (y * y - x * x - z * z - _D * t * t) % _P == 0
    )


def _point_add(p, q):
    x1, y1, z1, t1 = p
    x2, y2, z2, t2 = q
    a = (y1 - x1) * (y2 - x2) % _P
    b = (y1 + x1) * (y2 + x2) % _P
    c = 2 * t1 * _D * t2 % _P
    d = 2 * z1 * z2 % _P
    e, f, g, h = b - a, d - c, d + c, b + a
    return (e * f % _P, g * h % _P, f * g % _P, e * h % _P)


def _scalar_mult(k, point):
    result = (0, 1, 1, 0)
    while k > 0:
        if k & 1:
            result = _point_add(result, point)
        point = _point_add(point, point)
        k >>= 1
    return result


def _point_compress(point):
    x, y, z, _ = point
    zinv = pow(z, _P - 2, _P)
    x = x * zinv % _P
    y = y * zinv % _P
    return int(y | (x & 1) << 255).to_bytes(32, "little")


def _point_decompress(data):
    y = int.from_bytes(data, "little")
    sign = y >> 255
    y &= (1 << 255) - 1
    x = _xrecover(y)
    if x & 1 != sign:
        x = _P - x
    point = (x, y, 1, x * y % _P)
    return point if _on_curve(point) else None


def ed25519_verify(public_key, signature, message):
    """RFC 8032 Ed25519 verification over raw bytes."""
    r_point = _point_decompress(signature[:32])
    a_point = _point_decompress(public_key)
    if r_point is None or a_point is None:
        return False
    s_value = int.from_bytes(signature[32:], "little")
    if s_value >= _L:
        return False
    h_value = int.from_bytes(
        hashlib.sha512(signature[:32] + public_key + message).digest(), "little"
    )
    left = _scalar_mult(s_value, _BASE)
    right = _point_add(r_point, _scalar_mult(h_value, a_point))
    return _point_compress(left) == _point_compress(right)


def decode_public_key(raw):
    try:
        key = base64.b64decode(raw, validate=True)
    except (ValueError, TypeError):
        return None
    return key if len(key) == 32 else None


def _decode_signature(raw, label):
    try:
        signature = base64.b64decode(raw, validate=True)
    except (ValueError, TypeError):
        fail(f"{label} is not valid base64")
    if len(signature) != 64:
        fail(f"{label} is not a 64-byte EdDSA signature")
    return signature


# Mirrors Sparkle's SPUExtractSignedFeed: the LAST signature comment signs
# the appcast bytes preceding it, and the recorded length must match.
def verify_feed_signature(appcast_bytes, public_key):
    prefix_at = appcast_bytes.rfind(FEED_SIGNATURE_PREFIX)
    if prefix_at < 0:
        fail("Appcast has no EdDSA feed signature comment")
    content = appcast_bytes[:prefix_at]
    block_end = appcast_bytes.find(FEED_SIGNATURE_SUFFIX, prefix_at)
    if block_end < 0:
        fail("Appcast feed signature comment is not terminated")
    block = appcast_bytes[
        prefix_at + len(FEED_SIGNATURE_PREFIX):block_end
    ].decode("utf-8", errors="replace")

    ed_signature = None
    content_length = None
    for line in block.splitlines():
        if line.startswith("edSignature:"):
            ed_signature = line[len("edSignature:"):].strip()
        elif line.startswith("length:"):
            length_text = line[len("length:"):].strip()
            if length_text.isdigit():
                content_length = int(length_text)
    if ed_signature is None or content_length is None:
        fail("Appcast feed signature comment lacks edSignature or length")

    if content_length != len(content):
        fail(
            f"Feed signature length {content_length} does not match the "
            f"signed content length {len(content)}"
        )
    signature = _decode_signature(ed_signature, "Feed edSignature")
    if not ed25519_verify(public_key, signature, content):
        fail("Feed EdDSA signature does not verify against the public key")


def verify_enclosure_signature(dmg_bytes, ed_signature, public_key, dmg_length):
    signature = _decode_signature(ed_signature, "Enclosure edSignature")
    if dmg_length != len(dmg_bytes):
        fail(
            f"Enclosure length {dmg_length} does not match the DMG size "
            f"{len(dmg_bytes)}"
        )
    if not ed25519_verify(public_key, signature, dmg_bytes):
        fail("Enclosure EdDSA signature does not verify against the public key")


def sparkle_version_value(item, enclosure, sparkle, name):
    qualified_name = f"{sparkle}{name}"
    item_value = item.findtext(qualified_name)
    item_value = item_value.strip() if item_value else None
    enclosure_value = enclosure.get(qualified_name)
    if item_value and enclosure_value and item_value != enclosure_value:
        fail(f"Appcast has conflicting sparkle:{name} values")
    return item_value or enclosure_value


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--appcast", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--download-url", required=True)
    parser.add_argument(
        "--public-key",
        help="base64 EdDSA public key; enables signature verification",
    )
    parser.add_argument(
        "--dmg",
        help="path to the release DMG; enables enclosure verification",
    )
    args = parser.parse_args()

    try:
        appcast_data = open(args.appcast, "rb").read()
        root = ElementTree.fromstring(appcast_data)
    except (ElementTree.ParseError, OSError) as error:
        fail(f"Could not parse appcast: {error}")

    sparkle = f"{{{SPARKLE_NAMESPACE}}}"
    items = root.findall("./channel/item")
    if len(items) != 1:
        fail(f"Expected one generated appcast item, found {len(items)}")

    item = items[0]
    enclosure = item.find("enclosure")
    if enclosure is None:
        fail("Appcast item is missing its enclosure")
    release_notes = item.findtext(f"{sparkle}releaseNotesLink")
    version = sparkle_version_value(item, enclosure, sparkle, "version")
    short_version = sparkle_version_value(
        item,
        enclosure,
        sparkle,
        "shortVersionString",
    )
    required = {
        "sparkle:version": version,
        "sparkle:shortVersionString": short_version,
        "sparkle:edSignature": enclosure.get(f"{sparkle}edSignature"),
        "pubDate": item.findtext("pubDate"),
        "release notes": item.findtext("description") or release_notes,
    }
    missing = [name for name, value in required.items() if not value]
    if missing:
        fail(f"Appcast is missing required fields: {', '.join(missing)}")

    if version != args.version:
        fail("Appcast sparkle:version does not match the release version")
    if short_version != args.version:
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

    if args.public_key:
        public_key = decode_public_key(args.public_key)
        if public_key is None:
            fail("--public-key must be a base64-encoded 32-byte EdDSA key")
        if args.dmg:
            try:
                dmg_bytes = open(args.dmg, "rb").read()
            except OSError as error:
                fail(f"Could not read DMG: {error}")
            verify_enclosure_signature(
                dmg_bytes,
                enclosure.get(f"{sparkle}edSignature"),
                public_key,
                length,
            )
        verify_feed_signature(appcast_data, public_key)


if __name__ == "__main__":
    main()
