# AGENTS.md

> Problem definition -> small, safe change -> change review -> refactor - repeat the loop.

---

## 0. Role & Mindset

This is a macOS menu-bar application that tracks AI provider usage. It makes
outbound network calls to provider APIs and stores API keys in the macOS
Keychain.

1. Be methodical and verify changes. Network and Keychain code deserves extra
   care.
2. No quick fixes or temporary hacks unless explicitly requested.
3. You have the authority and obligation to push back on requests that violate
   architectural integrity, type safety, or the Spec-First protocol.
4. The provider architecture is **orthogonal** — adding a provider must not
   require changes to any other provider or to the core app layer.

> **Never mutate git.** Do not commit, push, stage, branch, merge, rebase, or
> reset. Read-only inspection is fine — `git status`, `git diff`, `git log`,
> `git show`, `git remote get-url`, `git rev-parse` — and the `pr-description`
> and `release-notes` skills rely on it. When a git action *changes* state, give
> the exact commands to the user and let them run it.

## 1. Structure

The project follows a Swift Package Manager structure:

- `Sources/App` — the macOS app target: menu bar, popover, widgets, app lifecycle.
- `Sources/Core` — the provider hub: protocol definitions, registry, refresh
  scheduling, data aggregation.
- `Sources/Providers/<Name>` — one module per provider, each implementing the
  `AIProvider` protocol.
- `Tests/` — unit and integration tests, mirroring the Sources layout.

A provider module depends only on `Core`. The app depends only on `Core` (and
transitively on any provider it links). Providers have **no knowledge of each
other**.

## 2. The Spec-First protocol

Every feature starts as a spec. No code is written until a spec exists and the
user has reviewed it.

See [`.agents/skills/writing-specs/SKILL.md`](.agents/skills/writing-specs/SKILL.md)
for the full spec format and rules.

## 3. Internet access

Unlike a local-only application, this project makes outbound HTTPS requests to
provider APIs. Follow these rules:

- **One request shape per provider.** Use `URLSession` directly. No third-party
  networking libraries unless the user explicitly adds one.
- **Handle network errors gracefully.** A failed refresh must not crash the
  app. Show stale data with a timestamp, not a blank panel.
- **Rate-limit refreshes.** Default: one refresh every 5 minutes. Providers
  with tighter rate limits may need longer intervals.
- **Respect provider rate limits.** If a provider returns 429, back off
  exponentially.
- **Never cache API keys outside the Keychain.** Keys are read from Keychain
  at request time and never stored in memory longer than needed.
