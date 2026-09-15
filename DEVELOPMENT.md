# Development

## Build and package

Requires Xcode with the macOS SDK and Swift 5.9 or later. Open `Package.swift` in Xcode, or:

```sh
swift build
swift test
./scripts/package.sh
open "dist/Activity Monitor.app"
```

The packaging script builds a universal binary, creates the app bundle and icon, signs it, and emits a compressed DMG, ZIP and SHA-256 checksums. The DMG includes an Applications shortcut and installation notes. Generated artifacts are ignored by Git.

For a notarized release, configure a Developer ID Application identity and an existing `notarytool` keychain profile:

```sh
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="your-existing-notary-profile" \
./scripts/package.sh
```

The optional path signs with hardened runtime and a secure timestamp, notarizes and staples the app, then builds the final ZIP and DMG. It signs, notarizes and staples the DMG too. Both downloads contain the stapled app. Set `EXPECT_NOTARIZED=1` when running `scripts/verify-package.sh` to check tickets and Gatekeeper acceptance. Credentials are never stored in this repository.

## Structure

- `Sources/SystemBridge`: small C bridge for kernel process enumeration, libproc counters, host CPU/VM statistics, 64-bit interface statistics and IOKit battery information.
- `Sources/ActivityMonitor/Monitor.swift`: background sampling, counter deltas, bounded histories, serialization and validated process termination.
- `Sources/ActivityMonitor/ContentView.swift`: fixed dashboard shell, custom toolbar, theme controls and diagnostics.
- `Design.swift`, `Overview.swift`, `ProcessTable.swift`, `Inspector.swift`, `Gallery.swift`: reference-matched visual components, charts and view gallery.
- `GPUCollector.swift`, `GPUOverview.swift`: optional driver GPU counters, process-rate baselines, device histories and the GPU overview. See [hardware validation](docs/GPU_VALIDATION.md).
- `ANECollector.swift`, `ANEOverview.swift`: read-only Neural Engine driver descriptors and direct-path process connections. See [hardware validation](docs/ANE_VALIDATION.md).
- `NetworkCollector.swift`: bounded nettop collection and CSV parsing.
- `Sources/ActivityMonitor/ActivityMonitorApp.swift`: window, commands and optional menu-bar item.
- `Tests/ActivityMonitorTests`: live collector, CPU accounting, export and disposable-process termination tests.
- `scripts`: deterministic icon generation and universal release packaging.

See [QA.md](QA.md) for verification and its limits.


## Continuous integration and releases

GitHub Actions builds and runs the test suite on the latest macOS Apple silicon runner. Native Intel tests can be enabled through manual CI dispatch. After tests and performance gates pass, CI builds and verifies the universal app, DMG and ZIP, and retains the complete installer artifacts for 30 days. Pull requests, pushes to main and manual CI runs use the same reusable build workflow.

To release, first wait for green CI on the intended commit, then push a version tag such as `v1.0.1`. The release workflow validates the tag, repeats the Apple silicon tests and performance gates, builds versioned universal installers, verifies their contents and signatures, and publishes a GitHub release only after all checks succeed. It attaches the DMG, ZIP containing the full app bundle, portable SHA-256 checksums and installation notes. Failed builds do not publish a release.

Pull-request builds use ad-hoc signing without Apple credentials. Tagged releases can use the protected `apple-signing` environment for Developer ID signing and notarization; see [Apple signing setup](docs/APPLE_SIGNING.md). Once enabled, signing, notarization or Gatekeeper failures prevent publication. The publishing job uses only its scoped GitHub token.

## Performance regression gates

Run `./scripts/performance.sh` in addition to `swift test` before merging UI or telemetry changes. CI retains release-mode timing samples and physical-footprint measurements. See [performance gates](docs/performance/OPTIMIZATION.md) for budgets, headless coverage, profiling and interpretation.

### Native software updates

Sparkle 2.9.6 is pinned in SwiftPM. `scripts/package.sh` embeds its universal framework,
including its installer helpers, and signs nested code inside out when a Developer ID
is configured. Bare `swift run` does not start the updater; run a packaged app to test it.
The application menu and More menu expose Check for Updates and update preferences.
Daily checks are enabled by default; downloading and installing automatically is opt-in.
Disabling automatic checks suspends background updates. Manual checks remain available.

The feed is the `appcast.xml` asset on the latest GitHub release. Both the feed and ZIP
are Ed25519-signed, and downloads must verify before extraction. Release publishing
fails if the `SPARKLE_PRIVATE_KEY` repository secret is absent, signing fails, or the
archive signature does not match the public key embedded in the app. The secret is a
base64 Sparkle private seed, supplied over stdin, never in command arguments. The
maintainer backup is in the login Keychain under Sparkle account
`com.wieslawsoltes.ActivityMonitor`; keep that key for all future releases.

After building, `VERSION=x.y.z ./scripts/generate-appcast.sh dist` signs a feed locally
using that Keychain account. CI resolves the pinned tools before loading the secret and
signs the exact verified archive after optional Developer ID signing/notarization.
Never edit a signed feed afterward. Do not replace the public key casually: installed
copies trust it, and ad-hoc distributions cannot use Developer ID key rotation.
