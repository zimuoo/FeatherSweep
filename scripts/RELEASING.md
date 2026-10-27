# Local signed releases

On macOS 14 or newer with Xcode command-line tools, run from the repository root:

```sh
bash scripts/release-updates.sh
```

This builds both architectures, verifies each signed app bundle and DMG, generates
architecture-isolated signed appcasts, verifies feed and archive signatures, checks
that modified feeds/archives fail verification, and writes `dist/SHA256SUMS`.
It does not upload anything. To regenerate feeds for already built DMGs, use
`bash scripts/release-updates.sh --feeds-only`.

The official Sparkle 2.10.1 SDK is downloaded over HTTPS, checked against the
pinned SHA-256 in `sparkle-tools.sh`, and cached under ignored `.build/`.
SwiftPM resolves the exact 2.10.1 dependency and checks its binary artifact
checksum. The complete framework is embedded, with symlinks and nested upstream
signatures preserved. The enclosing app is signed ad hoc; this is not Developer
ID signing or Apple notarization.

The signing identity is the login Keychain account
`io.github.zimuoo.FeatherSweep.updates`. The private key must remain in Keychain;
never add it to this repository, a release, an environment variable, or a command
argument. `Resources/UpdatePublicKey.txt` holds only the public key. Release tooling
fails if the account's public key differs from that resource. A new machine needs
the existing signing key securely provisioned into its login Keychain before it
can sign releases; creating a different key would break updates for installed apps.

For a future release, update the version/build in `build.sh`, the version in
`release-updates.sh`, and the expected build number in `verify-update-feed.py`.
Upload the two DMGs, `appcast-arm64.xml`, `appcast-x86_64.xml`, and `SHA256SUMS` to
the matching `vVERSION` GitHub release. Publish that release as latest only once
all assets are present. Never manually modify signed XML after generation;
regenerate and verify it instead. Existing installed apps fetch their architecture
feed through `/releases/latest/download/appcast-ARCH.xml`.
