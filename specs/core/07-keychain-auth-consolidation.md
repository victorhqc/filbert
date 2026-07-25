## Objective

Consolidate all Keychain authentication through one session-scoped context and one public Core accessor so providers stop reinventing SecItem/LAContext code and users see the macOS-allowed minimum of password prompts.

## Context

- `Sources/Core/Keychain.swift` — allocates a fresh `KeychainAuthenticationContext` per public call (L67, L87, L121) and performs a verification read after every write (L166-201, `replaceAndVerify`); both multiply prompts.
- `Sources/Core/KeychainStorage.swift` — defines `KeychainAuthenticationContext` and the `KeychainStorage` / `SecurityKeychainStorage` pair as `internal`, so providers cannot reuse them across the SwiftPM module boundary.
- `Sources/Providers/Cursor/CursorTokenStore.swift` — duplicates `KeychainAuthenticationContext` as `CursorKeychainAuthenticationContext` (L6-8) and reimplements the SecItem read query (L258-287) precisely because the Core types are not visible.
- `Sources/Providers/Cursor/CursorCredentialVault.swift` — writes Cursor credentials into Filbert's consolidated item via `Keychain`, inheriting the verification-read prompt cost on every save.
- The existing `Keychain.lock` (`Keychain.swift` L39, `NSLock`) already serializes every in-process access to the consolidated item, which is the sole writer to `filbert` / `providers`. Concurrency integrity therefore does not depend on the verification read.
- Builds on the consolidated-item design from (core 04) and the operation-scoped context from (core 05 AC3); supersedes the post-write verification requirement in (core 04 AC2, AC3) and the verification inheritance in (core 05 AC2).

## Acceptance Criteria

### AC1: One authentication context per app session

- **Given** Filbert is running
- **When** any combination of Keychain reads, writes, deletes, migrations, or provider imports happens during the session
- **Then** all `SecItem*` calls route through one shared `LAContext` owned by Core
- **And** that context is created lazily on first Keychain use and reused for every subsequent operation in the session
- **And** a successful authorization on one read is reused for the session's subsequent permitted reads, per macOS's `LAContext` reuse rules
- **And** no public Keychain entry point, helper, or provider import path allocates its own `LAContext` or `KeychainAuthenticationContext`

### AC2: Post-write verification is removed

- **Given** Core writes the consolidated item during a save, delete, or migration
- **When** `SecItemUpdate` or `SecItemAdd` returns `errSecSuccess`
- **Then** Core trusts the Security framework status and performs no read-back
- **And** the `replaceAndVerify`, `restore`, and `cachedData` machinery is deleted from `Keychain`
- **And** a failed `SecItemUpdate` or `SecItemAdd` still returns a typed `KeychainError` and leaves the in-memory cache unchanged
- **And** the existing `Keychain.lock` remains the sole integrity guarantee against concurrent in-process access

### AC3: A public Core accessor exposes generic Keychain item operations

- **Given** a provider needs to read or write a Keychain item that is not Filbert's consolidated item
- **When** it performs that external access
- **Then** it calls a public Core type that wraps `SecItemCopyMatching`, `SecItemUpdate`, `SecItemAdd`, and `SecItemDelete` with the shared authentication context
- **And** Core exposes this accessor, the shared context type, and the storage protocol as `public` so they cross SwiftPM module boundaries
- **And** `Keychain` uses this accessor internally for its own consolidated-item reads and writes
- **And** no provider module defines its own `LAContext` wrapper, SecItem query builder, or authentication-context type

### AC4: Cursor uses the shared accessor and drops its duplicates

- **Given** the public Core accessor exists
- **When** the Cursor provider reads external credentials during bootstrap or re-import
- **Then** `CursorKeychainAuthenticationContext` and `CursorTokenStore.defaultReadKeychain` are deleted
- **And** `CursorTokenStore.loadExternalPair` calls the shared Core accessor with the session-scoped context
- **And** Cursor's external reads still distinguish absence (`errSecItemNotFound`) from authentication failure and surface the existing typed errors (core 05 AC4)
- **And** the Cursor provider module depends only on Core, with no new cross-module coupling

### AC5: The shared context is invalidated on system sleep and lock

- **Given** the shared `LAContext` has been used during the session
- **When** the system sleeps, wakes, or the user session locks
- **Then** Core invalidates the `LAContext` and creates a fresh one on the next Keychain access
- **And** a re-prompt may occur after wake or lock, because macOS requires re-authorization after biometric or session state changes
- **And** the consolidated item's in-memory cache survives invalidation, so a re-prompt happens only when the cache is cold

### AC6: Tests and a smoke test cover the consolidation

- **Given** the implementation is complete
- **When** the Core and Cursor test suites run
- **Then** Core tests prove the shared context is reused across multiple operations in one session, the accessor types are public, `replaceAndVerify` and `cachedData` no longer exist, and a failed write still returns a typed error without changing the cache
- **And** Cursor tests prove external reads use the shared Core accessor, `CursorKeychainAuthenticationContext` is gone, the absence-versus-denial distinction is preserved, and concurrent initial loads still share one external read
- **And** a documented macOS Keychain smoke-test checklist records the prompt count for a first Cursor import, a subsequent Cursor refresh, and a Z.ai or DeepSeek API-key save, confirming the new counts match the macOS-allowed minimum
- **And** `swift build` and the full `swift test` suite pass with no warnings

## Plan

1. Promote `KeychainAuthenticationContext`, `KeychainStorage`, `SecurityKeychainStorage`, and `KeychainStorageError` to `public` in Core. Add a shared, session-scoped `KeychainAuthenticationContext` (static `shared` or a small provider type) that `Keychain` and external callers both use.
2. Wire `NSWorkspace` sleep/wake and Distributed Notification lock/unlock observers to invalidate and recreate the underlying `LAContext`.
3. Remove `replaceAndVerify`, `restore`, and `cachedData` from `Keychain`. Have `mutateStore` call the storage's `replaceData` directly and trust the framework status; keep the `NSLock`.
4. Delete `CursorKeychainAuthenticationContext` and `CursorTokenStore.defaultReadKeychain`. Route `CursorTokenStore.loadExternalPair` through the public Core accessor with the shared context.
5. Extend Core and Cursor tests per AC6, and record the macOS smoke-test checklist in the spec file for completion before release.

No production code is written until this spec is reviewed.

## Risks

- **Removing verification loses silent-corruption detection.** Accepted trade-off: the consolidated item is only written by Filbert and serialized by `Keychain.lock`, so the realistic failure modes collapse to Security framework bugs. (core 04 AC2, core 04 AC3, core 05 AC2) explicitly required verification and read-back; this spec supersedes those clauses, and the reviewer should sign off on the lost safety net.
- **Per-item prompts remain an macOS limit.** macOS scopes authorization to the keychain item, not the context, so Cursor's external items (`cursor-access-token`, `cursor-refresh-token`) and Filbert's consolidated item each prompt independently on first access. The dual "access key" plus "confidential information" prompts per external item are macOS showing two authorization stages for items Filbert is not on the ACL for; not fixable from code without a signed release build and an ACL grant.
- **Shared `LAContext` can suppress a legitimate re-prompt if held too long.** Mitigated by invalidating on sleep, wake, and lock (AC5). The context is never a credential cache — it only batches authorization within its valid window.
- **Public Core surface area grows.** Promoting internal types to public is a one-way door; future signature changes to the accessor become breaking. The spec keeps the surface minimal: read, write, and delete for generic password items, plus the shared context.
- **macOS smoke test was skipped for (core 05).** Plan item 7 of (core 05) is still open. AC6 here re-asserts it; the prompt counts cannot be trusted until a real keychain is exercised.

## macOS Keychain smoke-test checklist

Run on a real Mac before release. CI cannot exercise this — the real
Keychain is the only source of truth for prompt counts. Record the observed
prompt count after each step; it must match the macOS-allowed minimum.

### Setup

- [ ] Fresh macOS user account, or one where Filbert's consolidated item
      (`filbert` / `providers`) and Cursor's external items
      (`cursor-access-token`, `cursor-refresh-token`) have never been
      authorized for Filbert.
- [ ] Cursor Agent CLI signed in (`agent login`) so both external items
      exist in the login keychain.
- [ ] Filbert built and signed. Ad-hoc signatures may yield more prompts
      than a stable developer-ID signature; record which was used.
- [ ] Confirm `swift build -c release` and `swift test` pass on the revision
      under test before starting.

### Steps (append observed prompt count after each)

- [ ] **1. First Cursor import.** Launch Filbert, then trigger the Cursor
      "Import from Cursor" action.
      Expected: one prompt per external item (`cursor-access-token`,
      `cursor-refresh-token`) for the read, plus one prompt for the
      consolidated item write. No read-back prompt on the write.
      Observed prompts: ___
- [ ] **2. Cursor refresh.** Restart Filbert with Cursor already configured
      and trigger a refresh, or wait for the 5-minute auto-refresh.
      Expected: 0 prompts. The consolidated item is already authorized and
      the cache is warm; external items are not re-read on refresh.
      Observed prompts: ___
- [ ] **3. Z.ai or DeepSeek API-key save.** With the consolidated item
      already authorized from step 1, save a new API key.
      Expected: 0 prompts. The write trusts the Security framework status;
      no read-back.
      Observed prompts: ___
- [ ] **4. Sleep / wake re-authorization.** Put the system to sleep, wake
      it, then trigger any Keychain read (e.g. refresh).
      Expected: one prompt. The session-scoped `LAContext` is invalidated
      on wake (AC5), so macOS re-authorizes the next access. The
      in-memory cache survives; only the authorization state resets.
      Observed prompts: ___
- [ ] **5. Session lock / unlock.** Lock the session, unlock, then trigger
      any Keychain read.
      Expected: one prompt, for the same reason as step 4.
      Observed prompts: ___

If any observed count exceeds the expected minimum, file a bug and do not
release. Lower-than-expected counts are also worth investigating — they
usually indicate a stale grant from a prior test run, not a real reduction.

### Pre-release sign-off

- [ ] All steps above show observed counts matching the expected minimum.
- [ ] No new `LAContext`, `SecItem` query builder, or authentication-context
      type exists outside Core (grep `Sources/Providers`).
- [ ] The checklist is attached to the release notes for this version.
