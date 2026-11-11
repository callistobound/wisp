import os
import sys
import unittest
from datetime import datetime, timedelta, timezone

sys.path.insert(0, os.path.dirname(__file__))
from update_appcast import NS, update  # noqa: E402

ATTRS = {"sparkle:edSignature": "c2lnbmF0dXJl", "length": "1234"}
START = datetime(2026, 11, 11, tzinfo=timezone.utc)


def publish(appcast, channel, build, hours=0):
    return update(
        appcast,
        channel=channel,
        version=f"1.4.1+wisp.{build}",
        build=str(build),
        commit="fd6bc12",
        url=f"https://example.com/{build}/Wisp.dmg",
        enclosure_attrs=ATTRS,
        now=START + timedelta(hours=hours),
    )


def items(tree):
    return tree.getroot().find("channel").findall("item")


def builds(tree):
    return [i.find("sparkle:version", NS).text for i in items(tree)]


class UpdateAppcastTest(unittest.TestCase):
    def test_first_publish_creates_feed(self):
        tree = publish(None, "stable", 18871)
        self.assertEqual(tree.getroot().find("channel").find("title").text, "Wisp")
        (item,) = items(tree)
        self.assertEqual(item.find("sparkle:version", NS).text, "18871")
        self.assertEqual(item.find("sparkle:shortVersionString", NS).text, "1.4.1+wisp.18871")
        enclosure = item.find("enclosure")
        self.assertEqual(enclosure.get("url"), "https://example.com/18871/Wisp.dmg")
        self.assertEqual(enclosure.get(f"{{{NS['sparkle']}}}edSignature"), "c2lnbmF0dXJl")
        self.assertEqual(enclosure.get("length"), "1234")

    def test_same_build_replaced(self):
        tree = publish(publish(None, "stable", 18871), "stable", 18871, hours=1)
        self.assertEqual(builds(tree), ["18871"])

    def test_stable_keeps_15(self):
        tree = None
        for build in range(1, 21):
            tree = publish(tree, "stable", build, hours=build)
        self.assertEqual(len(items(tree)), 15)
        self.assertEqual(min(int(b) for b in builds(tree)), 6)

    def test_tip_keeps_1(self):
        tree = None
        for build in range(1, 4):
            tree = publish(tree, "tip", build, hours=build)
        self.assertEqual(builds(tree), ["3"])

    def test_description_names_commit(self):
        (item,) = items(publish(None, "tip", 1))
        description = item.find("description").text
        self.assertIn("fd6bc12", description)
        self.assertIn("https://github.com/callistobound/wisp/commit/fd6bc12", description)


if __name__ == "__main__":
    unittest.main()
