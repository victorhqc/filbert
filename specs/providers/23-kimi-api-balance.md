## Objective

Add a `KimiAPIProvider` that reads a Kimi Open Platform (Moonshot) pay-as-you-go account's prepaid balance with an API key.

## Context

- Status: implemented on 2026-10-23, uncommitted. The native review of the new translations is still open. Kimi Code subscriptions are a separate product with separate keys and get their own provider (providers 24).
- `Sources/Providers/KimiAPI/` — new provider module: request, decoding, mapping, and errors. Mirrors the DeepSeek provider (providers 04), the closest existing shape.
- `Sources/Providers/KimiAPI/Resources/Localizable.xcstrings` — provider labels, setup text, and errors in every locale the app ships.
- `Sources/Providers/KimiAPI/Resources/ProviderGlyph.png` and `ProviderGlyph@2x.png` — license-safe monochrome Kimi glyph (ui 14 AC1).
- `Sources/Core/` — unchanged. `UsageBalance` with a `.currency` unit already covers prepaid balances (core 13).
- `Package.swift` and `Sources/App/AppMain.swift` — gain a `KimiAPIProvider` target, a test target, and one registration line (core 02 AC7, ui 02 AC9).
- `README.md` — lists the provider, where to create a key, and the China base URL.
- Moonshot moved its docs from `platform.moonshot.ai` to `platform.kimi.ai` (international) and `platform.kimi.com` (China). The API hosts did not change.
- Public contract, as documented on 2026-10-23 ([international](https://platform.kimi.ai/docs/api/balance), [China](https://platform.kimi.com/docs/api/balance)):
  - `GET https://api.moonshot.ai/v1/users/me/balance` (international, USD) and `GET https://api.moonshot.cn/v1/users/me/balance` (China, CNY).
  - Auth: `Authorization: Bearer <apiKey>`. Keys are per platform. A key sent to the other platform's host gets `401`.
  - Response:
    ```json
    {"code": 0, "data": {"available_balance": 49.58894, "voucher_balance": 46.58893, "cash_balance": 3.00001}, "scode": "0x0", "status": true}
    ```
  - `available_balance` = cash + vouchers. At 0 or below, inference fails with `exceeded_current_quota_error`.
  - `voucher_balance` is never negative. `cash_balance` can be negative (money owed); then `available_balance` equals `voucher_balance`.
  - Amounts are JSON numbers with up to five decimals in the example. The response names no currency.
  - Documented errors: `401` and `500`. No usage or spend-history endpoint exists.
- CodexBar's `docs/moonshot.md` reads the same endpoint and hosts. It is second-party corroboration, not a live capture.

## Evidence

Live capture by the user on 2026-10-23, with an international key from `platform.kimi.ai`. Account and trace identifiers are left out.

- `GET https://api.moonshot.ai/v1/users/me/balance` with the key gives HTTP `200`, `content-type: application/json; charset=utf-8`:
  ```json
  {"code":0,"data":{"available_balance":10,"voucher_balance":5,"cash_balance":5},"scode":"0x0","status":true}
  ```
  Whole amounts are bare integers. `available_balance` = cash + vouchers holds. Ten reads over five minutes returned the same body.
- The same key on `https://api.moonshot.cn` gives HTTP `401`:
  ```json
  {"error":{"message":"Invalid Authentication","type":"invalid_authentication_error"}}
  ```
- An invalid key on `https://api.moonshot.ai` gives the same `401` body. A key for the wrong region and a bad key cannot be told apart.
- Error bodies use this OpenAI-style `error` object, not the `code`/`status` envelope.
- No rate-limit or `Retry-After` headers appear on success or on `401`.
- Charge timing, for the forecasting follow-up:
  - One `kimi-k2.6` request (14 tokens) at about 11:39:16 cost 0.000019.
  - The balance read `10` until 11:40:48 and read `9.999981` from 11:41:18, so the charge showed up 1.5–2 minutes later, in one step:
    ```json
    {"code":0,"data":{"available_balance":9.999981,"voucher_balance":4.9999905,"cash_balance":4.9999905},"scode":"0x0","status":true}
    ```
  - Amounts carry at least seven decimals.
  - The charge came off vouchers and cash in equal halves, not vouchers first.

## Acceptance Criteria

### AC1: Authenticated request to the balance endpoint

- **Given** a non-empty API key
- **When** `fetchQuota(auth:baseURL:)` runs
- **Then** it sends `GET <baseURL>/v1/users/me/balance` with `Authorization: Bearer <apiKey>` and `Accept: application/json`
- **And** `<baseURL>` defaults to `https://api.moonshot.ai` and follows the user's override (core 02 AC2)
- **And** `authShape` is `.apiKey`.

### AC2: The currency follows the host

- **Given** a successful response
- **When** the provider picks the currency
- **Then** a host of `api.moonshot.cn` gives `CNY`
- **And** any other host gives `USD`.

### AC3: Balance maps to currency lines

- **Given** a `200` response with `code == 0` and `status == true`
- **When** the provider maps it
- **Then** `available_balance` becomes the "Available balance" line, with stable ID `available-balance`
- **And** `voucher_balance` and `cash_balance` become the "Voucher balance" and "Cash balance" lines, with IDs `voucher-balance` and `cash-balance`, only when they are non-zero and differ from the available balance. The labels use the vendor's names: "available, voucher, and cash balances" in the English docs, and 可用余额, 代金券余额, 现金余额 in the Chinese docs.
- **And** a negative cash balance is shown as a negative amount, not hidden
- **And** amounts are decoded as `Decimal` without a round trip through `Double`.

### AC4: Headline shows what is left

- **Given** a mapped balance
- **When** the headline is built
- **Then** it reads `"<amount> left"`, formatted in the display language's currency style
- **And** `headlineUsageLineId` is `available-balance`
- **And** an available balance of 0 or below reads "No balance available", with the lines still shown.

### AC5: Failures surface as errors, never fake data

- **Given** an empty key, a non-`200` status, a body with `code != 0` or `status == false`, a network failure, or an undecodable body
- **When** `fetchQuota` runs
- **Then** it throws a typed `KimiAPIError` and returns no placeholder quota
- **And** `401` reads "Authentication failed. Check your API key. Keys from platform.kimi.com need the base URL https://api.moonshot.cn."
- **And** `429` reads "Rate limited. Try again later." and records any `Retry-After` in the provider's retry gate, as the z.ai provider does.

### AC6: Setup points to the right console

- **Given** the provider has no key
- **When** Settings or the README shows it
- **Then** the description reads "Monitor prepaid balance"
- **And** the README links the API key pages on `platform.kimi.ai` and `platform.kimi.com`, and gives the China base URL.

Finding, 2026-10-23: the API-key settings row (`ProviderSettingsRow` in `Sources/App/ProviderSetupCard.swift`) does not render `setupHelp`. Only `APIKeyFreeSettingsRow` does. A setup link for API-key providers needs its own `ui` spec, so this provider sets no `setupHelp`. The `401` message carries the region hint inside the app.

### AC7: Strings are localized

- **Given** any shipped display language
- **When** labels, the headline, setup text, or errors are produced
- **Then** they resolve through the module's String Catalog. No English literal reaches `ProviderQuota`.

### AC8: Activity detection uses the available balance only

- **Given** a mapped response
- **When** the provider builds its activity observation
- **Then** only `available-balance` is a `.credits` metric, and the observation is `.fresh`
- **And** it carries no forecast descriptor. Forecasting needs a captured resolution and charge delay first (Out of scope).

### AC9: The package builds clean

- **Given** a fresh checkout after the change
- **When** `swift build` and `swift test` run
- **Then** both pass with zero warnings, and `KimiAPIProvider` depends only on `Core`.

## Plan

1. [x] Capture one live response with a real key, outside the repository. Done on 2026-10-23 (Evidence). Amounts are JSON numbers, whole amounts have no decimals, and errors use an `error` object instead of `code`/`status`. How fast a charge reaches the balance is left to the forecasting follow-up.
2. [x] Add the `KimiAPIProvider` target, the test target, the App dependency, and the registration line. The module also joins the catalog coverage list in `Tests/AppTests/StringCatalogCoverageTests.swift`.
3. [x] Add the private wire types (`code`, `status`, `data`) and `KimiAPIError`. Decode amounts as `Decimal`. `scode` is not decoded, because nothing reads it. `JSONDecoder` keeps every captured decimal exactly, e.g. `4.9999905`. A test pins this.
4. [x] Implement `fetchQuota`, the host-to-currency rule, the mapping, the headline, and the retry gate.
5. [x] Seed the String Catalog in every shipped locale, and add the glyph.
   - Shared strings reuse the DeepSeek translations.
   - Portuguese "%@ left" follows the glossary rule "Saldo restante: %@". DeepSeek still uses "Restante: %@".
   - New terms are recorded in `docs/localization-glossary.md`. Only the zh-Hans balance terms have a vendor source; the rest keep ⚠︎ until a native review.
   - The glyph is Simple Icons' `kimi.svg` (CC0), pinned in `scripts/provider-glyphs/README.md` and rendered by `scripts/generate-provider-glyphs.swift`.
6. [x] Tests: request shape, both hosts' currency, the live capture as a fixture, integer and fractional amounts, line selection, negative cash, zero balance, `code != 0`, the live `401` body, `429`/`500`, and undecodable bodies. Fixtures in `Tests/KimiAPIProviderTests/Fixtures/` keep the live bodies verbatim: `balance-live-whole.json` (before the charge), `balance-live-after-charge.json`, and `unauthorized-live.json`.
7. [x] Update `README.md`. `SETUP.md` also gains a Kimi API section with both key pages and the China base URL, as AC6 asks.

## Out of scope

- Balance forecasting. A follow-up spec opts `available-balance` in, as (providers 19) did for DeepSeek, once a capture shows the resolution and how fast a charge reaches the balance.
- Spend history. The API has none.
- Kimi Code subscription usage (providers 24).

## Risks

- **Currency from a proxy.** A proxy in front of the China host reports `USD`. Accepted for v1. A later spec can add an explicit region if users hit it.
- **China keys on the default host.** They fail with `401` until the user sets the base URL. The error text names the fix.
- **Five-decimal amounts.** Formatting rounds to the currency's minor unit. A balance of 0.004 shows as 0.00 while still positive.
