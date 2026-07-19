---
name: release-notes
description: Write the body text for a GitHub release in this repo — the Overview, Features, Bug Fixes, and full Changes list. Use this whenever the user asks to "write release notes", "draft the release text", "summarize what's in the release", or wants prose for a new GitHub release. Covers how to find the last release tag, list the commits and merged PRs on main since that tag, read the diffs and PR descriptions, and turn them into plain-English release notes.
---

# Release notes

Release notes tell the user what changed since the last version. Keep them short.
Keep them true. Read the commits and the pull requests, then write what changed.

## 1. Find the release range

Do not guess. Work out the exact range of commits that will ship.

1. Find the repository owner and name from the remote:

   ```sh
   git --no-pager remote get-url origin
   ```

   Parse the `owner/repo` from it.

2. Find the last published release and its tag with the GitHub tools. Use
   `get_latest_release` (or `list_releases` and take the first entry).

3. Resolve that tag to a commit so you know exactly where the last release ends:

   ```sh
   git --no-pager rev-parse <last-tag>
   git --no-pager log -1 <last-tag>
   ```

4. List the commits on `main` (and `main` only) that will ship in this release.
   Use the `main` branch, not the current working branch:

   ```sh
   git --no-pager log <last-tag>..main --oneline
   ```

   The agent tools work too: `list_commits` with `sha: main` gives the history.
   Count the commits. This is the set of changes to write about.

   If there are no commits since the last tag, stop and tell the user there is
   nothing to release.

## 2. Read what changed

For each commit in the range, understand what it did. Do not stop at the commit
subject.

1. Find the merged pull requests in the range. Commit subjects often carry the PR
   number, e.g. `feat: add tags view (#94)`. Collect those numbers.

2. For each PR, read its description with `pull_request_read` using
   `method: get`. The PR description often states the intent and the fix in
   clearer terms than the commit.

3. When a change is not clear from the title and PR body, read the diff. Use
   `pull_request_read` with `method: get_diff` for a PR, or for a bare commit:

   ```sh
   git --no-pager show <commit-sha> --stat
   git --no-pager show <commit-sha>
   ```

   Read only what you need to understand the change. Do not quote code back at
   the reader.

4. Sort each change into one of three buckets:

   - **Feature** — new functionality the user can see or do.
   - **Bug fix** — something broken that is now fixed. Note what was broken and
     what the fix does.
   - **Other** — dependency upgrades, CI changes, refactors, tooling. These go
     in the plain Changes list, not in Features or Bug Fixes.

## 3. Write the release notes

Use the Hemingway approach:

- Short sentences. One idea per sentence.
- Plain words. No jargon when a common word works.
- Active voice. The subject does the thing.
- No filler. "In order to" is just "to". "At this point in time" is "now".
- No marketing. Say what the code does, not how amazing it is.
- No restating the commit subject. The overview adds new information.

Write for a user who runs the app but has not seen this branch of the code.

## 4. Template

Fill in each section. Drop a section if it has nothing to say. Do not pad.

The **Changes** list is the only section that lists every PR. Features and Bug
Fixes summarize the user-facing changes in plain English.

```markdown
## Overview

<One to three sentences. What is this release about? Name the big themes. A
user should know what to expect after reading this.>

## ✨ Features

- <Feature in one sentence. What can the user do now that they could not
  before? One bullet per feature. Group small related changes.>

## 🐛 Bug Fixes

- <What was broken, and what the fix does. One bullet per fix.>

## 📝 Changes since <last-tag>

- <PR title or commit subject> (#<PR number>) (<short hash>)
- <PR title or commit subject> (#<PR number>) (<short hash>)
```

### Notes on the Changes list

- Keep the existing line format: `- <subject> (#<PR>) (<short hash>)`.
- Use the short hash, 7 characters.
- If a commit has no PR number, drop the `(#NN)` part but keep the subject and
  hash.
- Preserve the original commit subject. Do not rewrite it. This list is the
  audit trail, not the summary.

## 5. Before you hand it back

- [ ] The range is right. Every commit between the last tag and `main` is
  covered, and only those commits.
- [ ] Every claim in Overview, Features, and Bug Fixes is grounded in a diff, a
  commit, or a PR description. No invented detail.
- [ ] Features and Bug Fixes describe what the user sees, not the implementation.
- [ ] The Changes list includes every PR in the range, in the original format.
- [ ] Sentences are short. Words are simple.
- [ ] A user can read it in under a minute and know what changed.
