# Yopass on Railway

One-click [Railway](https://railway.com) template for [Yopass](https://github.com/jhaals/yopass): share passwords,
keys and small files through end-to-end encrypted, one-time links that expire automatically.

> Community-maintained. Not affiliated with or endorsed by the Yopass project. The template ships its own generic
> icon, not the Yopass logo.

- **Image:** the official `jhaals/yopass:14.10.0`, unmodified, pinned by digest (Apache-2.0).
- **Store:** a bundled, private [Valkey](https://valkey.io) 9.1 (BSD-3-Clause, Redis-compatible) with a volume and an
  append-only file, so unread secrets survive redeploys.

## What you get

| Service | Role | Public |
|---|---|---|
| `yopass` | Web app + API on port 1337, health check `/ready` (checks Valkey) | yes (HTTPS domain) |
| `valkey` | Encrypted-secret store, password-protected, 256 MB cap, volume at `/data` | no (private network only) |

Secrets are encrypted in the browser (OpenPGP.js); the decryption key travels only in the link's `#fragment`, which
browsers never send to the server. The server and Valkey only ever hold ciphertext.

## Deploy

1. Click **Deploy** on the marketplace page. No input is required; the Valkey password is generated.
2. Open the `yopass` service's public domain, type a secret, pick an expiry (1 hour, 1 day, 1 week) and share the link.

## Security model (read this)

Yopass is **public by design**: anyone who can reach the URL can create a secret, and anyone with a link can open it
once. There is no login. That is safe for the confidentiality of secrets (end-to-end encrypted, one-time, expiring),
but it means strangers can use your instance to store encrypted blobs. The template bounds this:
Valkey is capped at `VALKEY_MAXMEMORY` (256 MB) with `volatile-ttl` eviction, text secrets at `MAX_LENGTH`, files at
512 KB, and every secret expires within a week. See [SECURITY.md](SECURITY.md) for the options to restrict creation
(`READ_ONLY`, `DISABLE_UPLOAD`, an access proxy) and why the template does not put a password in front of Yopass.

## Repository layout

| Path | Purpose |
|---|---|
| `compose.yaml` | Local topology mirroring the Railway services |
| `tests/static.sh` | Syntax, shellcheck, compose shape, digest pins, config, secret scan |
| `tests/smoke.sh` | Every product flow locally (create, read once, multi-read, delete, files, CLI, expiry/TTL) |
| `tests/persistence.sh` | Secrets survive Yopass and Valkey restarts; TTLs keep counting down |
| `tests/railway-smoke.sh` | The same flows over HTTPS on a deployment, plus plant/verify around a redeploy and a real 1-hour expiry |
| `marketplace/OVERVIEW.md` | Marketplace page |
| `RAILWAY_TEMPLATE.md` | The exact published template configuration |

## Local development

```bash
tests/static.sh
tests/smoke.sh          # needs docker and gpg
tests/persistence.sh
```

Template files are MIT-licensed (`LICENSE`); Yopass and Valkey keep their own licences (`licenses/`).
