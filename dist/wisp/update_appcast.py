"""
Adds a build to a Wisp appcast (Sparkle update feed).

Usage:
    update_appcast.py --channel {tip,stable} --version V --build N --commit C
        --url DMG_URL --signature sign_update.txt --appcast IN.xml --out OUT.xml

IN.xml may be missing, which starts a new feed. sign_update.txt holds the
output of Sparkle's sign_update for the DMG.
"""

import argparse
import os
import xml.etree.ElementTree as ET
from datetime import datetime, timezone

NS = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
for _prefix, _uri in NS.items():
    ET.register_namespace(_prefix, _uri)

REPO = "https://github.com/jamesboehmer/wisp"
KEEP = {"stable": 15, "tip": 1}
PUBDATE_FORMAT = "%a, %d %b %Y %H:%M:%S %z"


def _sparkle(name):
    return f"{{{NS['sparkle']}}}{name}"


def _qualified(key):
    """'sparkle:edSignature' -> Clark notation; other keys unchanged."""
    prefix, _, local = key.partition(":")
    return f"{{{NS[prefix]}}}{local}" if local and prefix in NS else key


def parse_signature(text):
    """Parses sign_update output: key="value" pairs separated by spaces."""
    attrs = {}
    for pair in text.split():
        key, value = pair.split("=", 1)
        attrs[key] = value.strip('"')
    return attrs


def new_feed():
    rss = ET.Element("rss", {"version": "2.0"})
    channel = ET.SubElement(rss, "channel")
    ET.SubElement(channel, "title").text = "Wisp"
    return ET.ElementTree(rss)


def update(appcast, channel, version, build, commit, url, enclosure_attrs, now):
    tree = appcast if appcast is not None else new_feed()
    feed = tree.getroot().find("channel")

    # Sparkle reports bad signatures if it picks a stale duplicate.
    for item in feed.findall("item"):
        existing = item.find("sparkle:version", NS)
        if item.find("pubDate") is None or (existing is not None and existing.text == build):
            feed.remove(item)

    item = ET.SubElement(feed, "item")
    ET.SubElement(item, "title").text = f"Build {build}"
    ET.SubElement(item, "pubDate").text = now.strftime(PUBDATE_FORMAT)
    ET.SubElement(item, _sparkle("version")).text = build
    ET.SubElement(item, _sparkle("shortVersionString")).text = version
    ET.SubElement(item, _sparkle("minimumSystemVersion")).text = "13.0.0"
    ET.SubElement(item, "description").text = (
        f"<h1>Wisp {version}</h1>"
        f'<p>Built from commit <a href="{REPO}/commit/{commit}"><code>{commit}</code></a>.</p>'
    )
    enclosure = ET.SubElement(item, "enclosure", {"url": url, "type": "application/octet-stream"})
    for key, value in enclosure_attrs.items():
        enclosure.set(_qualified(key), value)

    items = sorted(
        feed.findall("item"),
        key=lambda i: datetime.strptime(i.find("pubDate").text, PUBDATE_FORMAT),
    )
    for old in items[: -KEEP[channel]]:
        feed.remove(old)
    return tree


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--channel", choices=KEEP, required=True)
    for name in ("version", "build", "commit", "url", "signature", "appcast", "out"):
        parser.add_argument(f"--{name}", required=True)
    args = parser.parse_args()

    with open(args.signature) as f:
        attrs = parse_signature(f.read())
    appcast = ET.parse(args.appcast) if os.path.exists(args.appcast) else None
    tree = update(
        appcast,
        channel=args.channel,
        version=args.version,
        build=args.build,
        commit=args.commit,
        url=args.url,
        enclosure_attrs=attrs,
        now=datetime.now(timezone.utc),
    )
    tree.write(args.out, xml_declaration=True, encoding="utf-8")


if __name__ == "__main__":
    main()
