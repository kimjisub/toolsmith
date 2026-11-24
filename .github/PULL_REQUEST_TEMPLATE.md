## What and why

<!-- One feature or fix. What it changes for the person using the app. -->

## How it was checked

- [ ] `scripts/build.sh --test` passes without warnings (includes the design lint)
- [ ] Tried in a development build (`TOOLSMITH_SUPPORT_DIR=<empty folder>` keeps your own settings safe)
- [ ] Screenshot for anything visible (a development build can draw its own windows, see CONTRIBUTING.md)

## For a new or changed module

- [ ] One folder, one line in `ModuleRegistry`; nothing feature-specific in the app's shell
- [ ] `stop()` leaves nothing running; switching it off and on works without a restart
- [ ] Only tokens and parts from `App/Main/Theme`
- [ ] Permissions it needs are in its `ModuleDescriptor`
