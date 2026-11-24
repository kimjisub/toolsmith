# Releasing

Builds for users are signed with a Developer ID, notarized by Apple and published by CI. This page is for the maintainer.

## Publish a release

Push a tag `v<version>` from `main`:

```bash
git tag -a v2026.11.1 -m "Toolsmith 2026.11.1"
git push origin v2026.11.1
```

CI (`.github/workflows/ci.yml`, macOS runner) then:

1. builds the Release configuration with that version (`TOOLSMITH_VERSION`) and the run number as the build number, and runs the tests and the design lint;
2. signs every executable (the charge helper with its own identifier, then the app) with hardened runtime, makes the DMG and notarizes it (`scripts/release.sh`);
3. publishes the DMG and `release.json` (version, build, sha256, size) as a release in this repository (`scripts/publish-release.sh`), where people download it and installed apps look for updates.

Versions are CalVer `YYYY.M.PATCH`: year, month without a leading zero, and a number that starts at `0` each month (`2026.11.0`, `2026.11.1`, `2026.12.0`). Never reuse or lower a version; automatic updates only install higher ones.

Pushes to `main` and pull requests build and test only. A manual run of the workflow also signs and notarizes, and keeps the DMG as the artifact `Toolsmith-dmg` (30 days) without publishing it.

## Automatic updates

Installed apps read this repository's latest release through GitHub's public API, 20 seconds after launch and every six hours (Settings → 정보 can turn this off or check now). No token is needed. A newer build is installed only if its sha256 matches `release.json`, it is signed by the same Developer ID team as the running app (`APP_TEAM_ID` in `project.yml`) and Apple notarized it. A running screen recording is never interrupted; the swap waits until it ends. Only builds signed by the team update themselves; development builds and copies you build yourself do not.

## CI secrets

| Secret | What |
|---|---|
| `DEVELOPER_ID_P12_BASE64`, `DEVELOPER_ID_P12_PASSWORD` | The Developer ID Application certificate and private key (.p12, base64) and its password |
| `NOTARY_APPLE_ID`, `NOTARY_TEAM_ID`, `NOTARY_PASSWORD` | Apple ID, team and app-specific password for `notarytool` |

CI imports the certificate into a throwaway keychain for each run (`scripts/ci-signing-keychain.sh`) and publishes with the workflow's own `GITHUB_TOKEN`. Signing steps run only for tags and manual runs, never for pull requests.

## Building a release on a Mac

On a Mac with the signing identity in a dedicated keychain (`~/Library/Keychains/toolsmith-signing.keychain-db` by default):

```bash
scripts/build.sh --release
scripts/release.sh --skip-build
```

`scripts/release.sh` reads the keychain password from `TOOLSMITH_SIGNING_KEYCHAIN_PASSWORD` (or a 1Password reference in `TOOLSMITH_SIGNING_KEYCHAIN_OP_REF`) and the notarization credentials from `TOOLSMITH_NOTARY_APPLE_ID`/`TEAM_ID`/`PASSWORD`, a saved `notarytool` profile (`toolsmith-notary`), or `TOOLSMITH_NOTARY_OP_REF`. At the end `spctl` must report `accepted … source=Notarized Developer ID`. `--adhoc` checks the pipeline without a certificate (ad-hoc signature, no notarization).

## Your own signed build

Change the identity block at the top of `project.yml` (`APP_NAME`, `APP_BUNDLE_ID`, `APP_TEAM_ID`, `APP_UPDATE_REPOSITORY`, `APP_COPYRIGHT`) to yours and set `TOOLSMITH_SIGN_IDENTITY` to your Developer ID Application identity. Your builds then trust and update from your own releases only.
