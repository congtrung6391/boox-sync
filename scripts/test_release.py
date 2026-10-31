#!/usr/bin/env python3
"""Unit tests for release.py:  python3 scripts/test_release.py"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import release  # noqa: E402
from release import Commit  # noqa: E402


def commit(subject, body=""):
    return Commit("a" * 40, "aaaaaaa", subject, body)


class ParsingTests(unittest.TestCase):
    def test_conventional(self):
        c = commit("feat(dashboard): add weather")
        self.assertTrue(c.conventional)
        self.assertEqual((c.type, c.scope, c.message, c.breaking), ("feat", "dashboard", "add weather", False))

    def test_breaking_marker_and_body(self):
        self.assertTrue(commit("feat!: drop adb").breaking)
        self.assertTrue(commit("fix(core)!: rename").breaking)
        self.assertTrue(commit("fix: x", "details\n\nBREAKING CHANGE: removed the flag").breaking)
        self.assertFalse(commit("fix: x", "mentions BREAKING CHANGE in prose").breaking)

    def test_not_conventional(self):
        c = commit("Add app icon and logo")
        self.assertFalse(c.conventional)
        self.assertEqual(c.heading, "Other changes")
        self.assertIsNone(c.level)

    def test_release_commit_detected(self):
        self.assertTrue(commit("chore(release): v1.2.3").is_release_commit)
        self.assertFalse(commit("chore: tidy").is_release_commit)


class BumpTests(unittest.TestCase):
    def test_levels(self):
        v = (1, 4, 2)
        self.assertEqual(release.decide_bump([commit("fix: a")], v), "patch")
        self.assertEqual(release.decide_bump([commit("fix: a"), commit("feat: b")], v), "minor")
        self.assertEqual(release.decide_bump([commit("feat: a"), commit("fix!: b")], v), "major")
        self.assertEqual(release.decide_bump([commit("perf: a")], v), "patch")

    def test_nothing_releasable(self):
        v = (1, 0, 0)
        for subject in ["docs: x", "chore: x", "ci: x", "refactor: x", "test: x", "Update things"]:
            self.assertIsNone(release.decide_bump([commit(subject)], v), subject)

    def test_pre_one_point_zero_breaking_is_minor(self):
        self.assertEqual(release.decide_bump([commit("feat!: a")], (0, 3, 1)), "minor")
        self.assertEqual(release.decide_bump([commit("feat!: a")], (1, 0, 0)), "major")

    def test_bump_version(self):
        self.assertEqual(release.bump_version((1, 2, 3), "patch"), (1, 2, 4))
        self.assertEqual(release.bump_version((1, 2, 3), "minor"), (1, 3, 0))
        self.assertEqual(release.bump_version((1, 2, 3), "major"), (2, 0, 0))

    def test_parse_version(self):
        self.assertEqual(release.parse_version("1.20.3\n"), (1, 20, 3))
        with self.assertRaises(ValueError):
            release.parse_version("1.2")
        self.assertEqual(release.format_version((0, 1, 0)), "0.1.0")


class ChangelogTests(unittest.TestCase):
    def test_section_groups_and_links(self):
        commits = [
            commit("feat(display): second display"), commit("fix: crash on start"),
            commit("docs: update readme"), commit("chore: tidy"), commit("chore(release): v0.1.0"),
            commit("Some old commit"), commit("feat!: new layout format"),
        ]
        text = release.render_section((0, 2, 0), "2026-11-01", commits, "https://github.com/o/r")
        self.assertIn("## [0.2.0] - 2026-11-01", text)
        self.assertLess(text.index("### Breaking changes"), text.index("### Features"))
        self.assertIn("- **display:** second display ([aaaaaaa](https://github.com/o/r/commit/" + "a" * 40 + "))", text)
        self.assertIn("### Bug fixes", text)
        self.assertIn("### Documentation", text)
        self.assertIn("### Other changes", text)
        self.assertNotIn("tidy", text)
        self.assertNotIn("chore(release)", text)

    def test_empty_section(self):
        text = release.render_section((1, 0, 1), "2026-11-01", [commit("chore: x")])
        self.assertIn("No user-facing changes.", text)

    def test_update_inserts_above_newest(self):
        existing = "# Changelog\n\nintro\n\n## [0.1.0] - 2026-10-31\n\n- first\n"
        new = release.render_section((0, 2, 0), "2026-11-01", [commit("feat: x")])
        updated = release.update_changelog(existing, new)
        self.assertLess(updated.index("## [0.2.0]"), updated.index("## [0.1.0]"))
        self.assertTrue(updated.startswith("# Changelog"))

    def test_update_appends_when_empty(self):
        updated = release.update_changelog("# Changelog\n", release.render_section((0, 1, 0), "d", [commit("feat: x")]))
        self.assertIn("## [0.1.0] - d", updated)

    def test_find_section_and_notes(self):
        text = "# C\n\n## [0.2.0] - d\n\n### Features\n\n- b\n\n## [0.1.0] - d\n\n- a\n"
        section = release.find_section(text, "0.2.0")
        self.assertIn("- b", section)
        self.assertNotIn("- a", section)
        self.assertIsNone(release.find_section(text, "9.9.9"))
        notes = release.notes_body(section)
        self.assertNotIn("## [0.2.0]", notes)
        self.assertIn("### Features", notes)


if __name__ == "__main__":
    unittest.main(verbosity=2)
