# Rolling back a bad release

## Beta channel (one click)

The beta appcast is a rolling pointer; re-publishing an older tag rolls back
what beta users receive.

1. Pick the last known-good beta tag from the releases page
   (e.g. `v1.5.0-beta.912`).
2. Run the **Republish Beta Appcast** workflow
   (`.github/workflows/republish-beta-appcast.yml`) with that tag.
3. Sparkle clients pick up the older build on their next update check.

## Stable channel

Stable has no appcast republish workflow. Roll forward instead:

1. Identify the offending change (`git log` between the good and bad tags).
2. Revert it on a branch (`git revert <sha>`), open a PR, wait for the
   **Checks** workflow to go green.
3. Merge; the next `Release (Beta)` run ships a beta with the revert.
4. Promote that beta to stable with the `Release` workflow.

## After the rollback

1. Post a short note in Discord describing what happened and which version
   users should be on.
2. File a GitHub issue (or reuse the one filed by `sentry-to-issues`) to
   track the underlying bug.
3. Add a regression test before re-landing the reverted change.
