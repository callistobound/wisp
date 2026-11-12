"""
Prints the version for a Wisp release tag, or fails if the tag doesn't fit.

Usage: release_version.py TAG build.zig.zon

A tag vX.Y.Z-wisp.N builds as X.Y.Z+wisp.N, and only once build.zig.zon is
at the Ghostty release X.Y.Z (no -dev).
"""

import re
import sys

TAG = re.compile(r"^v(\d+\.\d+\.\d+)-wisp\.(\d+)$")
ZON_VERSION = re.compile(r'^\s*\.version\s*=\s*"([^"]+)"', re.MULTILINE)


def release_version(tag, zon):
    match = TAG.match(tag)
    if not match:
        raise ValueError(f"{tag} isn't a Wisp release tag (vX.Y.Z-wisp.N)")
    base, n = match.groups()

    zon_match = ZON_VERSION.search(zon)
    if not zon_match:
        raise ValueError("no .version in build.zig.zon")
    zon_version = zon_match.group(1)
    if zon_version != base:
        raise ValueError(
            f"{tag} is for {base}, but build.zig.zon is {zon_version}; "
            "merge Ghostty's release before tagging"
        )
    return f"{base}+wisp.{n}"


def main():
    tag, zon_path = sys.argv[1:3]
    with open(zon_path) as f:
        zon = f.read()
    try:
        print(release_version(tag, zon))
    except ValueError as e:
        sys.exit(f"error: {e}")


if __name__ == "__main__":
    main()
