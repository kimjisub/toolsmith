# Toolsmith: notes for contributors and coding agents

Toolsmith is a native macOS menu bar app (Swift, SwiftUI + AppKit, macOS 26+) whose features are modules the user switches on and off. What it is for users: `README.md`. How to add a module and the design system: `CONTRIBUTING.md`. This file holds what is easy to get wrong.

## Layout

- `App/Main`: the app. Windows, views, system adapters, and the modules (`App/Main/<Feature>/<Feature>Module.swift`). The shell (`AppEnvironment`, the settings window, `MenuBarController`, `MenuBarPanel`) gathers what modules declare and knows no feature by name.
- `App/Kit`: `ToolsmithKit.framework`, pure logic with XCTest coverage (search, commands, shortcut table, settings, module switches and resolver, menu bar layout, palette and contrast, clipboard store, snippets, monitor maths, charge rules). No SwiftUI or AppKit UI imports here (Carbon and AppKit's non-UI APIs used by adapters are the exception).
- `App/Tests`: XCTest for `App/Kit`.
- `App/Helper`: the charge-limit helper (root, launchd daemon).
- `App/CLI`: the `toolsmith` command line tool (Contents/Helpers/toolsmith). It forwards its arguments over a Unix socket in the support folder (`CLIEndpoint`, owner-only, same user checked) to the running app's `CLIServer`, which hands `toolsmith <name> …` to the module whose `commandLine` has that name. Sign it like the helper, with `--identifier <bundle id>.cli`.
- `App/Main/Theme`: design tokens and parts. Everything visual comes from here (see CONTRIBUTING, Design system).

## Modules

- A module declares itself in `ModuleDescriptor` (id, title, summary, symbol, tile, default on/off, requirements, permissions, menu bar items) and provides commands, default shortcuts, menu bar drawing, panel screens, settings groups, `start()` and `stop()`. One line in `ModuleRegistry` registers it.
- Off means off: after `stop()` no timer, observer, window, tap or helper connection of the module remains. Its saved data and shortcut bindings stay; switching it on brings everything back without a restart. Do the work in `start()`, not in `init`.
- The shell resolves requirements (`ModuleResolver`): a module whose requirement is off does not run.
- Settings pages are drawn by the shell in one shape (`ModuleSettingsScreen`): header with the switch, the module's groups (`settingsGroups`), its shortcuts, its permissions. Modules return groups made of settings parts only.
- Menu bar items all open one panel (`MenuBarPanel`); modules add pages with `panelScreens`. The launcher, the ⌥V clipboard strip, capture overlays and the annotation editor, the settings window and onboarding live outside the panel on purpose.
- Settings live in one JSON file (`Settings`, schema 2). Old files are migrated when read; never remove a key's decoding without a migration.

## Text and languages

- English in code, Korean in the String Catalogs (`App/Main/*.xcstrings`, `App/Kit/Localizable.xcstrings`); how to write text is in CONTRIBUTING, "Text and languages". `scripts/localization.py check --built` (run by `build.sh`) fails on Korean literals in code (except `keywords:` and lines marked `// not localized:`), untranslated entries and strings missing from the catalogs; `scripts/localization.py sync` adds new strings after a build.
- The app's language is macOS's per-app `AppleLanguages` preference, read only at launch: Settings → General writes it and offers to reopen. `Locale.app` is the language the text is shown in; formatters and SwiftUI hosting views use it so numbers and dates match the words.
- A development build takes the language from the command line without touching the saved preference: `Toolsmith -AppleLanguages "(ko)" …`.

## Design system

- Colors: `App/Kit/Design/Palette.swift` holds the numbers (contrast checked by `PaletteTests`); screens use only the meaning tokens in `App/Main/Theme/Tokens.swift` (`Ink`, `Fill`, `Line`, `Shade`, `Surface`, `Brand`, `Status`, `Tile`, `Tint`).
- Type by role (`.font(.role(.body))`, `.textRole(.detail)`), whole-point sizes. Spacing `Space` on a 4-point grid, `Radius`, `IconSize`.
- Switches and sliders are drawn by the app (`TrackSwitch`, `TrackSlider`): the system ones turn grey when the app is not in front, which a menu bar app almost always is.
- `scripts/lint-design.sh` runs before every build and rejects values written directly in views. Add a token or a part instead of silencing it.
- Dark only. The look is dark glass; a light mode would be a second design.

## Building and checking

- `scripts/build.sh --test`: development build (`Dev` configuration) and the tests. The app ends up in `build/Release/Toolsmith.app`. `scripts/build.sh --release` is what users get. Tools: Xcode 26, XcodeGen. The `.xcodeproj` is generated from `project.yml` and not committed.
- From an agent's sandbox, run the build outside the sandbox: Xcode's build database does not open inside it.
- Keep a single copy of the app on disk. macOS finds apps by bundle id, so a stale copy elsewhere can be the one that launches (after "Quit & Reopen" from a permission prompt, for instance). The tests use a scheme that does not build the app, and `build.sh` deletes the intermediate copy. If something seems to come back, check `pgrep -fl Toolsmith` first.
- Development signing: with a self-signed code-signing certificate named "Toolsmith Dev" in the login keychain, `build.sh` signs with it. Ad-hoc signatures change every build, and macOS ties Accessibility and Screen Recording grants to the signature.
- `TOOLSMITH_DEV` is defined only in the `Dev` configuration: development flags (`--show-panel`, `--snapshot-settings`, `--render-tokens`, `--render-menubar`, `--set-modules`, each module's `runDevelopmentAid`) and the stand-in fan helper. `--release` refuses a binary that still contains development flags.
- Try a development build next to an installed copy with `TOOLSMITH_SUPPORT_DIR=<empty folder>`: settings and histories go there. Keychain items and UserDefaults are still shared (same bundle id).
- A development build can draw its own windows into pictures without Screen Recording permission (`--snapshot-settings <folder>`, `--snapshot-window <folder> <seconds>`, `--render-menubar <png>`). Use them for screenshots in pull requests. For pictures without personal data, start it with an empty `TOOLSMITH_SUPPORT_DIR`, `--mac-name <name>` (the monitor's heading), `--clipboard-demo` (made-up copies in the app's language) and `--audio-demo` (made-up devices, apps and levels on the sound screen; nothing is read from or sent to the audio system). The README pictures (`docs/images/en`, `docs/images/ko`) were made that way, once per language.

## Identity and releases

- The app's name, bundle id (`kim.jisub.toolsmith`), team id, update repository and copyright are set only in the `APP_*` block at the top of `project.yml`. Code reads them through `AppIdentity`, scripts through `scripts/identity.sh`, and the helper's launchd plist is generated from `App/Helper/LaunchDaemons/helper.plist`. Never write the name or the bundle id anywhere else.
- Changing the bundle id makes a new app for every user: Accessibility grants, the login item, Keychain items and the support folder do not follow.
- Releases: a tag `v<version>` builds, signs (Developer ID), notarizes and publishes a GitHub release with the DMG and `release.json`, which installed apps read to update themselves. See `docs/release.md`.

## Things to keep

- Minimum macOS is 26. Do not add fallbacks for older systems.
- Charge limit: the helper (root, launchd daemon) controls charging on every Mac, by AlDente's rules (`ChargePlanner`: charge to the limit, sail until the level falls the sailing range below it, pause at the level when the limit is under it, discharge and charge to 100% only on request). Where the firmware still has the charge controller's keys (`CHTE`, `CH0B`+`CH0C`) it writes them; where they are gone (macOS 27, 26.7 and 15.8 firmware) it writes macOS's own limit as PowerUIAgent's preferences (`NativeChargeLimit`), because PowerUI's client quietly ignores values outside its list, and checks the value took (`NativeLimitWatch`). It writes nothing while another charge app runs (`ChargeConflicts`). The helper accepts only the commands in `ChargeHelperProtocol` and requires the other side's signature (identifier + team). Sign the helper before the app with `--identifier <bundle id>.helper` and hardened runtime, or notarization fails.
- The fan helper is a development stand-in that relaunches the app's own executable as root; it must never ship. Shipping fan control needs a separate small helper installed as a daemon with signature checks.
- Hangul: composing text must already search, and one Return while composing both commits the syllable and runs the selection.
- The launcher never takes "frontmost app" from the app in use (a non-activating panel): window snapping and pasting act on that app.
- The system monitor reads only what macOS allows without administrator rights; CPU package power and per-process power are not available, so it shows "other (incl. CPU)" and energy impact instead.
- Nothing leaves the Mac unless the user asked (AI questions) or can turn it off (public IP lookup, update check). No analytics.
