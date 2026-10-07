# Railway template configuration

The template's exact configuration. Reproduce it from this file if it ever has to be rebuilt.

| | |
|---|---|
| Name | Yopass |
| Code | `yopass` |
| Template id | `465a5c9e-fc83-4a64-b9d3-d44bd860ea86` |
| Deploy URL | https://railway.com/deploy/yopass |
| Category | Other |
| Card description | End-to-end encrypted one-time secret links, with a private Valkey store |
| Icon | `assets/icon.png` |
| Overview markdown | `marketplace/OVERVIEW.md` (Railway enforces its section headings) |

Generated values use Railway's `secret()` function: `hexN` is `${{secret(N, "abcdef0123456789")}}` and `alnumN` is
`${{secret(N, "a-zA-Z0-9")}}` spelled out. Alphanumeric passwords are used wherever a value is embedded in a
connection URL, so nothing needs percent-encoding. Images are pinned by tag and digest (see the
Source rows and `UPSTREAM.md`).

## Services

### `valkey`

| Field | Value |
|---|---|
| Source | `valkey/valkey:9.1.2-alpine@sha256:48332870af354a799964c0012ae1194a0bf2bf894eb508f945810596dc2d8d11` |
| Public domain | none |
| Volume | `/data` |
| Start command | `sh -c 'exec docker-entrypoint.sh valkey-server --requirepass "$REDIS_PASSWORD" --appendonly yes --maxmemory "${VALKEY_MAXMEMORY:-256mb}" --maxmemory-policy volatile-ttl'` |
| Restart policy | on failure, 10 retries |

| Variable | Value |
|---|---|
| `REDIS_PASSWORD` | generated, alnum32 |
| `VALKEY_MAXMEMORY` | `256mb` |

### `yopass`

| Field | Value |
|---|---|
| Source | `jhaals/yopass:14.10.0@sha256:6c33d9c813f77bae70787e1bce76710840ff654f454998b01f8dacc0a7988fd3` |
| Public domain | target port 1337 |
| Volume | none |
| Healthcheck | `/ready`, timeout from `RAILWAY_HEALTHCHECK_TIMEOUT_SEC` |
| Restart policy | on failure, 10 retries |

| Variable | Value |
|---|---|
| `PORT` | `1337` |
| `DATABASE` | `redis` |
| `REDIS` | `redis://default:${{valkey.REDIS_PASSWORD}}@${{valkey.RAILWAY_PRIVATE_DOMAIN}}:6379/0` |
| `CORS_ALLOW_ORIGIN` | `https://${{RAILWAY_PUBLIC_DOMAIN}}` |
| `DEFAULT_EXPIRY` | `1h` |
| `MAX_LENGTH` | `10000` |
| `RAILWAY_HEALTHCHECK_TIMEOUT_SEC` | `300` |
| `READ_ONLY` | optional, unset |
| `FORCE_ONETIME_SECRETS` | optional, unset |
| `FORCE_EXPIRATION` | optional, unset |
| `DISABLE_UPLOAD` | optional, unset |
| `MAX_FILE_SIZE` | optional, unset |
| `PUBLIC_URL` | optional, unset |
| `PRIVACY_NOTICE_URL` | optional, unset |
| `IMPRINT_URL` | optional, unset |
| `NO_LANGUAGE_SWITCHER` | optional, unset |

## Notes

- No wrapper: official `jhaals/yopass` (Apache-2.0) and `valkey/valkey` (BSD-3-Clause), both unmodified and digest-pinned.
- Yopass reads every flag from the environment without a prefix (`PORT`, `DATABASE`, `REDIS`, `FORCE_ONETIME_SECRETS`, ...). `DATABASE=redis` is required; the default backend is memcached on localhost.
- Valkey (not memcached, not Redis >= 7.4) so unread secrets survive redeploys: volume `/data`, `--appendonly yes`, generated `--requirepass`, `--maxmemory 256mb --maxmemory-policy volatile-ttl`. No `--bind`: the default `* -::*` covers Railway's IPv6 private network.
- Health check `/ready` (pings Valkey); `PORT=1337` = domain target port.
- Creation is public by design (no accounts). No front door: one SPA (hash routes) serves create and read, and Yopass's own creation auth is a paid licence feature. Bounded by the Valkey memory cap, `MAX_LENGTH`, 512 KB files, 1-week max TTL, and `CORS_ALLOW_ORIGIN` = own origin. `READ_ONLY`, `DISABLE_UPLOAD`, `FORCE_ONETIME_SECRETS`, `FORCE_EXPIRATION` are optional variables.
- Live e2e (HTTPS) on a clean-room deploy of the template: 38/38 flows (one-time read then 404, multi-read, delete, expiry options and validation, encrypted file, the official yopass CLI), secrets survived a yopass redeploy and a valkey redeploy (AOF reload), and a 1-hour secret returned 404 after one hour while a 1-week secret remained.
