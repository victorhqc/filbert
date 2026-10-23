## Objective

Rename the z.ai provider to "z.ai Coding Plan" and make it read z.ai's business envelope, so a key with no active GLM Coding Plan gets a clear message instead of "Unexpected response from server."

## Context

- Status: implemented 2026-10-23, uncommitted. The user approved the spec that day. We cannot test it live, so public payload evidence replaces a capture (Evidence). Builds on (providers 01) and (providers 11). Standard keys get their own provider (providers 25).
- `Sources/Providers/ZAI/ZAIWire.swift` — `ZAIQuotaResponse` requires `data.limits`. A no-plan body has no `data`, so decoding fails and the user sees the generic error.
- `Sources/Providers/ZAI/ZAIProvider.swift` — `get` treats every HTTP `200` as success. `ZAIError` has no case for business codes. A code comment says the monitor endpoints are plan-agnostic for every key, which is no longer true.
- `Tests/ZAIProviderTests/` — mapping, observation, and retry tests. New fixtures go in `Fixtures/`.
- `README.md`, `SETUP.md`, `site/index.html` — list the provider as "z.ai" and must use the new name and say which key to use.
- `Sources/Providers/ZAIAPI/ZAIAPIProvider.swift` (providers 25) — its disclaimer says "Coding Plan usage is shown by the z.ai provider." The `SETUP.md` z.ai API section says "use the z.ai provider." Both must use the new name. This is a string change only: the two modules still do not import each other.
- `providerName` is the display name in Settings, on provider cards, and in the menu-bar VoiceOver label (`Sources/App/MenuBarProviderPresentation.swift`). Cards have room for the longer name, and the menu bar shows only an icon and a value. Preferences, order, enablement, and the Keychain key are keyed by `providerId`, so a rename moves no stored state.
- The user chose the rename on 2026-10-23, so that the two z.ai providers are easy to tell apart.
- Since 2026-10-16, z.ai issues separate keys ([API key management](https://docs.z.ai/devpack/notice/api-key-management)):
  - Standard keys bill the account balance and never use Coding Plan quota.
  - Accounts that ever had a Coding Plan got Compatible keys. After a plan expires, a Compatible key does not switch to pay-as-you-go.
  - Team Plan projects get Team Plan keys.
  - No response field reveals the key type.

## Evidence

Collected 2026-10-23 from public sources. No live call was made.

- **No plan, live, both hosts, HTTP 200** (view-limits issue #1 and PR #28, `api.z.ai` and `open.bigmodel.cn`, 2026-10-03; cc-switch `coding_plan.rs`, `ZHIPU_NO_PLAN_BODY`, a China pay-as-you-go key, 2026-10-18; glm-for-copilot issue #48, global, 2026-08-28):
  ```json
  {"code":500,"msg":"当前用户不存在coding plan","success":false}
  ```
  A lapsed plan and a key that never had one look the same. The message is Chinese on both hosts. No English variant has been captured.
- **Auth failures, live, HTTP 200** (view-limits PR #28):
  ```json
  {"code":1000,"msg":"Authentication Failed","success":false}
  {"code":1001,"msg":"Authentication parameter not received in Header, unable to authenticate","success":false}
  ```
  An expired token gives `{"code":401,"msg":"令牌已过期或验证不正确","success":false}`. That is from the cc-switch fixture only.
- **Team keys** without `?type=2` and the organization and project headers get the no-plan body (zai-coding-plugins issue #22). With them, they get `{"code":200,…,"data":{"limits":[],"level":"pro"},"success":true}` (issue #36).
- The source for the empty-limits body elides `msg`. The fixture uses "Operation successful", the `msg` of z.ai's live success envelope (providers 25).
- **`subscription/list` with no plan** returns `{"code":200,"success":true,"data":[]}`. The provider already reads that as no version.
- Other tools detect no plan with code `500` plus a message that matches `coding plan` (cc-switch, glm-for-copilot, ZCode).

## Acceptance Criteria

### AC1: The envelope is read before the limits

- **Given** an HTTP `200` from `quota/limit`
- **When** the provider decodes it
- **Then** it first reads `code`, `msg`, and `success`
- **And** only `success == true` with a `data` object goes on to the existing mapping
- **And** a body without `success` but with `data.limits` still maps, so the fixtures from (providers 11) keep passing
- **And** a body with neither `data` nor `code` is a decoding error.

### AC2: No Coding Plan has its own message

- **Given** an envelope with `code == 500` and a `msg` that contains `coding plan`, ignoring case
- **When** `fetchQuota` runs
- **Then** it throws `ZAIError.noCodingPlan`
- **And** the error reads "This key has no active GLM Coding Plan. For pay-as-you-go balance, use the z.ai API provider with a Standard key."
- **And** `subscription/list` is not called, and nothing is logged.

### AC3: Business auth failures read as auth failures

- **Given** an envelope with code `401`, `1000`, `1001`, or `1002`
- **When** `fetchQuota` runs
- **Then** it throws `ZAIError.business(code)`, which reads the same as HTTP `401`: "Authentication failed. Check your API key."
- **And** nothing is logged.

### AC4: Other business failures are typed and logged without text

- **Given** any other envelope with `success == false`
- **When** `fetchQuota` runs
- **Then** it throws `ZAIError.business(code)`, which reads "Unexpected response from server."
- **And** the error log records only the code, never the server's `msg`.

### AC5: An empty plan reads as no windows

- **Given** a successful envelope with an empty `limits` array
- **When** the provider maps it
- **Then** the headline reads "No usage windows reported" instead of "No data", and no lines are shown
- **And** a non-empty array with no recognized window still reads "No data".

### AC6: The provider is named "z.ai Coding Plan"

- **Given** an existing user with a z.ai key, order, enablement, and collapse state
- **When** they update the app
- **Then** Settings, the provider card, and the menu-bar VoiceOver label show "z.ai Coding Plan"
- **And** the provider ID stays `zai`, so the stored key and every preference carry over with no migration
- **And** the description reads "Monitor GLM Coding Plan quota"
- **And** `README.md` and `SETUP.md` use the new name, and `SETUP.md` says that Coding Plan and Compatible keys go here and Standard keys go to the z.ai API provider (providers 25)
- **And** `site/index.html` keeps its "z.ai" tile, which already names both products (Plan step 9)
- **And** the z.ai API disclaimer reads "Use a Standard API key. Coding Plan usage is shown by the z.ai Coding Plan provider. For BigModel (bigmodel.cn) accounts, set the base URL to https://open.bigmodel.cn.", in every shipped locale.

### AC7: Existing behavior holds

- **Given** the legacy V2 and credits fixtures (providers 11)
- **When** the tests run
- **Then** lines, headline, peak-hours metadata, forecasts (providers 21), and the retry gate are unchanged
- **And** the new strings exist in every shipped locale.

## Plan

1. [x] Add fixtures to `Tests/ZAIProviderTests/Fixtures/`:
   - `quota-no-plan.json`: the live body, verbatim.
   - `quota-auth-1000.json` and `quota-auth-1001.json`: the live bodies.
   - `quota-auth-401.json`: the fixture body.
   - `quota-empty-limits.json`: the Team body from issue #36, with the `msg` noted in Evidence.
   Their sources go in this spec, not in the test code.
2. [x] Add an envelope wire type with optional `code`, `msg`, `success`, and `data`. Decode it first, then decide success or failure (AC1).
3. [x] Add `ZAIError.noCodingPlan` and `ZAIError.business(Int)` with their messages, and map the auth codes to the existing authentication message.
4. [x] Skip `subscription/list` when the quota call fails.
5. [x] Add the "No usage windows reported" headline.
6. [x] Rename `providerName` to "z.ai Coding Plan" and update the description, `README.md`, `SETUP.md`, `site/index.html`, and the stale code comment about plan-agnostic endpoints. Update the z.ai API disclaimer and its translations, and the provider name in the `SETUP.md` z.ai API section.
7. [x] Seed the new strings in every shipped locale.
8. [x] Tests: each fixture, both auth paths, the unknown business code, the error-log content, and AC7's regression set.
9. [x] Finding behind AC6: the site groups providers by brand. The Kimi tile covers Kimi API and Kimi Code, and the z.ai tile already reads "GLM Coding Plan & Pay-as-you-go balance" (providers 25). The site does not give key guidance for any provider, so `site/index.html` is unchanged and the key guidance lives in `SETUP.md`.

## Out of scope

- Team Plan keys. Reading them needs `?type=2` and organization and project headers, which Filbert does not have. Today they get the no-plan message, which is accurate for the personal endpoint.
- Detecting the key type from a response. Nothing in the evidence exposes it.
- Pay-as-you-go balance (providers 25).

## Risks

- **Message matching.** The no-plan rule depends on `coding plan` appearing in `msg`. If z.ai rewords it, the user sees the generic error again, which is today's behavior and no worse.
- **Code 500 reused.** Another failure with code `500` and that phrase would also read as no plan. No such case is known.
- **Team users.** A Team Plan user sees "no active GLM Coding Plan" even though they pay for one. The message is accurate for the endpoint Filbert calls, but it may cause confusion until Team support has its own spec.
