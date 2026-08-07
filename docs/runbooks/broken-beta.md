# Broken beta channel

Symptoms: beta users report no update found, a DMG that fails to install, or
Sparkle signature errors.

## Diagnose

1. Open the `beta-channel` release and confirm both
   `appcast-beta-arm64.xml` and `appcast-beta-x86_64.xml` are present and
   recently updated.
2. Download the appcast and check the enclosure URL points at an existing
   DMG in the referenced beta tag release.
3. Signature errors mean the appcast was generated without the correct
   `SPARKLE_PRIVATE_KEY`; verify the secret is still valid by re-running the
   **Republish Beta Appcast** workflow for the current tag.

## Repair

- **Missing/stale appcast:** run **Republish Beta Appcast** with the latest
  good beta tag.
- **Missing DMG artifacts:** re-run the **Release (Beta)** workflow; it
  rebuilds and re-uploads DMGs for a fresh beta tag.
- **Corrupt appcast:** delete the two appcast assets from the `beta-channel`
  release, then republish as above (the workflow regenerates them from the
  DMG plus the previous appcast when present).

## Verify

1. Fetch `https://github.com/<repo>/releases/download/beta-channel/appcast-beta-arm64.xml`
   and confirm the top item is the intended version.
2. On a beta-channel install, run a manual update check from the app menu.
