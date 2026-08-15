> **Status: BLOCKED — discovery-only (decided 2026-08-15).** No AC5 path is
> approved: the API-key path has no server endpoint to call, and the
> dashboard-session path was assessed against live evidence and rejected as
> too fragile (build-generated RPC ids, turbo-stream script responses, cookie
> authority). Unblock trigger: OpenCode ships a key-authenticated Zen balance
> endpoint — subscribe to the upstream request at
> <https://github.com/anomalyco/opencode/issues/10448> — then re-verify the
> contracts recorded below and implement using the (providers 04) balance
> pattern.

## Objective

Define a safe, evidence-backed path for an OpenCode Zen provider that reports account balance and billed usage without presenting local estimates as server-authoritative data.

## Context

- `Sources/Providers/OpenCodeZen/` — future provider module; it will own authentication, account-snapshot decoding, and mapping into `ProviderQuota` once the implementation gate in AC5 is satisfied.
- `Sources/Core/ProviderProtocol.swift` — the existing balance-style `UsageLine` model can represent USD balance and spend, as demonstrated by DeepSeek (providers 04), but the authentication metadata may need a provider-defined credential label if Zen requires a dashboard session instead of an API key (core 03).
- `Sources/Core/Keychain.swift` — any Zen API key, dashboard session, or composite credential must remain in Filbert's consolidated Keychain item (core 04).
- `Sources/App/SettingsView.swift` — may need provider-neutral setup copy for a credential that is not an API key; it must not branch on the OpenCode Zen provider ID (ui 05).
- `Package.swift` and `Sources/App/AppMain.swift` — will add and register an orthogonal `OpenCodeZenProvider` target only after this spec contains a verified request contract.
- OpenCode's official [Zen documentation](https://opencode.ai/docs/zen), [Zen account page](https://opencode.ai/zen), [CLI documentation](https://opencode.ai/docs/cli), and upstream [Zen balance API request](https://github.com/anomalyco/opencode/issues/10448) were verified on 2026-08-14.
- **Product boundary:** OpenCode is a client for many providers. OpenCode Zen is its optional prepaid model gateway. `opencode stats` reports costs recorded by local OpenCode sessions across providers; it is not an OpenCode Zen account balance and misses use from other clients.
- **Zen billing model:** Zen is pay as you go. The account holds USD credits, each request is charged using the selected model's per-million-token rates, and the published token categories are input, output, cached read, and cached write. The default auto-reload behavior adds $20 when the balance falls below $5; both values are configurable. A workspace or member may also have a monthly spending limit.
- **Pricing variability:** no peak-hour, off-peak, surge, or time-of-day pricing is documented for Zen. Cost varies by model, token category, and sometimes request context size. Published examples include higher tiers above 200K or 272K tokens. Free models and their availability are temporary. Filbert must therefore consume server-reported balance and billed cost rather than reproduce Zen's pricing table.
- **Separate Go product:** OpenCode Go is a subscription, not Zen's default billing mode. Its documented limits are dollar-valued usage windows ($12 per five hours, $30 weekly, and $60 monthly), and it may fall back to the Zen balance when `Use balance` is enabled. Go quota support is outside this provider's first version and is specified separately in (providers 10) so a Zen balance is never confused with Go subscription capacity.
- **Current API gap:** Zen documents inference endpoints and `GET /zen/v1/models`, but no balance or billing-usage endpoint authenticated by the Zen API key. The upstream balance-API request remains open and explicitly says the web dashboard is currently the only server-authoritative source. The documented OpenCode Console CSV Usage API is a separate organization/service-account product and is not evidence of a personal Zen balance API.
- **Discovery 2026-08-15 — dashboard contract, verified from public source** (`anomalyco/opencode`, commit `4643e65`, `packages/console/`): the billing page (`app/src/routes/workspace/[id]/billing/`) reads a SolidStart server query `queryBillingInfo` (query key `"billing.get"`, defined in `app/src/routes/workspace/common.tsx`). It is not a REST route — the result is embedded in the server-rendered page and revalidated through the build-internal `/_server` RPC. Redacted shape (field names verbatim, values elided):
  ```json
  {
    "customerID": "redacted", "paymentMethodID": "redacted",
    "paymentMethodType": "redacted", "paymentMethodLast4": "redacted",
    "balance": 0,
    "reload": false, "reloadAmount": 0, "reloadAmountMin": 0,
    "reloadTrigger": 0, "reloadTriggerMin": 0,
    "monthlyLimit": null, "monthlyUsage": null, "timeMonthlyUsageUpdated": null,
    "reloadError": null, "timeReloadError": null,
    "subscription": null, "subscriptionID": null, "subscriptionPlan": null,
    "timeSubscriptionBooked": null, "timeSubscriptionSelected": null,
    "lite": null, "liteSubscriptionID": null
  }
  ```
  One response supplies current balance, current-month spend, monthly limit, auto-reload state, and timestamps; currency is USD (the dashboard hardcodes `$` in `formatBalance`); there is no pagination. Units (`common.tsx`, `core/src/schema/billing.sql.ts`, `core/src/billing.ts`): `balance` and `monthlyUsage` are micro-cents (USD = value / 100,000,000); `monthlyLimit`, `reloadAmount`, `reloadTrigger` are whole dollars. Payment identifiers, reload-error state, subscription (Go "black"), and lite fields are ignored by Filbert.
- **Discovery 2026-08-15 — dashboard authentication and scoping:** console server queries authenticate only through an httpOnly session cookie named `auth` (OpenAuth-issued, 365-day max age) read by `getActor` in `app/src/context/auth.ts`; there is no `Authorization` header path. The workspace ID (`wrk_…`) is a URL parameter, and the session's account must map to a member row of that workspace — otherwise the server redirects to `/auth/authorize` rather than returning a JSON 401.
- **Discovery 2026-08-15 — no key-authenticated balance route exists:** the complete `/zen` route tree is inference endpoints, `models`, and the Go product's `go/v1/*`. However `GET /zen/go/v1/usage` proves the server pattern exists: a plain JSON GET authenticated by `Authorization: Bearer <Zen API key>` (401 `AuthError` JSON when the key is missing or invalid, 403 `EntitlementError` without a Go subscription), with keys stored per user per workspace in `KeyTable`. That endpoint — added by community PR [anomalyco/opencode#16513](https://github.com/anomalyco/opencode/pull/16513) (merged 2026-08-11) and specified for Filbert in (providers 10) — measures Go subscription windows, not the Zen balance (AC3), but it is the natural precedent for the upstream-requested `GET /zen/v1/balance`.
- **AC4 live wire capture (2026-08-15), sanitized:** the dashboard revalidates `billing.get` as `GET https://opencode.ai/_server?id=<64-hex build-generated function id>&args=<urlencoded typed-args envelope>` carrying `X-Server-Id: <same id>`, `X-Server-Instance: server-fn:<N>`, and `Cookie: auth=<session>` — no `Authorization` path exists, and the sole argument is the workspace ID (`wrk_<redacted>`) embedded as the string at `a[0].s` inside the envelope. The response is **not JSON**: it is a turbo-stream-style script chunk (a `;0x<hex>;` boundary followed by JavaScript assigning the payload into `self.$R["server-fn:<N>"][0]`), so a client must parse a JS object literal rather than decode JSON. The captured fresh-account payload serves as the sanitized empty-account fixture: every optional field `null`, `balance: 0`, and the server fills reload defaults (`reloadAmount: 20`, `reloadAmountMin: 10`, `reloadTrigger: 5`, `reloadTriggerMin: 5`) while `monthlyLimit`/`monthlyUsage` remain genuinely `null` — the response-side defaults a Filbert mapping must not misread as configured values (AC8). The same query fires from any workspace page (header balance widget), not only the billing page. Unobserved: populated-account encodings (e.g. how a non-null `timeMonthlyUsageUpdated` Date serializes inside the script chunk), expired-session wire bytes, and 429 behavior; the `/zen/go/v1/usage` probe (401 invalid / 403 valid-without-Go / 200 valid-with-Go) remains optional completeness evidence for key validity.

## Acceptance Criteria

### AC1: Treat Zen as prepaid, server-authoritative billing

- **Given** an OpenCode Zen account with paid credits
- **When** its billing model is represented in the provider design
- **Then** Zen is classified as a prepaid USD balance whose value decreases by the server-calculated cost of requests
- **And** monthly spending limits and auto-reload settings are treated as separate controls rather than as the balance itself
- **And** credit-card processing fees are not counted as model usage or subtracted locally by Filbert.

### AC2: Do not invent dynamic pricing

- **Given** Zen's published pricing varies by model, token category, and for some models by context-size tier
- **When** Filbert receives an account snapshot
- **Then** it displays server-reported monetary values without recalculating them from token counts or a bundled pricing table
- **And** it publishes no `PeakHoursConfig`, because no peak/off-peak or time-of-day schedule is documented
- **And** a future pricing-table or free-model change requires no Filbert release unless the account response contract also changes.

### AC3: Keep Zen, Go, local stats, and Console distinct

- **Given** OpenCode exposes several usage-related products and data sources
- **When** the provider scope is reviewed
- **Then** `OpenCode Zen` means the prepaid account at `opencode.ai/zen`
- **And** local `opencode stats` data is rejected as an account-balance source
- **And** OpenCode Go's five-hour, weekly, and monthly subscription windows are not synthesized from Zen spend
- **And** the organization-only Console Usage API is not used unless OpenCode documents that it represents the same Zen workspace and credential.

### AC4: Record the unresolved account contract before coding

- **Given** the official documentation exposes no Zen balance API
- **When** authenticated dashboard reconnaissance is performed by the account owner
- **Then** the spec is updated with the exact request URL, HTTP method, authentication mechanism, workspace scoping, response content type, and redacted response shape for balance and billed usage
- **And** it records whether the response supplies current balance, current-month spend, monthly limit, auto-reload state, currency, timestamps, and pagination
- **And** it records 401/403, 429, and empty-account behavior without committing cookies, API keys, account identifiers, email addresses, or unredacted payloads.

### AC5: Pass an explicit implementation gate

- **Given** AC4 has produced a verified request contract
- **When** the user reviews the discovery result
- **Then** one of these paths is explicitly approved before production code is written:
  1. a supported Zen API authenticated by the existing Zen API key; or
  2. an undocumented dashboard request authenticated by a manually supplied browser session
- **And** if neither path is approved or verifiable, this feature remains discovery-only rather than shipping estimated or fabricated data
- **And** approval of an undocumented path adds a persistent localized disclaimer equivalent to the warning used for Cursor's private API (providers 07).

### AC6: Minimize credential authority

- **Given** the user has approved either credential path from AC5
- **When** the provider is configured
- **Then** when a supported API-key path is available, Filbert stores only the Zen API key in its consolidated Keychain item and sends it only to the verified `https://opencode.ai` endpoint
- **And** if the approved path instead requires a dashboard session, v1 accepts an explicit manual credential and does not automatically read browser cookie databases or browser-owned Keychain items
- **And** the session is stored only in Filbert's consolidated Keychain item, is held in memory only for the request, and is never written to `UserDefaults`, logs, diagnostics, fixtures, or error text (core 04).

### AC7: Use one canonical account-snapshot request

- **Given** a verified and approved account contract
- **When** `fetchQuota(auth:baseURL:)` refreshes Zen
- **Then** it uses one canonical read-only account-snapshot request through `URLSession`
- **And** if the request needs a workspace ID, setup captures and validates that ID rather than polling a second discovery endpoint on every refresh
- **And** the provider performs no inference request, top-up, auto-reload change, spending-limit change, or other account mutation
- **And** a dashboard-session implementation is pinned to the exact `https://opencode.ai` origin and exposes no base-URL override, while a supported API-key implementation may inherit Core's explicit proxy override only if the reviewed API contract permits it (core 02).

### AC8: Map only fields the account actually returns

- **Given** a successful verified account snapshot
- **When** it maps into `ProviderQuota`
- **Then** the headline is the localized server-reported USD balance, such as `"$18.50 left"`
- **And** `UsageLine` values are added for current balance, billed usage, and monthly limit only when those fields are present in the response
- **And** a usage percentage is calculated only when the same response supplies both the used amount and its applicable limit
- **And** missing optional fields remain absent instead of being filled with published defaults such as the $5 auto-reload threshold or $20 reload amount
- **And** all provider-specific interpretation stays inside `OpenCodeZenProvider`.

### AC9: Fail safely and respect rate limits

- **Given** an empty or expired credential, unknown workspace, non-success HTTP status, 429 response, network failure, or changed dashboard payload
- **When** a refresh runs
- **Then** the provider throws a typed, localized error and returns no placeholder quota
- **And** stale previously loaded data remains visible through the existing registry and view-model behavior
- **And** 429 responses honor `Retry-After` when present and otherwise enter bounded exponential backoff
- **And** errors and logs never include response bodies, cookies, API keys, workspace identifiers, or account details.

### AC10: Preserve provider orthogonality

- **Given** the OpenCode Zen provider is eventually implemented
- **When** the package is built and the app renders it
- **Then** its target depends only on `Core`
- **And** no existing provider module changes
- **And** App and Core contain no quota, pricing, or authentication branch keyed on `"opencode-zen"`
- **And** any generic credential-label extension behaves unchanged for every existing provider.

### AC11: Verify fixtures, security, and validation

- **Given** the implementation gate has passed and sanitized fixtures exist
- **When** provider and app tests run
- **Then** tests cover request construction, credential redaction, workspace validation, successful balance mapping, optional fields, zero balance, expired auth, 429 backoff, non-success responses, and payload drift
- **And** tests prove no request mutates the Zen account and no secret reaches persisted non-Keychain storage
- **And** formatting, the full test suite, strict concurrency checks, release build, and static analysis pass without warnings or errors.

## Plan

1. Keep the verified product and pricing findings in this spec current. Do not copy Zen's changing model-price table into production code.
2. While signed in to the target Zen workspace, use browser developer tools to reload the workspace billing page and identify the read-only request that supplies balance and usage. Preserve only a sanitized request description and response fixture; never share or commit the session credential.
3. Test whether the normal Zen inference API key can authenticate that read-only request. Prefer this path if OpenCode supports it. Otherwise document the dashboard-session requirement, expiry behavior, and exact private-contract risk for user review.
4. Update AC4 and the Context section with the verified wire contract, then stop for a second review and the explicit AC5 decision.
5. After approval, add the isolated `OpenCodeZenProvider` target, private wire types, typed errors, localized strings, canonical request, and provider tests. Reuse the balance presentation established by (providers 04).
6. If the selected credential is not an API key, add only the smallest provider-neutral credential-label/setup metadata needed by Settings and keep the secret in the consolidated Keychain item (core 04, ui 05).
7. Register the provider in `AppMain`, add package and test targets, run the repository validation gate, and update the acceptance criteria as they land.

### Discovery status (2026-08-15)

Steps 1–3 were executed against the public console source instead of a live
session; findings are recorded in Context. Conclusion for the AC5 gate:
**path 1 is not selectable today** — no balance endpoint exists anywhere in
the route tree for the API key to authenticate against. Path 2 would mean
replaying the cookie-authenticated `/_server` RPC described above. The AC5
decision is deferred to the user together with the remaining live-capture
items listed in Context.

2026-08-15 update: the live `/_server` wire capture landed (Context). AC4's
evidence set is now complete enough for the AC5 decision — path 2 is fully
specified: GET with a build-generated function id, cookie auth, and a
turbo-stream script response. Expired-session bytes and populated Date
encodings remain unobserved; either way a path-2 implementation would need
tolerant decoding and drift fixtures (AC9, AC11).

**AC5 decision (2026-08-15):** after reviewing the live capture the user
rejected path 2; with path 1 unavailable, neither AC5 path is approved and
this feature is BLOCKED as discovery-only. Revisit when the upstream
endpoint ships.

No production code is written until this spec is reviewed, AC4 is completed with sanitized evidence, and the user explicitly selects an AC5 path.

## Risks

- **No public Zen balance API exists today.** The preferred API-key integration cannot be implemented until OpenCode exposes one; the upstream request remains open. Source-verified 2026-08-15: the only key-authenticated non-inference endpoint anywhere under `/zen` is the Go usage route.
- **The `/_server` RPC is a build-internal contract.** Live-confirmed 2026-08-15: the function is addressed by a 64-hex build-generated id (echoed in `X-Server-Id`/`X-Server-Instance`), the response is a turbo-stream script rather than JSON, and the id regenerates whenever the console's function source changes. A path-2 client would need to scrape the current id from the deployed page before use and parse a JS object literal — a deeper private-contract dependency than Cursor's (providers 07), with no discovery endpoint to ease it.
- **The dashboard is a private contract.** HTML, serialized server functions, workspace routes, and response fields may change without notice. A dashboard implementation needs a visible disclaimer, tolerant decoding, fixtures, and a clean failure state.
- **A browser session has broader authority than an inference key.** Manual opt-in, Keychain-only storage, strict host validation, redacted errors, and read-only requests are mandatory. Automatic browser-cookie extraction is deliberately excluded from v1.
- **Balance, spend limit, and charges are different values.** Auto-reload can charge a card even when a monthly usage limit prevents further model spend; Filbert must not combine them into one percentage or promise a maximum charge.
- **Published rates are volatile.** Context-size tiers, model availability, free promotions, and prices can change independently of Filbert. Server-reported billed cost is the only safe financial source.
- **Zen and Go can share one account.** `Use balance` lets exhausted Go usage consume Zen credits, but this does not turn Zen into a subscription window. A later Go provider must remain separate and may display the shared Zen balance only with clear labels.
