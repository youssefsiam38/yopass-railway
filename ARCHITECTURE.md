# Architecture

```
            HTTPS (Railway edge)
                    │
          ┌─────────▼──────────┐
          │ yopass  :1337      │  official jhaals/yopass image, unmodified
          │ web app + API      │  health: /ready (pings Valkey)
          └─────────┬──────────┘
                    │ redis://default:<generated>@valkey.railway.internal:6379/0  (private, IPv6)
          ┌─────────▼──────────┐
          │ valkey  :6379      │  valkey/valkey alpine, requirepass, appendonly yes,
          │ volume /data       │  maxmemory 256mb, maxmemory-policy volatile-ttl
          └────────────────────┘
```

## Why this shape

- **No wrapper.** Yopass is configured entirely from environment variables (viper `AutomaticEnv`: `PORT`, `DATABASE`,
  `REDIS`, …), it has no accounts or admin to bootstrap, and it listens on all interfaces (Go `:1337`), so the stock
  image runs unmodified.
- **Valkey instead of memcached.** memcached keeps everything in RAM, so every redeploy or restart would silently
  destroy every unread secret. Valkey with a volume and an append-only file keeps unread secrets (and their remaining
  TTL) across redeploys. Valkey is the BSD-licensed, Redis-compatible fork; Yopass's `redis` backend (go-redis) speaks to it
  unchanged. (Redis 7.4+ is not under an OSI licence, so it is not bundled.)
- **IPv6 private network.** Railway's private network is IPv6-only. The Valkey image's default bind is `* -::*`
  (IPv4 and IPv6), so no `--bind` is passed; go-redis resolves the AAAA record of `valkey.railway.internal`.
- **Expiry lives in the store.** Yopass writes each secret with a Valkey TTL equal to the chosen expiry
  (3600 / 86400 / 604800 s). Expiry therefore needs no Yopass process running, and a TTL keeps counting down across
  restarts.
- **One-time reads are atomic.** Yopass claims one-time secrets with WATCH/MULTI on Valkey, so two racing readers
  cannot both get the ciphertext.
- **Health.** `/ready` returns 200 only when Valkey answers, so a deploy is not marked healthy until the store is
  reachable. `PORT=1337` equals the domain's target port.

## Start command (valkey)

```
sh -c 'exec docker-entrypoint.sh valkey-server --requirepass "$REDIS_PASSWORD" --appendonly yes \
       --maxmemory "${VALKEY_MAXMEMORY:-256mb}" --maxmemory-policy volatile-ttl'
```

The image entrypoint chowns the root-owned Railway volume to the `valkey` user and drops privileges.
