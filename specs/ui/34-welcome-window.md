## Objective

On the first launch, show a Welcome window that introduces Filbert, lets the user choose a language and set up a provider, and shows that Filbert lives in the menu bar.

## Context

- Problem: a new user launches Filbert and sees nothing but a small icon in the menu bar. Some users do not find it. When the menu bar is full, or the notch covers it, the icon is not visible at all.
- `Sources/App/AppMain.swift` — owns the scenes and the app-lifetime state. It creates the Welcome window controller. `AppDelegate` handles a reopen of the app.
- `Sources/App/SettingsWindowActivation.swift` — `SettingsWindowLookup` returns the first titled window that is not a panel. A second titled window breaks this. The lookup must skip the Welcome window.
- `Sources/App/SettingsView.swift` — `ProviderSettingsRow` is private. The Welcome window must use the same setup row, so the provider card moves to a shared view.
- `Sources/App/GeneralSettingsView.swift` — the language picker (ui 32) and the Launch at login toggle (ui 26) move to shared views, so the Welcome window and Settings use the same controls.
- `Sources/App/QuotaView.swift` — the popover's empty state stays as it is. It is the fallback when the user skips the provider step.
- `Sources/Core/ProviderEnablement.swift` — writes `provider-enablement` to `UserDefaults` the first time the app reads the providers. An existing install already has this key, so it tells a new user from a user who updates.
- `Sources/App/Resources/Localizable.xcstrings` — the new text, in all languages (ui 31), with terms from `docs/localization-glossary.md`.
- The language switch rebuilds the view tree (ui 32 Plan step 4). The current step must live above `DisplayLanguageRoot`, like the Settings tab.
- `Package.swift` requires macOS 14. `.defaultLaunchBehavior` needs macOS 15, so the app opens the window itself (Plan step 5).
- Builds on (ui 01, ui 02, ui 17, ui 32). The Welcome window adds no provider-specific code. It reads `ProviderInfo` from the registry, as Settings does.

## Acceptance Criteria

### AC1: A new user sees the Welcome window

- **Given** a fresh install, with no `provider-enablement` value and no Welcome completion value in `UserDefaults`
- **When** Filbert launches
- **Then** the Welcome window opens in front of other apps, at the center of the main screen
- **And** the menu bar item is also present.

### AC2: An existing user does not see it

- **Given** an install that has a saved `provider-enablement` value, or a saved Welcome completion value
- **When** Filbert launches
- **Then** the Welcome window does not open.

### AC3: The first step introduces Filbert and its language

- **Given** the Welcome window is open
- **When** the first step shows
- **Then** it shows the Filbert icon, the name, and one sentence about what Filbert does
- **And** it shows the language picker from Settings (ui 32 AC1)
- **And** the steps are numbered, for example "1 of 3".

### AC4: A language change applies at once and keeps the step

- **Given** the Welcome window is on any step
- **When** the user selects a language
- **Then** all text in the Welcome window, the popover, and Settings changes to that language at once (ui 32 AC3)
- **And** the Welcome window stays on the same step.

### AC5: The second step sets up a provider

- **Given** the user goes to the second step
- **When** the step shows
- **Then** it lists every registered provider in the Settings order, each with its glyph, name, and description
- **And** when the user selects a provider, the step shows the same setup controls as that provider's card in Settings: the API key field, or the helper install and credential import actions
- **And** a provider that the user sets up here is enabled, and its state shows on the card, as in Settings.

### AC6: The user can skip the provider step

- **Given** the second step, with no provider set up
- **When** the user selects "Skip for now"
- **Then** the window goes to the third step
- **And** the popover later shows its empty state with "Open Settings".

### AC7: The third step shows where Filbert lives

- **Given** the user goes to the third step
- **When** the step shows
- **Then** it shows a picture of a menu bar with Filbert's icon marked, and the text "Filbert lives in your menu bar. Click its icon to see your usage."
- **And** it says that Filbert has no Dock icon and no main window
- **And** it shows the Launch at login toggle from Settings (ui 26 AC1), off by default (ui 26 AC2).

### AC7a: The toggle works as in Settings

- **Given** the third step
- **When** the user changes the Launch at login toggle
- **Then** Filbert registers or unregisters the login item, as in Settings (ui 26 AC3)
- **And** the General tab in Settings shows the same state.

### AC8: A hidden icon gets help

- **Given** the third step
- **When** the Filbert menu bar item is not visible on any screen, because the menu bar is full or the notch covers it
- **Then** the step says that the menu bar has no space for the icon, and how to make space: hold ⌘ and drag other icons out of the menu bar
- **And** it says that the user can open Filbert again from the Applications folder or Spotlight to open Settings.

### AC9: Done closes the window for good

- **Given** any step
- **When** the user selects "Done" on the last step, or closes the window
- **Then** Filbert saves the Welcome completion value
- **And** the Welcome window does not open at the next launch.

### AC10: Opening Filbert while it runs shows a window

This is not about the Welcome window for existing users. Today, when Filbert already runs and the user opens it again, for example a double-click in Applications, nothing visible happens. A user whose icon is hidden then has no way in.

- **Given** Filbert runs
- **When** the user opens Filbert again from Finder, Spotlight, or Launchpad
- **Then** Filbert opens the Welcome window if the user has not completed it
- **And** otherwise it opens Settings
- **And** the window comes to the front.

### AC11: The user can see the Welcome window again

- **Given** the General tab in Settings
- **When** the user selects "Show Welcome Window"
- **Then** the Welcome window opens on the first step.

### AC11a: Developers can open it on demand

- **Given** any install, with or without the Welcome completion value
- **When** Filbert launches with the `--show-welcome` argument, for example `swift run App --show-welcome` or `open -a Filbert --args --show-welcome`
- **Then** the Welcome window opens on the first step
- **And** the argument does not reset the saved completion value. Closing the window saves it, as in AC9.

### AC12: Settings still opens

- **Given** the Welcome window is open
- **When** the user selects "Open Settings" in the popover
- **Then** the Settings window opens and comes to the front, and the Welcome window does not.

### AC13: The window is accessible

- **Given** VoiceOver is on
- **When** focus moves through each step
- **Then** VoiceOver reads the step number, the headings, and every control
- **And** the user can move between the steps with the keyboard alone. Return selects the main button.

### AC14: The text is in every language

- **Given** the new strings
- **When** the catalog test (ui 29 AC3) runs
- **Then** every new string has a value in every supported language (ui 31).

## Plan

1. [x] `WelcomeState` in `Sources/App`. It reads and writes the completion value (`welcome-completed`) through an injected `UserDefaults`, and takes the launch arguments as an injected list. `shouldShowOnLaunch` is true when the arguments contain `--show-welcome`, or when neither the completion value nor `provider-enablement` exists. `AppMain.init` reads it before it builds the view model, because the first enablement read saves `provider-enablement`. Core gets `ProviderEnablement.hasSavedValues`. `WelcomeStateTests` covers AC1, AC2, AC9, and AC11a.
2. [x] Settings lookup (AC12). The Settings scene does not let Filbert set its window identifier before the first lookup. So the Welcome window gets the fixed identifier `filbert.welcome`, and `SettingsWindowLookup` skips it. `raiseSettingsWindow()` is now shared by the popover button and the reopen path.
3. [x] Shared views. `ProviderSetupCard` (the provider card and its private rows, moved from `SettingsView`), `LanguagePicker`, and `LaunchAtLoginControls`. Both windows use the one `LaunchAtLoginController` from `AppMain` (AC7a). Settings uses the same views, and the existing tests pass.
4. [x] `WelcomeView` with three steps (AC3, AC5, AC6, AC7). `WelcomeFlow` holds the step and the selected provider. It lives in the controller, above `DisplayLanguageRoot` (AC4). Fixed size 540 × 540. "Back" and "Continue" at the bottom. The main button is the default button (Return).
   - On the provider step, a provider is a compact row until the user selects it. Then the row becomes the full Settings card. The main button reads "Skip for now" until a provider is configured, then "Continue".
   - The menu bar picture uses the real `MenuBarStatusIcon`, so it shows what the user will see.
5. [x] The window and the launch (2026-10-19). An `NSWindow` that hosts `WelcomeView` in an `NSHostingView`, owned by `WelcomeWindowController`. A SwiftUI `Window` scene would need `openWindow` from a live view, and the reopen path starts in `AppDelegate`.
   - The controller opens the window on the tick after `didFinishLaunchingNotification`, after `AppDelegate` sets the accessory policy. Checked with `--show-welcome` on the debug build: the window opens at launch.
   - `NSWindow(contentViewController:)` binds the window title to the controller's title, and `navigationTitle` does not reach a plain `NSWindow`. The view sets the title itself, so it follows the language. Checked: "Welcome to Filbert".
6. [x] Reopen (AC10). `applicationShouldHandleReopen` calls the controller. `WelcomeWindowBridge` sits in the menu bar label, which renders at launch, and hands over `openSettings`, which only a scene view can read. Its `onAppear` fires at launch (checked).
7. [x] Hidden icon check (AC8), partly verified (2026-10-19).
   - A representable view in the menu bar label never gets a window. SwiftUI does not host the label's views in the status item. So `StatusItemVisibility` reads `NSApp.windows` at the `.statusBar` level instead. It skips panels and windows with no screen, because SwiftUI keeps an off-screen copy at `y = -33`.
   - On this Mac, the visible icon reads as visible. The hidden case is not checked yet; see step 10. The check runs when the menu bar step appears and on each occlusion change. With no status bar window, the tip shows in small text.
8. [x] "Show Welcome Window" card on the General tab (AC11).
9. [x] Strings (AC14). 18 new keys in every language. The catalog tests pass, including the deny lists. Two long sentences were shortened to keep lines under the lint limit. Needs a native review, as for (ui 31).
10. [ ] Manual check in the packaged app:
    - a fresh user account (AC1), and an updated install (AC2);
    - a full menu bar or the notch hiding the icon (AC8);
    - a reopen from Finder before and after Done (AC10), with the popover's "Open Settings" while the Welcome window is open (AC12);
    - a language change on each step (AC4), VoiceOver and keyboard only (AC13).

## Risks

- `--show-welcome` is also accepted in release builds. It only opens a window and changes no saved state, so it is safe, and it lets the packaged app be checked in Plan step 10.
- The provider check (AC2) is a guess. A user who launched an old build but never opened the providers can still lack `provider-enablement`. That user sees the Welcome window one time. This is acceptable.
- Plan step 3 changes Settings code. A wrong move can break the API key field, the base URL override, or the helper actions. The existing tests and a manual check of every provider card must pass before the Welcome window uses the shared view.
- Under the `.accessory` policy, a window can open behind other apps or not take focus. Each open must activate the app.
- The language rebuild resets text in an API key field that is not saved (ui 32 Risks). In the Welcome window, the language picker and the key field are on different steps, so this is rare.
- `applicationShouldHandleReopen` changes how Filbert reacts when the user opens it again. Today nothing happens. Users who expect nothing to happen now see Settings.
- The hidden icon check (AC8) finds the status item by its window level. Apple does not document that the status item is a window at that level. It can give a wrong answer on a future macOS version. A wrong answer shows or hides a tip. It does not block the user.
