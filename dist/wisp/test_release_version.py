import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(__file__))
from release_version import release_version  # noqa: E402

ZON = '.{\n    .name = .ghostty,\n    .version = "1.4.1",\n}\n'


class ReleaseVersionTest(unittest.TestCase):
    def test_matching_tag(self):
        self.assertEqual(release_version("v1.4.1-wisp.3", ZON), "1.4.1+wisp.3")

    def test_tag_must_match_zon(self):
        with self.assertRaisesRegex(ValueError, "1.5.0.*1.4.1"):
            release_version("v1.5.0-wisp.1", ZON)

    def test_cant_claim_an_unreleased_version(self):
        with self.assertRaisesRegex(ValueError, "1.4.1-dev"):
            release_version("v1.4.1-wisp.1", ZON.replace('"1.4.1"', '"1.4.1-dev"'))

    def test_earlier_ghostty_release(self):
        dev = ZON.replace('"1.4.1"', '"1.4.1-dev"')
        self.assertEqual(release_version("v1.4.0-wisp.1", dev), "1.4.0+wisp.1")

    def test_malformed_tags(self):
        for tag in ("v1.4.1-wisp.1x", "v1.4.1-wisp.", "v1.4.1", "1.4.1-wisp.1", "v1.4-wisp.1"):
            with self.assertRaises(ValueError, msg=tag):
                release_version(tag, ZON)


if __name__ == "__main__":
    unittest.main()
