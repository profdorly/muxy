# Crash or error spike after a release

Use when Sentry alerts (Discord) or user reports indicate a new crash or
error signature after a release.

## Triage

1. Open the Sentry project and sort issues by `freq` (most events first).
2. Identify whether the top issues share a release (`release:` tag) matching
   the version that just shipped.
3. Check the Discord **Muxy Alerts** messages for the first-seen timestamps
   to confirm the spike started with the release.
4. Confirm the blast radius: affected macOS versions and architectures are
   visible on the issue's tags.

## Mitigate

- **Beta channel:** run the [rollback runbook](rollback.md) to re-point the
  beta appcast at the last good beta tag.
- **Stable channel:** stable releases are promoted from a beta tag. If the
  bad build is stable, ship a fix forward:
  1. Land the fix on `main` (all checks must pass).
  2. Let `Release (Beta)` publish a new beta containing the fix.
  3. Promote the fixed beta with the `Release` workflow.

## Resolve

1. Verify the fix: the Sentry issue's event count for the new release stays
   at zero for at least one alert window (30 minutes).
2. Mark the Sentry issue resolved; it reopens automatically on regression.
3. If `sentry-to-issues` filed a GitHub issue, close it with a link to the
   fixing PR.
4. Add a regression test that would have caught the crash.
