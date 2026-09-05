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

The optional path signs with hardened runtime, submits the DMG and staples its ticket. It requires your own Apple credentials; none are stored in this repository. The ZIP is an alternative archive of the signed app; the script's stapled artifact is the DMG.

## Structure

- `Sources/SystemBridge`: small C bridge for kernel process enumeration, libproc counters, host CPU/VM statistics, 64-bit interface statistics and IOKit battery information.
- `Sources/ActivityMonitor/Monitor.swift`: background sampling, counter deltas, bounded histories, serialization and validated process termination.
- `Sources/ActivityMonitor/ContentView.swift`: fixed dashboard shell, custom toolbar, theme controls and diagnostics.
- `Design.swift`, `Overview.swift`, `ProcessTable.swift`, `Inspector.swift`, `Gallery.swift`: reference-matched visual components, charts and view gallery.
- `NetworkCollector.swift`: bounded nettop collection and CSV parsing.
- `Sources/ActivityMonitor/ActivityMonitorApp.swift`: window, commands and optional menu-bar item.
- `Tests/ActivityMonitorTests`: live collector, CPU accounting, export and disposable-process termination tests.
- `scripts`: deterministic icon generation and universal release packaging.

See [QA.md](QA.md) for verification and its limits.


## Continuous integration and releases

GitHub Actions builds and runs the test suite on macOS 15 Apple silicon and Intel. After both pass, CI builds and verifies the universal app, DMG and ZIP, and retains the complete installer artifacts for 30 days. Pull requests, pushes to main and manual CI runs use the same reusable build workflow.

To release, first wait for green CI on the intended commit, then push a version tag such as `v1.0.1`. The release workflow validates the tag, repeats both architecture tests, builds versioned installers, verifies their contents and signatures, and publishes a GitHub release only after all checks succeed. It attaches the DMG, ZIP containing the full app bundle, portable SHA-256 checksums and installation notes. Failed builds do not publish a release.

Hosted builds use ad-hoc signing without credentials. Developer ID/notarization remains available through the local packaging script. Release publication needs only the workflow's scoped GitHub token; pull-request builds have read-only repository permissions.
