## Objective

Add a `ZAIAPIProvider` that reads a z.ai or BigModel pay-as-you-go account's prepaid balance with a Standard API key.

## Context

- Status: implemented 2026-10-23, merged in #102. The user approved the spec that day, after a live capture from their z.ai account. This is a separate product from the GLM Coding Plan, which the z.ai Coding Plan provider tracks (providers 01, providers 11, providers 26). (providers 26) renamed that provider, so the disclaimer in AC7 now names "the z.ai Coding Plan provider".
- `Sources/Providers/ZAIAPI/` — new provider module: request, envelope handling, decoding, mapping, and errors. Follows the DeepSeek balance provider (providers 04). It shares no code with `Sources/Providers/ZAI/`.
- `Sources/Providers/ZAIAPI/Resources/Localizable.xcstrings` — provider labels, setup text, and errors in every locale the app ships.
- `Sources/Providers/ZAIAPI/Resources/ProviderGlyph.png` and `ProviderGlyph@2x.png` — the z.ai glyph, copied into this module (ui 14 AC1).
- `Sources/Core/` — unchanged. `UsageBalance` with a `.currency` unit covers the balance (core 13).
- `Package.swift` and `Sources/App/AppMain.swift` — gain a `ZAIAPIProvider` target, a test target, and one registration line (core 02 AC7, ui 02 AC9).
- `README.md` — lists the provider and explains Standard vs Coding Plan keys.
- Since 2026-10-16, z.ai issues separate keys. A Standard key bills the account balance or usage bundles, never Coding Plan quota. Existing keys became Compatible, Standard, or Team Plan keys ([API key management](https://docs.z.ai/devpack/notice/api-key-management)).
- The balance endpoint is undocumented. The documented `GET /api/paas/v4/users/me/balance` returns HTTP `404` (live, 2026-10-23).

## Evidence

### Live, z.ai (2026-10-23)

A z.ai account that held only a 3 USD top-up, read with its API key. Each body below is verbatim.

- Endpoint: `GET {host}/api/biz/account/query-customer-account-report`. `api.z.ai` serves it. The key works both raw and with `Bearer` in `Authorization`, and both return the same body.
- After the top-up, before any call:
  ```json
  {"code":200,"msg":"Operation successful","data":{"balance":3.000000000,"rechargeAmount":3.000000,"giveAmount":0.000000,"totalSpendAmount":0E-9,"todaySpendAmount":null,"availableBalance":3.000000000,"frozenBalance":0E-9,"creditBalance":null,"availableCreditBalance":null,"creditStatus":"NOT_OPEN","modelSpendAmountList":null,"isKA":false},"success":true}
  ```
- After one `glm-4.5-air` chat call at 11:30:53 UTC, read at 11:32:15 UTC:
  ```json
  {"code":200,"msg":"Operation successful","data":{"balance":2.999994150,"rechargeAmount":3.000000,"giveAmount":0.000000,"totalSpendAmount":0.000005850,"todaySpendAmount":null,"availableBalance":2.999994150,"frozenBalance":0E-9,"creditBalance":null,"availableCreditBalance":null,"creditStatus":"NOT_OPEN","modelSpendAmountList":null,"isKA":false},"success":true}
  ```
- The charge is in USD. The call used 1 uncached input token, 5 cached input tokens, and 5 output tokens. At the list prices of $0.20, $0.03, and $1.10 per million tokens ([pricing](https://docs.z.ai/guides/overview/pricing)), that is $0.00000585, which matches `totalSpendAmount` exactly.
- Each call is billed on its own, at nine decimal places, and the charge appears in under 82 seconds.
- The same key on `open.bigmodel.cn` returns the same account, with `msg` reading `操作成功`. So the host does not identify the account's platform. `msg` follows the host and ignores `Accept-Language`.
- Failures come back as HTTP `200` envelopes:
  - Bad key: `{"code":401,"msg":"token expired or incorrect","success":false}`
  - No `Authorization` header: `{"code":1001,"msg":"Authentication parameter not received in Header, unable to authenticate","success":false}`
  - Unknown `/api/biz/` route: `{"code":404,"msg":"接口不存在: /account/does-not-exist","data":null,"success":false}`

### Public sources

- **China, live capture** (cc-switch `src-tauri/src/services/balance.rs`, `ZHIPU_BALANCE_BODY`, a pay-as-you-go key on `open.bigmodel.cn`, 2026-10-18):
  ```json
  {"code":200,"msg":"操作成功","data":{"balance":14.68002004,"rechargeAmount":15.0,"giveAmount":0.0,"totalSpendAmount":0.31997996,"todaySpendAmount":null,"availableBalance":14.68002004,"frozenBalance":0.0,"creditBalance":null,"availableCreditBalance":null,"creditStatus":"NOT_OPEN","modelSpendAmountList":null,"isKA":false},"success":true}
  ```
- **Global, empty account** (tidemark `crates/tidemark-core/src/providers/keyed/zai.rs`, recorded 2026-09-02 against `api.z.ai`, amounts invented):
  ```json
  {"code":200,"msg":"Operation successful","data":{"balance":0E-9,"rechargeAmount":0.000000,"giveAmount":0.000000,"totalSpendAmount":0E-9,"todaySpendAmount":null,"availableBalance":0E-9,"frozenBalance":0E-9,"creditBalance":null,"availableCreditBalance":null,"creditStatus":"NOT_OPEN","modelSpendAmountList":null,"isKA":false},"success":true}
  ```
- A bad key on BigModel returns `{"code":401,"msg":"令牌已过期或验证不正确","success":false}` (cc-switch fixture, TokenLedger). z.ai monitor routes use `1000` and `1001` for authentication failures (view-limits PR #28, live).

### Semantics

- `balance = rechargeAmount + giveAmount − totalSpendAmount`. This holds exactly in every capture, live and public.
- `availableBalance = balance − frozenBalance`. This comes from client code, and every capture has a frozen balance of 0.
- `rechargeAmount`, `giveAmount`, and `totalSpendAmount` are lifetime totals.
- Amounts are bare JSON numbers in major units, with six or nine decimal places. Zero may be written `0E-9`.
- The credit fields, `todaySpendAmount`, and `modelSpendAmountList` are null in every capture.
- There is no currency field. CNY on BigModel comes from the cc-switch capture, and USD on z.ai comes from the live capture.
- The app formats currency to two decimals, so a spend below half a cent would read `$0.00`. AC4 hides the spend line until it reaches one cent.

### Gaps

- No capture for a Coding Plan key, so we do not know what this endpoint returns for one.
- No capture for a BigModel key on `api.z.ai`.
- No non-zero `frozenBalance`, non-null `modelSpendAmountList`, or credit status other than `NOT_OPEN`.

## Acceptance Criteria

### AC1: Authenticated request to the balance report

- **Given** a non-empty API key
- **When** `fetchQuota(auth:baseURL:)` runs
- **Then** it sends `GET <baseURL>/api/biz/account/query-customer-account-report` with the raw key in `Authorization` and `Accept: application/json`
- **And** `<baseURL>` defaults to `https://api.z.ai` and follows the user's override, e.g. `https://open.bigmodel.cn` (core 02 AC2)
- **And** `authShape` is `.apiKey`.

### AC2: The envelope decides success

- **Given** an HTTP `200`
- **When** the provider reads the body
- **Then** only `success == true` with `code == 200` and a `data` object is a success
- **And** business codes `401`, `1000`, `1001`, and `1002` throw the authentication error
- **And** any other envelope throws "z.ai did not return a balance for this key.", and the error log records only the business code.

### AC3: The currency follows the host

- **Given** a successful response
- **When** the provider picks the currency
- **Then** a host ending in `bigmodel.cn` gives `CNY`
- **And** any other host gives `USD`.

Both hosts serve every account (Evidence), so the base URL is the only currency signal. Settings tells BigModel users to set it (AC7).

### AC4: The balance maps to currency lines

- **Given** a successful response
- **When** the provider maps it
- **Then** `availableBalance`, or `balance` when that is null, becomes the "Available balance" line, with ID `available-balance`
- **And** a non-zero `frozenBalance` becomes the "Frozen" line, with ID `frozen-balance`
- **And** `totalSpendAmount` becomes the "Spent to date" line, with ID `total-spend`, once it reaches 0.01, so a fraction of a cent is never shown as `$0.00`
- **And** amounts, including `0E-9`, `0.000000`, and `0.000005850`, decode as `Decimal` without losing digits, and null fields are tolerated
- **And** the credit fields, `todaySpendAmount`, `modelSpendAmountList`, `isKA`, `rechargeAmount`, and `giveAmount` are not shown.

### AC5: Headline shows what is left

- **Given** a mapped balance
- **When** the headline is built
- **Then** it reads `"<amount> left"` in the display language's currency style, with `headlineUsageLineId` set to `available-balance`
- **And** a balance of 0 or below reads "No balance available", and the lines are still shown
- **And** a missing balance reads "No data".

### AC6: Transport failures surface as errors

- **Given** an empty key, a non-`200` HTTP status, a network failure, or an undecodable body
- **When** `fetchQuota` runs
- **Then** it throws a typed `ZAIAPIError` and returns no placeholder quota
- **And** HTTP `429` reads "Rate limited. Try again later." and records any `Retry-After` in the provider's retry gate.

### AC7: Settings explains the key and the host

- **Given** the provider is listed in Settings
- **When** its card is shown
- **Then** the description reads "Monitor pay-as-you-go balance"
- **And** the provider disclaimer reads "Use a Standard API key. Coding Plan usage is shown by the z.ai provider. For BigModel (bigmodel.cn) accounts, set the base URL to https://open.bigmodel.cn."
- **And** `SETUP.md` links z.ai's API key page
- **And** the authentication error adds: "Keys from bigmodel.cn need the base URL https://open.bigmodel.cn."

### AC8: Activity detection follows spend

- **Given** a mapped response
- **When** the provider builds its activity observation
- **Then** `total-spend` is the only `.usage` metric, so top-ups and grants never read as activity, and the observation is `.fresh`
- **And** the metric is present even while the spend line is hidden, so a spend change below one cent still counts as a change
- **And** no metric carries a forecast descriptor (Out of scope).

### AC9: Strings are localized and the package builds clean

- **Given** a fresh checkout after the change
- **When** `swift build` and `swift test` run under any shipped display language
- **Then** every label, headline, setup text, and error resolves through the module's String Catalog
- **And** both commands pass with zero warnings, and `ZAIAPIProvider` depends only on `Core`.

## Plan

1. [x] Add the `ZAIAPIProvider` target, the test target, the App dependency, and the registration line.
2. [x] Add fixtures under `Tests/ZAIAPIProviderTests/Fixtures/`. The live and public ones are kept verbatim:

   | Fixture | Source |
   |---|---|
   | `balance-global-topup.json` | live z.ai, after the top-up |
   | `balance-global-spend.json` | live z.ai, after one call |
   | `balance-cn-live.json` | cc-switch |
   | `balance-global-empty.json` | tidemark |
   | `envelope-bad-key.json` | live z.ai, bad key |
   | `envelope-missing-key.json` | live z.ai, no header |
   | `envelope-unknown-route.json` | live z.ai, unknown route |

   The frozen balance and the null `availableBalance` cases are written inline in the tests.
3. [x] Add the envelope and data wire types and `ZAIAPIError`. The wire types are module-internal, as in (providers 23), so the tests can reach the mapping.
4. [x] Implement `fetchQuota`, the envelope rules, the host-to-currency rule, the mapping, the headline, and the retry gate.
5. [x] Seed the String Catalog in every shipped locale, and copy the glyph. Shared strings reuse the translations in (providers 23). The new terms (pay-as-you-go, frozen, spent to date, Standard key) are in `docs/localization-glossary.md`, all marked ⚠︎ until a native review.
6. [x] Tests: request shape, both currencies, every fixture, line selection, the `balance` fallback, zero and negative balances, a sub-cent spend, every envelope code, and HTTP `429`/`500`.
7. [x] Update `README.md` and `SETUP.md`. `SETUP.md` links the z.ai and BigModel API key pages. The site's z.ai tile now reads "GLM Coding Plan & Pay-as-you-go balance", as Kimi's single tile does.
8. [x] Finding behind AC7: Settings renders `setupHelp` only for providers without an API key, so the key and host guidance is the provider disclaimer, which every setup card shows. The API key link lives in `SETUP.md`.

## Out of scope

- Balance forecasting. Charges post per call within about a minute (Evidence). A follow-up spec opts `available-balance` in.
- Usage bundles (resource packs). Their endpoint has a single unverified mention.
- Per-model spend. `modelSpendAmountList` has never been seen non-null.
- Team Plan keys. They follow seat rules, not a balance.

## Risks

- **The host decides the currency, but not the account.** A BigModel user who keeps the default host sees CNY amounts labelled USD, if their key works on `api.z.ai`. The setup help tells them to set the base URL.
- **Coding Plan keys are untested.** If the endpoint returns the account balance for them too, the provider still works, and the "Standard key" wording is stricter than it needs to be.
- **Undocumented endpoint.** z.ai can close it to API keys, as it did for other `/api/biz/` routes. The provider then fails, and it never shows a zero balance.
- **Proxies.** A proxy in front of BigModel reports `USD`. Accepted for v1.
