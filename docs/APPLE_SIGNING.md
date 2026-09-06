# Apple signing in GitHub Actions

Tagged releases can use your Apple Developer Program membership to distribute a Developer ID-signed and notarized app outside the Mac App Store. Ordinary CI and pull requests remain ad-hoc signed and receive no Apple credentials.

## One-time Apple setup

1. Use an active, paid Apple Developer Program membership. In Xcode → Settings → Accounts → Manage Certificates, create a **Developer ID Application** certificate if you do not already have one. You need the appropriate account permissions; contact your team’s Account Holder if creation is unavailable. An Apple Development or Mac App Distribution certificate is not interchangeable with Developer ID Application.
2. Export that certificate **with its private key** as a password-protected `.p12` using Keychain Access. The public `.cer` file alone cannot sign an app. Record the full identity, for example `Developer ID Application: Your Name (ABCDE12345)`.
3. Create an App Store Connect **team API key** authorized for notarization. Download its `.p8` private key, and record the Key ID and Issuer ID. This workflow uses team keys, so the Issuer ID is required. Keep the downloaded key securely; Apple only offers the private-key download once.

For this app’s current capabilities, no App Store listing, sandbox entitlement or provisioning profile is needed. You do not need to put your normal Apple account password in GitHub.

## GitHub configuration

Create a repository environment named **`apple-signing`** under Settings → Environments. Restrict its deployment tags to `v*`, and add a required reviewer to inspect the tagged commit before credentials are released. On a team, prevent self-review so a different trusted person approves. Restrict who can create or update release tags using a repository ruleset. A `v*` name alone does not make a commit trustworthy; review workflow and packaging-script changes in particular.

Add these **environment secrets**, never source files or chat messages. Base64 only encodes the certificate; GitHub secret storage and environment access controls protect it. Keep a secure local backup, and revoke/replace credentials if they are exposed:

| Secret | Value |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64` | Base64-encoded `.p12`, including the signing private key |
| `DEVELOPER_ID_P12_PASSWORD` | Password used to protect the exported `.p12` |
| `DEVELOPER_ID_IDENTITY` | Full `Developer ID Application: … (TEAMID)` identity |
| `APP_STORE_CONNECT_KEY_P8` | Contents of the downloaded `.p8` file |
| `APP_STORE_CONNECT_KEY_ID` | API Key ID |
| `APP_STORE_CONNECT_ISSUER_ID` | Team API Issuer ID |

For example, upload files directly without printing their contents:

```sh
base64 -i /secure/path/DeveloperID.p12 | gh secret set DEVELOPER_ID_P12_BASE64 --env apple-signing
gh secret set APP_STORE_CONNECT_KEY_P8 --env apple-signing < /secure/path/AuthKey_KEYID.p8
# These commands prompt for values without putting them in shell history:
gh secret set DEVELOPER_ID_P12_PASSWORD --env apple-signing
gh secret set DEVELOPER_ID_IDENTITY --env apple-signing
gh secret set APP_STORE_CONNECT_KEY_ID --env apple-signing
gh secret set APP_STORE_CONNECT_ISSUER_ID --env apple-signing
```

After all six secrets are configured, set the **repository Actions variable** `APPLE_SIGNING_ENABLED` to `true`:

```sh
gh variable set APPLE_SIGNING_ENABLED --body true
```

This must be a repository variable, not an environment variable: the workflow decides whether to schedule the signing job before entering the environment. Leave it unset until credentials are ready. Once enabled, missing credentials, rejected notarization, timeout, or failed Gatekeeper checks prevent publication; there is no automatic ad-hoc fallback.

## Release behavior

Push a new version tag after merging and verifying the release changes. Existing published versions are not silently re-signed or replaced.

The workflow:

1. Runs Apple silicon and Intel tests and the standard package checks.
2. Enters the protected environment on a fresh macOS runner, verifies the tagged commit belongs to main, and downloads/verifies the already-tested app. Project compilation runs before credential access.
3. Imports the certificate into a temporary keychain and validates the notarization credentials.
4. Signs the universal app with hardened runtime and a secure timestamp.
5. Submits an app ZIP with `notarytool`, requires `Accepted`, and staples the app.
6. Creates the final ZIP from that stapled app, then creates, signs, notarizes and staples the DMG.
7. Validates tickets and Gatekeeper acceptance for the original app, the ZIP-extracted app, the DMG-mounted app and the DMG. Checksums are generated after stapling.
8. Publishes the notarized artifacts and accurate signing status in installation/release notes, and removes credentials from the signing runner using an always-run cleanup step. Only the separate publication job has `contents: write`; the signing job has `contents: read`.

The ZIP itself cannot be stapled; the app inside it carries the ticket. Notarization submissions wait up to 30 minutes each. On timeout or rejection the release stops. Available diagnostic JSON is retained as a workflow artifact for seven days. A timeout does not mean Apple rejected the app; inspect the submission before retrying the failed job.

## Validation status

The ad-hoc path can be exercised without an Apple account. Script tests check accepted, rejected, timed-out and malformed notarization responses, and missing configuration. They do not establish that a real certificate or Apple account works. The first signed release still requires a successful live Apple submission and Gatekeeper verification with your credentials.

References: [GitHub environment protections](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments), [GitHub secure workflow guidance](https://docs.github.com/en/actions/reference/security/secure-use), [Apple Developer ID](https://developer.apple.com/developer-id/), [Apple notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow), [GitHub certificate setup](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications).
