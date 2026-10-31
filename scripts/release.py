#!/usr/bin/env python3
"""Work out the next version from Conventional Commits and keep CHANGELOG.md up to date.

    scripts/release.py plan                       # dry run: prints the next version and the changelog section
    scripts/release.py plan --write               # also updates VERSION and CHANGELOG.md
    scripts/release.py plan --bump minor          # force a bump instead of reading the commits
    scripts/release.py plan --version 1.0.0       # force an exact version

Rules (Conventional Commits, https://www.conventionalcommits.org/):
    feat                       -> minor
    fix, perf, revert          -> patch
    "type!:" or BREAKING CHANGE -> major (while the major version is 0, a minor bump instead)
    docs, refactor             -> listed in the changelog, no version bump on their own
    build, ci, chore, test, style -> not listed, no bump
    anything else              -> listed under "Other changes", no bump

With no v*.*.* tag yet, the first release is the version in the VERSION file, and an existing hand-written
CHANGELOG section for it is used as is.
"""
import argparse
import datetime
import os
import re
import subprocess
import sys

SEMVER = re.compile(r"^(\d+)\.(\d+)\.(\d+)$")
TAG = re.compile(r"^v(\d+)\.(\d+)\.(\d+)$")
CONVENTIONAL = re.compile(r"^(?P<type>[A-Za-z]+)(?:\((?P<scope>[^)]+)\))?(?P<bang>!)?: (?P<subject>.+)$")
BREAKING_BODY = re.compile(r"^BREAKING[ -]CHANGE:", re.MULTILINE)

# type -> (changelog heading, bump it triggers)
LISTED = {
    "feat": ("Features", "minor"),
    "fix": ("Bug fixes", "patch"),
    "perf": ("Performance", "patch"),
    "revert": ("Reverts", "patch"),
    "docs": ("Documentation", None),
    "refactor": ("Refactoring", None),
}
HIDDEN = {"build", "ci", "chore", "test", "style"}
HEADING_ORDER = ["Features", "Bug fixes", "Performance", "Reverts", "Documentation", "Refactoring", "Other changes"]


class Commit:
    def __init__(self, sha, short, subject, body=""):
        self.sha = sha
        self.short = short
        self.subject = subject.strip()
        self.body = body or ""
        match = CONVENTIONAL.match(self.subject)
        self.conventional = bool(match)
        self.type = match.group("type").lower() if match else None
        self.scope = match.group("scope") if match else None
        self.message = match.group("subject").strip() if match else self.subject
        self.breaking = bool(match and match.group("bang")) or bool(BREAKING_BODY.search(self.body))

    @property
    def is_release_commit(self):
        return self.conventional and self.type == "chore" and (self.scope or "") == "release"

    @property
    def level(self):
        """The bump this commit asks for: 'major', 'minor', 'patch' or None."""
        if self.breaking:
            return "major"
        if self.type in LISTED:
            return LISTED[self.type][1]
        return None

    @property
    def heading(self):
        if self.type in LISTED:
            return LISTED[self.type][0]
        if self.type in HIDDEN:
            return None
        return "Other changes"


def parse_version(text):
    match = SEMVER.match(text.strip())
    if not match:
        raise ValueError(f"'{text}' is not a version like 1.2.3")
    return tuple(int(part) for part in match.groups())


def format_version(version):
    return ".".join(str(part) for part in version)


def decide_bump(commits, version):
    """The bump the commits call for, or None if none of them is releasable."""
    order = {"patch": 1, "minor": 2, "major": 3}
    best = None
    for commit in commits:
        level = commit.level
        if level and (best is None or order[level] > order[best]):
            best = level
    if best == "major" and version[0] == 0:
        best = "minor"   # before 1.0.0 a breaking change bumps the minor version
    return best


def bump_version(version, level):
    major, minor, patch = version
    if level == "major":
        return (major + 1, 0, 0)
    if level == "minor":
        return (major, minor + 1, 0)
    if level == "patch":
        return (major, minor, patch + 1)
    raise ValueError(f"unknown bump '{level}'")


def render_section(version, date, commits, repo_url=None):
    """The changelog section for a release, header line included."""
    groups = {}
    breaking = []
    for commit in commits:
        if commit.is_release_commit or commit.heading is None:
            continue
        line = format_entry(commit, repo_url)
        groups.setdefault(commit.heading, []).append(line)
        if commit.breaking:
            breaking.append(line)
    lines = [f"## [{format_version(version)}] - {date}", ""]
    if breaking:
        lines += ["### Breaking changes", ""] + [f"- {entry}" for entry in breaking] + [""]
    for heading in HEADING_ORDER:
        if heading in groups:
            lines += [f"### {heading}", ""] + [f"- {entry}" for entry in groups[heading]] + [""]
    if len(lines) == 2:
        lines += ["No user-facing changes.", ""]
    return "\n".join(lines).rstrip() + "\n"


def format_entry(commit, repo_url):
    text = commit.message
    if commit.scope:
        text = f"**{commit.scope}:** {text}"
    link = f"[{commit.short}]({repo_url}/commit/{commit.sha})" if repo_url else commit.short
    return f"{text} ({link})"


def update_changelog(text, section):
    """Insert a section above the newest existing release (or append when there is none)."""
    match = re.search(r"^## \[", text, re.MULTILINE)
    if match:
        return text[: match.start()] + section + "\n" + text[match.start():]
    return text.rstrip() + "\n\n" + section


def find_section(text, version):
    """The existing changelog section for a version, header included, or None."""
    header = re.compile(rf"^## \[{re.escape(version)}\].*$", re.MULTILINE)
    start = header.search(text)
    if not start:
        return None
    following = re.search(r"^## \[", text[start.end():], re.MULTILINE)
    end = start.end() + following.start() if following else len(text)
    return text[start.start():end].rstrip() + "\n"


def notes_body(section):
    """Release notes: the section without its '## [x] - date' header line."""
    lines = section.splitlines()
    return "\n".join(lines[1:]).strip() + "\n"


# --- git and files ---------------------------------------------------------------------------------------------

def git(*args):
    return subprocess.run(["git", *args], check=True, capture_output=True, text=True).stdout.strip()


def repo_root():
    return git("rev-parse", "--show-toplevel")


def latest_tag():
    try:
        tag = git("describe", "--tags", "--abbrev=0", "--match", "v[0-9]*")
    except subprocess.CalledProcessError:
        return None
    return tag if TAG.match(tag) else None


def commits_in(rev_range):
    args = ["log", "--no-merges", "--format=%H%x1f%h%x1f%s%x1f%b%x1e"]
    if rev_range:
        args.append(rev_range)
    out = git(*args)
    commits = []
    for record in out.split("\x1e"):
        record = record.strip("\n")
        if not record.strip():
            continue
        sha, short, subject, body = (record.split("\x1f") + ["", "", "", ""])[:4]
        commits.append(Commit(sha.strip(), short.strip(), subject, body))
    return commits


def repo_url():
    try:
        remote = git("remote", "get-url", "origin")
    except subprocess.CalledProcessError:
        return None
    match = re.search(r"github\.com[:/](?P<path>[^/]+/[^/]+?)(?:\.git)?$", remote)
    return f"https://github.com/{match.group('path')}" if match else None


def write_github_output(path, values):
    with open(path, "a", encoding="utf-8") as handle:
        for key, value in values.items():
            handle.write(f"{key}={value}\n")


# --- command ---------------------------------------------------------------------------------------------------

def plan(args):
    root = repo_root()
    os.chdir(root)
    version_file = os.path.join(root, "VERSION")
    changelog_file = os.path.join(root, "CHANGELOG.md")
    file_version = parse_version(open(version_file, encoding="utf-8").read()) if os.path.exists(version_file) else (0, 1, 0)
    changelog = open(changelog_file, encoding="utf-8").read() if os.path.exists(changelog_file) else "# Changelog\n"
    date = args.date or datetime.date.today().isoformat()
    url = repo_url()

    tag = latest_tag()
    if tag is None:
        # First release: no tag to compare with.
        version = parse_version(args.version) if args.version else file_version
        previous = None
        commits = commits_in(None)
        reason = "first release"
        bump = "initial"
    else:
        previous = parse_version(tag[1:])
        commits = [c for c in commits_in(f"{tag}..HEAD") if not c.is_release_commit]
        if args.version:
            version = parse_version(args.version)
            bump, reason = "manual", "version given explicitly"
        elif args.bump != "auto":
            version = bump_version(previous, args.bump)
            bump, reason = args.bump, "bump given explicitly"
        else:
            level = decide_bump(commits, previous)
            if level is None:
                print(f"No releasable changes since {tag}: only docs, chores or other commits.\n"
                      "Use --bump patch|minor|major or --version to release anyway.", file=sys.stderr)
                return 2
            version = bump_version(previous, level)
            bump = level
            reason = f"{len(commits)} commit(s) since {tag}, highest change: {level}"
        if previous and version <= previous:
            print(f"The new version {format_version(version)} must be higher than {tag}.", file=sys.stderr)
            return 2

    version_text = format_version(version)
    existing = find_section(changelog, version_text)
    section = existing if (existing and (tag is None or args.keep_existing)) else render_section(version, date, commits, url)

    print(f"previous : {tag or '(none)'}")
    print(f"next     : v{version_text}  ({reason})")
    print(f"commits  : {len(commits)}")
    print()
    print(section)

    notes = notes_body(section)
    if args.notes_out:
        with open(args.notes_out, "w", encoding="utf-8") as handle:
            handle.write(notes)
    if args.github_output:
        write_github_output(args.github_output, {
            "version": version_text, "tag": f"v{version_text}", "bump": bump, "previous": tag or "",
        })
    if args.write:
        with open(version_file, "w", encoding="utf-8") as handle:
            handle.write(version_text + "\n")
        if not existing:
            with open(changelog_file, "w", encoding="utf-8") as handle:
                handle.write(update_changelog(changelog, section))
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("plan", help="work out the next version and changelog section")
    p.add_argument("--bump", choices=["auto", "major", "minor", "patch"], default="auto")
    p.add_argument("--version", help="exact version to release, for example 1.0.0")
    p.add_argument("--write", action="store_true", help="update VERSION and CHANGELOG.md")
    p.add_argument("--notes-out", help="write the release notes (changelog section without its header) to this file")
    p.add_argument("--github-output", help="append version, tag, bump and previous to this file ($GITHUB_OUTPUT)")
    p.add_argument("--date", help="release date, default today")
    p.add_argument("--keep-existing", action="store_true", help="reuse an existing changelog section for the version")
    args = parser.parse_args(argv)
    return plan(args)


if __name__ == "__main__":
    sys.exit(main())
