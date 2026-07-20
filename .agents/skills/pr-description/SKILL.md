---
name: pr-description
description: Write or fill in the body of a pull request in this repo — the Summary, Why, What changed, and Notes for review sections. Use this whenever the user asks to "write a PR description", "describe the changes", "summarize the branch or diff", "fill in the PR body", or otherwise wants prose explaining what a branch changes and why. Covers how to inspect the branch diff against main, how to summarize it in plain English (short sentences, simple words, no jargon, no marketing), and the exact template to follow.
---

# PR description

A PR description tells the reader what the branch brings to `main`. Keep it short.
Keep it true. Read the diff, then write what changed and why.

## 1. Inspect the branch

Do not guess. Look at the actual changes on the branch.

1. Find the base branch (usually `main`).
2. Run a diff to see what this branch adds, removes, or changes:

   ```sh
   git --no-pager diff main...HEAD --stat
   git --no-pager log main..HEAD --oneline
   ```

   If the user already has a PR number, use the GitHub tools instead:
   `pull_request_read` with `method: get` and `method: get_files`.

3. Read the changed files when you need to understand intent. Do not quote code
   back at the reader — they can read the diff.

4. If a spec exists for the change, cite it in MLA form — `(topic NN)`. See
   [`writing-specs`](../writing-specs/SKILL.md).

## 2. Write the description

Use the Hemingway approach:

- Short sentences. One idea per sentence.
- Plain words. No jargon when a common word works.
- Active voice. The subject does the thing.
- No filler. "In order to" is just "to". "At this point in time" is "now".
- No marketing. Say what the code does, not how amazing it is.
- No restating the title. The body adds new information.

Write for a teammate who knows the codebase but has not seen this branch yet.

## 3. Template

Fill in each section. Drop a section if it has nothing to say. Do not pad.

```markdown
## Title
<One sentence. What this branch does.>

## Summary

<One to three sentences. What does this branch add or change in main?>

## Why

<The reason for the change. A bug, a new need, a spec item. One or two sentences.>

## What changed

- <Bullet per logical change. Group related files. Name the area, not every file.>

## Notes for review

- <Anything a reviewer should watch for. Migration, follow-up, risk. Omit if none.>
```

## 4. Before you hand it back

- [ ] Every claim is grounded in the diff or a spec. No invented detail.
- [ ] No code block quotes the diff back at the reader.
- [ ] Sentences are short. Words are simple.
- [ ] A reviewer can read it in under a minute and know what to look for.
