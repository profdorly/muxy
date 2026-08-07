# Runbooks

Operational procedures for Muxy maintainers. Each runbook is a step-by-step
response to a specific incident class.

## Index

- [Crash or error spike after a release](crash-spike.md)
- [Rolling back a bad release](rollback.md)
- [Broken beta channel](broken-beta.md)

## Tooling references

- **Error tracking:** Sentry project (see `SENTRY_ORG`/`SENTRY_PROJECT` repo
  variables). The app only reports after explicit user consent.
- **Release automation:** `.github/workflows/release.yml` (stable),
  `release-beta.yml` (beta), `republish-beta-appcast.yml` (beta rollback).
- **Alerting:** `.github/workflows/sentry-alerts.yml` posts new Sentry issues
  to Discord every 30 minutes.
- **Error triage:** `.github/workflows/sentry-to-issues.yml` files GitHub
  issues for unlinked Sentry issues daily.
