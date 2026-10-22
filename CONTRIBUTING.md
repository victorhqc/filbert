# Contributing to Filbert

Thanks for helping build Filbert. This guide covers how we work: the
spec-first workflow, the coding standards, commits, and pull requests.

This is a macOS menu-bar app. It makes network calls to AI provider APIs and
stores API keys in the macOS Keychain. Be methodical. Network and Keychain code
deserves extra care. No quick fixes or temporary hacks unless someone asks for
one.

To set up your Mac, build Filbert, and learn the project layout, read
[`DEVELOPMENT.md`](DEVELOPMENT.md).

## Spec-first

Every feature starts as a spec. Write no code until a spec exists and the owner
has reviewed it. If there is no spec for your change, stop and write one first.

The spec format lives in
[`.agents/skills/writing-specs/SKILL.md`](.agents/skills/writing-specs/SKILL.md).

## Keep providers orthogonal

The provider architecture is orthogonal. Adding a provider must not force a
change in another provider or in the core app. To add one, you implement
`AIProvider` and register it. Nothing else changes. A provider module depends
only on `Core`, and **providers know nothing about each other**. See
[Architecture](DEVELOPMENT.md#architecture).

When you write a provider module:

- Make only `AIProvider` public. Keep helpers internal.
- Use one `URLSession`, set up with the provider's base URL and headers.
- Map the response into the shared `ProviderQuota` model. Provider-specific
  fields stay out of the core.
- Handle auth errors (401), rate limits (429), and network errors on their own.
- Record errors only. **Never log credentials, headers, or raw response bodies.**

## Network rules

This app makes outbound HTTPS calls to provider APIs. Follow these rules:

- **One request shape per provider.** Use `URLSession` directly. No third-party
  networking libraries unless the owner adds one.
- **Handle network errors gracefully.** A failed refresh must not crash the
  app. Show stale data with a timestamp, not a blank panel.
- **Rate-limit refreshes.** Default: one refresh every 5 minutes. Providers
  with tighter limits may need longer intervals.
- **Respect provider rate limits.** On a 429, back off.
- **Keep keys in the Keychain.** Read a key at request time. Never hold it in
  memory longer than you need.

## Coding standards

1. **Naming** — say what you mean. No hidden magic.
2. **Guard clauses** — prefer `guard` and an early return over deep nesting.
3. **Side effects at the edges** — each function does one thing. Network calls
   and Keychain access happen at clear boundaries.
4. **DRY, but no premature abstraction** — explicit beats implicit.
5. **Idiomatic Swift** — use `async/await`, `Result` types, and SwiftUI idioms.
6. **Protocol-oriented** — each provider is a struct or actor that conforms to
   `AIProvider`. The hub talks to the protocol, never to a concrete provider.
7. **Comments are a last resort** — follow the
   [minimal-comments](#minimal-comments) rules. Do not cite specs or
   acceptance criteria in code. Spec citations belong in `specs/`.
8. **Dependencies** — add a package to `Package.swift` before you use it. Prefer
   Apple frameworks over third-party ones.
9. **Concurrency** — use structured concurrency (`async/await`, `Task`,
   `@MainActor`). No bare `DispatchQueue` unless you bridge a callback API.

## Minimal comments

The code is the comment. Write no comment by default. If you want to explain
*what* the code does, rename or extract something instead. A comment is valid
only for:

- a non-obvious domain or business rule,
- an external system's quirk or contract,
- a deliberate deviation from what a reader expects,
- the reason for a necessary suppression or cast.

Code, tests, scripts, and config never cite a spec or an acceptance criterion.
If a spec drives a non-obvious decision, state the reason in plain words.

The full rules are in the
[minimal-comments](https://github.com/victorhqc/skills.sh/tree/main/skills/minimal-comments)
skill. AI agents in this repo follow it. Install it with:

```sh
npx skills add victorhqc/skills.sh --skill minimal-comments
```

## Validation gate

Run the validation gate before you hand off a change. It formats, lints,
builds, and tests the project, the same way CI does. The tool setup and the
commands are in [`DEVELOPMENT.md`](DEVELOPMENT.md#validation-gate).

## Commits

We use [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).
Every commit message starts with a type, then a short summary in the present
tense.

```
<type>(<scope>): <summary>
```

- `<type>` says what kind of change it is. See the list below.
- `<scope>` is optional. It names the area you touched, like `core`, `zai`, or
  `build`.
- `<summary>` is a short line in the present tense. "add z.ai provider", not
  "added" or "adds".

The types we use:

- **feat** — a new feature.
- **fix** — a bug fix.
- **docs** — docs only.
- **refactor** — a code change that neither fixes a bug nor adds a feature.
- **test** — adding or fixing tests.
- **chore** — build, tooling, or housekeeping.
- **ci** — CI configuration.

A breaking change adds a `!` after the type, like `feat(core)!: ...`, and
explains the break in the commit body.

Examples from this repo:

```
feat(core): consolidate keychain to single item for single auth prompt
fix(build): set SDKROOT for relink step in build-dmg
docs: update mascot image in README
```

## Pull requests

Keep the PR body short and true. Say what the branch changes and why.

Use the **pr-description** skill to write it. The skill writes a short Summary,
a Mermaid diagram of the change, and a reading order for the files. It can open
or update the PR with `gh` after you confirm, or give you a markdown block to
paste.

The skill is not in this repo. Install it from
[victorhqc/skills.sh](https://github.com/victorhqc/skills.sh/tree/main/skills/pr-description):

```sh
npx skills add victorhqc/skills.sh --skill pr-description
```

## License

By contributing, you agree that your work ships under the project's
[MIT License](./LICENSE).
