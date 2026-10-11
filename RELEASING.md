# Publishing and updates

Source repository: https://github.com/Kickchat/plantuml-studio (private by owner choice). Source publication succeeded before update development. `main`, `release/v0.2`, `release/v0.3` and `feature/appearance-redesign` retain their original history. `feature/release-updates` contains the release infrastructure. Do not merge it into main without owner approval.

## Current status

0.4.0 is a development build, not a published stable release. There are no Apple or Sparkle credentials or hosting variables configured in the repository. Production update delivery remains disabled until a public HTTPS feed and valid public key are embedded. No Developer ID/notarization or installed-app upgrade has been claimed as tested.

The repository stays private. GitHub Releases are the canonical private release archive; users download signed archives and signed appcasts from separate public HTTPS hosting. The included publisher supports S3-compatible storage behind a public HTTPS domain/CDN. No GitHub token is embedded in the application. The app bundle identifier and existing preference/session/history paths remain unchanged.

## Owner setup

Create a GitHub Actions environment named `release`, with required reviewers and tag restrictions. Configure secrets there (or at repository level). Never paste private keys/passwords in issues or chat, and never commit them.

| Secret | Value |
| --- | --- |
| APPLE_CERTIFICATE_P12_BASE64 | Base64 export of Developer ID Application certificate **with private key** |
| APPLE_CERTIFICATE_PASSWORD | Password protecting that P12 |
| APPLE_ID | Apple Developer account login |
| APPLE_TEAM_ID | Developer team identifier |
| APPLE_APP_PASSWORD | App-specific password for notarization |
| SPARKLE_PRIVATE_KEY | Base64 32-byte seed exported by Sparkle 2.10 `generate_keys` |
| UPDATE_ACCESS_KEY_ID | Dedicated S3-compatible publishing access key |
| UPDATE_SECRET_ACCESS_KEY | Matching storage secret; limit write permissions to update prefix |

| Variable | Value |
| --- | --- |
| DEVELOPER_ID_APPLICATION | Exact `Developer ID Application: … (TEAMID)` certificate identity |
| SPARKLE_PUBLIC_KEY | Public Ed25519 key printed by `generate_keys` |
| UPDATE_BASE_URL | Public HTTPS base, e.g. your existing domain's `/updates` path; no credentials/query/fragment |
| UPDATE_BUCKET | S3-compatible bucket |
| UPDATE_PREFIX | Optional object prefix matching the URL path |
| UPDATE_REGION | Storage region (required) |
| UPDATE_S3_ENDPOINT | Optional HTTPS API endpoint for non-AWS S3 providers |

The publisher stores files under `UPDATE_PREFIX/stable/`; their URLs must be `UPDATE_BASE_URL/stable/<filename>`. Allow anonymous HTTPS GET for these update objects only, not writes. Keep directory listing and public access to signing material disabled. The workflow checks for the `aws` CLI and installs it through Homebrew if absent.

After `swift package resolve`, Sparkle tools are in `.build/artifacts/sparkle/Sparkle/bin`. Run `generate_keys --account PlantUMLStudio` once on the owner's Mac; this stores the key in the owner's Keychain. Export with `generate_keys --account PlantUMLStudio -x <secure-file-outside-repository>`, upload that file's contents to SPARKLE_PRIVATE_KEY, then securely remove the export. Use the same account with `-p` to retrieve the public key. The workflow checks that the seed and embedded public key match. Keep an offline protected backup; do not regenerate keys for each release.

Enable GitHub Actions. The runner label is `macos-15` (arm64). Do not switch to an Intel runner: the bundled JRE is arm64. Approve the integration PR only after its checks pass. `main` currently contains the preserved v0.1 baseline until an explicitly approved merge.

## Next release

1. Finish and review changes, update CHANGELOG.md, run `python3 -m unittest discover -s scripts/tests -v`, `./scripts/test.sh`, `./scripts/build.sh`, and `./scripts/smoke.sh` in a macOS graphical session. Resolve packages first on a clean checkout.
2. For a later version run `python3 scripts/version.py bump --version 0.4.1 --build 5`. Both semantic version and integer build must increase. For the first updater release the prepared version is 0.4.0/build 4. Do not publish the earlier local ad-hoc 0.3.1 build as an updater release.
3. Commit, open/review a PR and obtain approval before merging into main. Pull-request CI runs release-script tests, Swift tests, and builds/verifies an ad-hoc app without uploading release artifacts or accessing signing secrets.
4. From the approved main commit create an annotated tag: `git tag -a v0.4.0 -m 'PlantUML Studio 0.4.0'`, then `git push origin v0.4.0` (replace version for later releases).
5. `Signed stable release` rejects a mismatched version, tag outside approved main history, missing credentials, or an existing GitHub Release for that version. It tests, imports a temporary signing keychain, builds, signs native code from inside out, runs GUI smoke, submits to Apple, requires Accepted, staples/assesses the app, then creates the final ZIP.
6. Sparkle generates and signs the appcast and embedded notes using the private seed. Validation checks version/build, exact public download URL, ZIP length and EdDSA signature; the signed feed is independently verified. A draft GitHub Release receives artifacts and generated Git-history notes.
7. ZIP/notes/checksums are mirrored and downloaded anonymously to verify SHA-256. The signed appcast is published last with a short cache lifetime, then the GitHub Release is made non-draft. No debug/ad-hoc artifact is delivered to Stable.

Release cleanup removes temporary P12/seed/keychain even on failure. GitHub masks configured secrets; scripts do not log credential values. The only relaxed runtime entitlements are JIT/executable-memory permissions on the Java launcher; the application itself retains library validation. These Developer ID/JRE signing details must be confirmed in the first real signed release.

## App behaviour

Sparkle 2 handles standard update UI, version comparisons, dismiss/skip, signed downloads, extraction and installation/relaunch. Automatic checks run daily and there is a non-interactive launch check. Silent automatic installation is disabled. The stable channel allows no beta-tagged entries; a future Beta setting can change the allowed channels/feed without changing the installation architecture.

The app requires HTTPS, an embedded 32-byte public key, signed feeds and archive verification before extraction. Without feed/key configuration the update menu is disabled and the app continues to work. No network request can block opening documents. A deployment can move appcast/archives to another HTTPS host by changing the build configuration; preserve the original URL or redirect it for already installed applications.

Before relaunch Sparkle's installation handler is postponed. The existing save/cancel/discard flow protects dirty documents. Cancel retains the pending handler; the update menu retries it later. Ordinary window/app termination also retains the existing unsaved-document check and persisted session. UserDefaults, themes, documents and saved history are not migrated or deleted by the updater.

## Recovery

- Failure before draft creation: fix configuration/build/notarization, rerun the failed workflow for the same tag only if no version was delivered. Never overwrite a delivered release.
- A draft exists but no feed was published: inspect logs and public objects. After owner review, remove the unpublished draft and its unreferenced objects before retrying; the duplicate guard intentionally blocks silent overwriting.
- Feed was published: users may already have installed it. Keep artifacts immutable; ship a new semantic version/build as a forward fix. Do not replace ZIP bytes, repoint a version or lower the build number.
- Keep the previous signed feed in storage version history. Restore it only to stop offering a faulty new release; it cannot downgrade already updated applications. Configure CDN TTL at 60 seconds for appcast and immutable caching only for versioned archives/notes.
- Lost signing credentials: stop publishing; follow [Sparkle key rotation](https://sparkle-project.org/documentation/) and Apple certificate procedures. Do not remove signature verification.

## Required acceptance test

Once owner credentials and hosting exist, install a Developer ID signed, notarized 0.4.0 in `/Applications` and release a similarly signed 0.4.1/build 5. Verify standard notification, notes, postpone/skip, installation/relaunch, unchanged theme/session/history, and no repeated offer of the installed version. Exercise offline checks, interrupted download, corrupted ZIP, wrong EdDSA signature, and dirty-diagram save/cancel. Use an isolated HTTPS test feed and test keys for destructive fixtures; never alter Stable archives. Existing pre-Sparkle installations require a one-time manual installation of the first Sparkle-enabled release.

Official references: [Sparkle setup](https://sparkle-project.org/documentation/), [programmatic API](https://sparkle-project.org/documentation/programmatic-setup/), [publishing](https://sparkle-project.org/documentation/publishing/), [GitHub macOS runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).
