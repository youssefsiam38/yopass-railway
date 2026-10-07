# Maintenance

## Bumping Yopass or Valkey

1. Resolve the new multi-arch digest (`UPSTREAM.md`).
2. Update `compose.yaml`, `tests/lib.sh` (`YOPASS_IMAGE`), `UPSTREAM.md`, and `_audit/spec_yopass.py` (outside this repo).
3. Run `tests/static.sh`, `tests/smoke.sh`, `tests/persistence.sh`; push; wait for CI.
4. Point the template at the new image (`tplkit.patch_template(spec, <template id>)` – it re-verifies), deploy a
   clean-room project from the template and run `tests/railway-smoke.sh https://<domain>` plus the plant/verify
   redeploy check. Then delete the clean-room project.
5. Re-check upstream release notes for renamed flags (Yopass reads every flag from the environment with `-` → `_`,
   e.g. `--force-onetime-secrets` → `FORCE_ONETIME_SECRETS`).

## Rebuilding the template from scratch

`tplkit.skeleton(spec_yopass, 'yopass.json')` → `railway templates create` → `tplkit.patch_template` →
verify → clean-room deploy → live e2e → `templates publish` → delete the skeleton and clean-room projects.

## Gotchas specific to this template

- Yopass reads env vars **without a prefix** (`PORT`, `REDIS`, `DATABASE`), so Railway's `PORT` drives the listener.
- The default backend is memcached; `DATABASE=redis` is required, otherwise Yopass dials `localhost:11211`.
- `/create/secret` accepts only an **armored** OpenPGP message; `/create/file` accepts only **binary** OpenPGP
  (first byte is checked). Tests encrypt with `gpg --symmetric`, which the server and the official CLI accept.
- Expirations are only 3600, 86400 or 604800 seconds; anything else is a 400.
- Do not swap Valkey for memcached: memcached loses every unread secret on each redeploy.
- Do not pass `--bind` to Valkey: the default `* -::*` already covers Railway's IPv6 private network.
