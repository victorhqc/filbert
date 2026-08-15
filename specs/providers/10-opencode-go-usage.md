> Implemented 2026-08-15. Contract fully verified 2026-08-15 — source, merged
> PR #16513, and live `200`/`401` samples from a Go-entitled key.

## Objective

Add an `OpenCodeGoProvider` that reports OpenCode Go subscription usage windows from the key-authenticated `GET /zen/go/v1/usage` endpoint without conflating them with the Zen prepaid balance.

## Context

- `Sources/Providers/OpenCodeGo/` — future provider module; owns the request, decoding, and window mapping.
- `Package.swift` and `Sources/App/AppMain.swift` — gain an orthogonal `OpenCodeGoProvider` target and one registration line, mirroring (providers 04).
- `Sources/Core/ProviderProtocol.swift` — unchanged; `UsageLine` already carries `percentage`, `windowDuration`, and `resetDate` — exactly what this endpoint returns (core 01).
- `Sources/Core/Keychain.swift` — the OpenCode API key stays in Filbert's consolidated Keychain item (core 04).
- **Host boundary:** proxy permission for this bearer-authenticated endpoint
  was not confirmed in review, so the provider rejects non-`opencode.ai` base
  URLs and cross-host redirects before they can receive the API key. Core's
  provider-neutral override mechanism remains unchanged.
- **Wire contract, live since 2026-08-11** — added by community PR [anomalyco/opencode#16513](https://github.com/anomalyco/opencode/pull/16513) (merged to `dev`, closing #16017), source-verified at commit `4643e65` in `packages/console/app/src/routes/zen/go/v1/usage.ts`:
  - `GET https://opencode.ai/zen/go/v1/usage` with `Authorization: Bearer <OpenCode API key>` — the same `KeyTable` lookup the Zen gateway uses.
  - `200 application/json`:
    ```json
    {
      "usage": {
        "rolling":  { "status": "ok", "percent": 0, "resetsAt": "2026-08-15T12:00:00.000Z" },
        "weekly":   { "status": "ok", "percent": 0, "resetsAt": "…" },
        "monthly":  { "status": "ok", "percent": 0, "resetsAt": "…" }
      }
    }
    ```
    `status` is `"ok" | "rate-limited"`; percentages only — the endpoint never returns dollar amounts (confirmed by early adopters, some of whom synthesize spend as `limit × percent`, which Filbert must not do). Live-verified 2026-08-15: `percent` is an integer on a 0–100 scale (`Math.floor(min(100, usage/limit × 100))` per `core/src/subscription.ts`, pinned at 100 when rate-limited); `resetsAt` is ISO-8601 UTC **with fractional seconds** (observed `2026-08-15T03:20:21.283Z`), so decoding needs a fractional-seconds-capable date strategy; and the windows anchor differently server-side (sliding five-hour window, calendar week, subscription-anchored month), so `resetDate` must come solely from `resetsAt`. Confirmed under real spend the same day: `rolling.percent` rose to 1 (~1% of the $12 window) while weekly/monthly floored to 0, `rolling.resetsAt` slid forward with the billable request (sliding window anchored to last usage), and every `resetsAt` is recomputed per fetch — all source-derived behaviors observed live. A follow-up sample (rolling 2%, weekly 1%) kept the same window anchor while percent rose, showing usage lands asynchronously a few seconds after request completion; and `resetsAt` milliseconds track fetch time (integer-second `resetInSec`), so the string is not stable across fetches and must not be diffed for change detection.
  - `401` `{"type":"error","error":{"type":"AuthError","message":"Unauthorized"}}` — observed verbatim 2026-08-15 — for a missing or invalid key; `403` `EntitlementError` ("OpenCode Go subscription required.") when the key is valid but has no Go subscription (source-verified, not yet observed live).
- **Contract status:** absent from the official docs page, but maintainer-merged, live, and adopted within days by a wave of third-party meters (OpenUsage, pi extensions, claude-usage-api, and others) — a de-facto client contract, far sturdier than the `/_server` RPC rejected in (providers 09).
- **Product boundary (providers 09 AC3):** OpenCode Go is a subscription with dollar-valued windows ($12 per five hours, $30 weekly, $60 monthly per the Go docs). It is not the Zen prepaid balance; `Use balance` may couple them server-side, but Filbert never merges them into one number.

## Acceptance Criteria

### AC1: One canonical, key-authenticated read
- **Given** a configured provider
- **When** `fetchQuota(auth:baseURL:)` runs
- **Then** it issues a single `GET <baseURL>/zen/go/v1/usage` with `Authorization: Bearer <key>` read from the consolidated Keychain item (core 04), performs no inference request or account mutation, and sends the key nowhere but `https://opencode.ai` (inheriting Core's explicit proxy override only if review confirms the contract permits it, core 02)

### AC2: Server-authoritative window mapping
- **Given** a `200` response
- **When** it maps into `ProviderQuota`
- **Then** `rolling`, `weekly`, and `monthly` each become a `UsageLine` with `percentage` from `percent`, `resetDate` from `resetsAt`, and `windowDuration` of five hours / one week / one month, in the coding-plan style of (providers 01)
- **And** `status: "rate-limited"` is surfaced rather than swallowed
- **And** no dollar figure is synthesized — neither from the documented $12/$30/$60 limits nor as `percent × limit` — and no line mixes in the Zen prepaid balance

### AC3: Typed failure states
- **Given** a missing key, `401`, `403`, `429`, network failure, or undecodable body
- **When** a refresh runs
- **Then** the provider throws a typed, localized error and returns no placeholder quota
- **And** `401` maps to an authentication-failed message while `403` `EntitlementError` maps to a distinct "no OpenCode Go subscription" message — the credential is valid but unentitled

### AC4: Orthogonality and validation
- **Given** the provider is implemented
- **When** the package builds and tests run
- **Then** its target depends only on `Core`, no existing provider changes, and App/Core contain no branch keyed on `"opencode-go"`
- **And** sanitized fixtures cover the `200`, `401`, `403`, and payload-drift cases, passing the repository validation gate without warnings

## Plan

1. [x] Capture one live `200` sample with a Go-entitled key to confirm the source-derived details (`percent` scale, `resetsAt` format) — done 2026-08-15, recorded in Context.
2. [x] Add the `OpenCodeGoProvider` target, private wire types, typed errors, localized strings, and tests, mirroring (providers 04) — completed 2026-08-15.
3. [x] Register in `AppMain`, run the repository validation gate, and mark criteria as they land — completed 2026-08-15; SwiftFormat, SwiftLint, debug/release builds, and 338 tests passed.

## Risks

- **Docs lag.** The endpoint is merged and live but absent from the official Go docs page; a future contract change remains possible, though the wave of third-party adopters makes breaking it costly for OpenCode. Tolerant decoding and drift fixtures stay mandatory.
- **Entitlement dependency.** Without a Go subscription the endpoint always returns `403`; the provider shows nothing for the user until they subscribe.
- **Percent-only payload.** No dollar amounts are available, so the UI shows server-reported percentages and reset times only.
- **`Use balance` coupling.** Go may fall back to the Zen balance when windows are exhausted; that balance remains blocked on (providers 09) and must not be approximated here.
