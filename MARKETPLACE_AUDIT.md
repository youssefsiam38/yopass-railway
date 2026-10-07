# Marketplace audit

A record of the diligence behind publishing this template.

## Identity

- Template: **Yopass** — end-to-end encrypted, one-time, expiring secret sharing (text and small files).
- Upstream: [jhaals/yopass](https://github.com/jhaals/yopass), Apache-2.0, actively maintained (release 14.10.0,
  September 2026), official multi-arch image `jhaals/yopass`.
- Marketplace gap (2026-10-07): no template named Yopass; the closest category entry ("One-Time Secret", a different
  product) had 9 deploys.

## Licence and brand

- **Apache-2.0** (`licenses/YOPASS-LICENSE`): commercial redistribution and hosting allowed. Used unmodified.
- Business-licence features (OIDC creation login, branding, audit log, webhooks, secret requests) are gated by a
  licence key at runtime and are not used.
- **Valkey** BSD-3-Clause, unmodified. Redis ≥ 7.4 (RSAL/SSPL) deliberately not bundled.
- **Brand.** Generic padlock icon; "not affiliated" disclaimer; no Yopass logo.

## Security review

- **No accounts, no admin, nothing to bootstrap** → no first-run race.
- **Public creation is the product.** Gating the whole site would lock out recipients (one SPA serves create and
  read); native creation auth is a paid feature. Decision: ship open creation, bounded (Valkey `maxmemory` 256 MB with
  `volatile-ttl`, `MAX_LENGTH` 10000, 512 KB files, ≤ 1 week TTL), CORS restricted to the app's own origin, and
  document `READ_ONLY` / `DISABLE_UPLOAD` / `FORCE_*` / access-proxy options in `SECURITY.md`.
- **Confidentiality** does not depend on the operator: the server only stores OpenPGP ciphertext (verified by the
  tests: stored message ≠ plaintext, is a PGP message, decrypts client-side to the original).
- **Store** private, password generated, never printed; images digest-pinned.

## Reproducibility & tests

- `tests/static.sh`: syntax, executability, shellcheck, compose shape, digest pins, Yopass/Valkey config, docs, secret scan.
- `tests/smoke.sh`: every product flow (see README) plus Valkey TTL per expiry, simulated elapsed expiry, and store hardening.
- `tests/persistence.sh`: unread secrets survive a Yopass restart and a full recreate; consumed stays gone; TTL continues.
- `tests/railway-smoke.sh`: flows over HTTPS, plus `plant` / `verify` / `final` around redeploys and `expired`
  (a real 1-hour secret is gone after an hour).
- CI runs static + smoke + persistence on every push (official images, nothing built).

## Deploy-time inputs

None required. `REDIS_PASSWORD` is generated; everything else has a default.

## Live verification (2026-10-07)

Clean-room deploy of the template: both services SUCCESS. `tests/railway-smoke.sh` over HTTPS 38/38; after a yopass
redeploy and then a valkey redeploy (AOF reload) the planted secrets survived (5/5 each), the surviving one-time
secret read once then 404 (3/3); a 1-hour secret was 404 after 3620 s while a 1-week secret remained (4/4).
Published as https://railway.com/deploy/yopass.

## Verdict

**SHIPPABLE**, no wrapper.
