---
name: writing-specs
description: Write or edit a spec in ./specs/ for this repo — the Spec-First protocol. Covers where a spec lives (specs/<topic>/NN-short-description.md), the outline template (Objective, Context, Acceptance Criteria, Plan, Risks), and the MANDATORY MLA in-text citation format — (topic NN) — for referring to other specs. Use this whenever you create, author, extend, or revise any spec/outline/acceptance-criteria file, or need to cross-reference one spec from another.
---

# Writing specs

The Spec-First protocol: **problem definition → small, safe change → change
review → refactor → repeat.** No code is written until a spec exists and the
user has reviewed it. This skill is the authority on *how a spec is structured
and how specs cite each other*; `AGENTS.md` is the authority on the surrounding
workflow.

## 1. Where the spec lives

```
specs/
├── <topic>/
│   ├── 01-short-description.md
│   ├── 02-short-description.md
│   └── ...
```

- **Pick the closest existing topic folder or create one.** Current topics:
  `core`, `providers`, `ui`, `widgets`, `ci`. Only create a new topic folder if
  the work fits none of them.
- **Number sequentially _within that topic folder_.** List the folder's files,
  take the next number, zero-pad to two digits (`07`, not `7`).
- **File name:** `NN-short-description.md` — kebab-case, intention-revealing,
  no spaces.

### Topic guide

| Topic        | What belongs here                                     |
|--------------|-------------------------------------------------------|
| `core`       | Provider protocol, hub, registry, Keychain, refresh   |
| `providers`  | Individual provider implementations (z.ai, Claude, …) |
| `ui`         | Menu bar, popover, settings, app lifecycle            |
| `widgets`    | Desktop widgets, Notification Center integration      |
| `ci`         | GitHub Actions workflows, CI configuration, tooling   |

## 2. MLA cross-references (MANDATORY)

When a spec mentions another spec, cite it with an **MLA-style in-text
citation**: the **main topic** followed by the **spec number**, in parentheses.
This is the analogue of MLA's `(Author Page)` — here `(topic number)`.

```
(core 03)                     one spec
(providers 02, ui 01)         several specs, comma-separated
(providers 04 AC10)           a specific acceptance criterion inside a spec
```

**Rules:**
- Always parenthesized, lowercase topic, zero-padded number matching the file
  (`03`, not `3`).
- Never write prose forms like `spec 03`, `(spec 03)`, `see spec 3`, or a bare
  file path when you mean *another spec*. Those are non-compliant.
- A path like `` `Sources/Core/ProviderHub.swift` `` pointing at **source code**
  is not a spec citation — leave those as file paths.
- **The same form applies in production code.** When a code comment refers to a
  spec, cite it the same way, e.g.
  `// peak-hours window matches (providers 02)`.

**Fix on sight.** Existing specs may use non-compliant `spec 03` / `(spec 03)`
forms. If you edit a spec that contains a non-compliant reference, convert it:

| Non-compliant  | Correct            |
|----------------|--------------------|
| `(spec 03)`    | `(core 03)`        |
| `in spec 03`   | `(core 03)`        |
| `spec 04 AC10` | `(providers 04 AC10)` |
| `see spec 3`   | `(ui 03)`          |

## 3. The outline

Keep it concise — Hemingway, not academia. Short declarative sentences. Write
as many acceptance criteria as the feature needs, no filler.

```markdown
## Objective
1 sentence.

## Context
- Key files affected — `Sources/Core/Whatever.swift` — one line on why it matters
- Cross-referenced specs go here in MLA form, e.g. builds on (core 03)

## Acceptance Criteria

### AC1: <short description>
- **Given** <precondition>
- **When** <action>
- **Then** <outcome>

### AC2: ...

## Plan
Brief description of the approach. Code snippets ONLY when they clarify an
interface or data shape.

## Risks
- Any known regression or side effect
```

### Section rules
- **Objective** — exactly one sentence. If it needs two, the spec is doing too
  much; split it.
- **Context** — bullet list of affected files, each with a terse reason. This
  is where you name the reference implementations and cite related specs in MLA
  form.
- **Acceptance Criteria** — every AC is Given/When/Then. Number them `AC1`,
  `AC2`, … so they can be cited as `(topic NN ACx)`. Make each one testable —
  a reviewer should be able to check it off.
- **Plan** — the approach, not a diff. No large code blocks; a small snippet is
  fine only to pin down a protocol signature or data shape.
- **Risks** — regressions and side effects a reviewer should watch for. Omit
  only if there are genuinely none.

## 4. After writing

- **STOP and wait for the user** before writing any code. The spec is a
  checkpoint, not a formality.
- During implementation the spec is the source of truth: re-read it before each
  change, mark items `[x]` as they land, and log new findings back into the
  spec.

## Self-check before handing a spec back

- [ ] File is at `specs/<topic>/NN-short-description.md`, number is the next
  free one in that folder, zero-padded.
- [ ] Objective is one sentence.
- [ ] Every AC is Given/When/Then and testable.
- [ ] **Every reference to another spec uses MLA `(topic NN)` form** — no `spec
  03`, no bare `(spec NN)`.
- [ ] If I edited an existing spec, I converted any legacy `spec NN` references
  I touched.
- [ ] Plan has no diff-sized code blocks; Risks lists real regressions.
