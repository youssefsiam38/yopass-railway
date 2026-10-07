# Deploy and Host Yopass on Railway

Yopass shares passwords, API keys and small files through end-to-end encrypted, one-time links that expire after an
hour, a day or a week. This template deploys the official Yopass image with a private, persistent Valkey
(Redis-compatible) store: no input needed, the store password is generated and unread secrets survive redeploys.
Community-maintained; not affiliated with the Yopass project, and it does not use the Yopass logo.

## About Hosting Yopass

Yopass encrypts each secret in the browser with OpenPGP; the decryption key lives only in the link's `#fragment`,
which is never sent to the server, so the server and its store only ever see ciphertext. The template runs two
services: `yopass` (the web app and API, public over HTTPS) and `valkey` (private, password-protected, with a volume
and an append-only file). Every secret is written with a store TTL equal to its expiry, and one-time secrets are
deleted atomically on first read. Yopass has no accounts: anyone with the URL can create secrets, which is how it is
designed. The template caps the store's memory (256 MB, soonest-expiring evicted first), keeps the size limits, and
restricts browser API access to its own origin; `READ_ONLY`, `DISABLE_UPLOAD`, `FORCE_ONETIME_SECRETS` and
`FORCE_EXPIRATION` tighten it further.

## Common Use Cases

- Send a password, API key or recovery code to a colleague or customer without it lingering in chat or email
- Hand over credentials during onboarding or support with links that self-destruct after one view
- Share small encrypted files (certificates, config snippets) that expire automatically

## Dependencies for Yopass Hosting

- Valkey (Redis-compatible), bundled in the template as a private service with a volume
- No external services or API keys

### Deployment Dependencies

- Yopass: https://github.com/jhaals/yopass (Apache-2.0)
- Valkey: https://github.com/valkey-io/valkey (BSD-3-Clause)
- Template repository and tests: https://github.com/youssefsiam38/yopass-railway

### Implementation Details

- Official `jhaals/yopass:14.10.0` and `valkey/valkey:9.1.2-alpine`, unmodified and pinned by digest.
- `yopass` listens on `PORT=1337`; the Railway health check is `/ready`, which only passes when Valkey answers.
- Valkey: `--requirepass` (generated), `--appendonly yes` on the `/data` volume, `--maxmemory 256mb`
  `--maxmemory-policy volatile-ttl`, reachable only on Railway's private (IPv6) network.
- Tested in CI and on a live deployment of this template: create via the API, read once, second read refused,
  multi-read and early delete, encrypted files, the official Yopass CLI, expiry options, unread secrets surviving
  redeploys of both services, and a 1-hour secret gone after an hour.

## Why Deploy Yopass on Railway?

Railway is a singular platform to deploy your infrastructure stack. Railway will host your infrastructure so you
don't have to deal with configuration, while allowing you to vertically and horizontally scale it.

By deploying Yopass on Railway, you are one step closer to supporting a complete full-stack application with
minimal burden. Host your servers, databases, AI agents, and more on Railway.
