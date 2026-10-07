#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016
# Static validation: syntax, shellcheck, compose shape, image pins and configuration. No containers started.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
cd "$REPO_ROOT"
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"
trap 'rm -rf "$TEST_TMP"' EXIT

section "syntax"
for f in tests/*.sh; do
  if bash -n "$f" 2>/dev/null; then pass "parses: $f"; else fail "syntax error: $f"; fi
done
for f in tests/*.sh; do
  [ -x "$f" ] && pass "executable: $f" || fail "not executable: $f"
done

section "shellcheck"
if command -v shellcheck >/dev/null; then
  if shellcheck -x -s bash tests/*.sh; then pass "shellcheck tests"; else fail "shellcheck tests"; fi
else
  echo "  SKIP  shellcheck not installed"
fi

section "compose"
if docker compose -f compose.yaml config -q; then pass "compose config"; else fail "compose config"; fi
cfg=$(docker compose -f compose.yaml config --format json)
assert_eq "two services" "valkey yopass" "$(jq -r '[.services | keys[]] | sort | join(" ")' <<<"$cfg")"
assert_eq "only yopass publishes a port, on loopback" "127.0.0.1" "$(jq -r '[.services[].ports[]? | .host_ip] | join(" ")' <<<"$cfg")"
assert_eq "yopass listens on 1337" "1337" "$(jq -r '.services.yopass.ports[0].target' <<<"$cfg")"
assert_eq "the Valkey volume is mounted at /data" "/data" "$(jq -r '[.services.valkey.volumes[]? | .target] | join(" ")' <<<"$cfg")"
assert_contains "the Yopass image is official and pinned by digest" \
  '^jhaals/yopass:[0-9.]*@sha256:[0-9a-f]\{64\}$' "$(jq -r '.services.yopass.image' <<<"$cfg")"
assert_contains "the Valkey image is official and pinned by digest" \
  '^valkey/valkey:[0-9.]*-alpine@sha256:[0-9a-f]\{64\}$' "$(jq -r '.services.valkey.image' <<<"$cfg")"
assert_eq "the test image pin matches compose" "$(jq -r '.services.yopass.image' <<<"$cfg")" "$YOPASS_IMAGE"

section "configuration"
y=$(jq -r '.services.yopass.environment' <<<"$cfg")
assert_eq "PORT" "1337" "$(jq -r .PORT <<<"$y")"
assert_eq "Redis backend" "redis" "$(jq -r .DATABASE <<<"$y")"
assert_contains "the Redis URL carries the password" '^redis://default:[^@]*@valkey:6379/0$' "$(jq -r .REDIS <<<"$y")"
assert_contains "CORS is restricted to the app's own origin" '^http://127.0.0.1:' "$(jq -r .CORS_ALLOW_ORIGIN <<<"$y")"
vcmd=$(jq -r '.services.valkey.command | join(" ")' <<<"$cfg")
assert_contains "Valkey requires a password" '--requirepass' "$vcmd"
assert_contains "Valkey persists with an append-only file" '--appendonly yes' "$vcmd"
assert_contains "Valkey memory is capped" '--maxmemory ' "$vcmd"
assert_contains "eviction is volatile-ttl" '--maxmemory-policy volatile-ttl' "$vcmd"
assert_not_contains "Valkey is not bound to IPv4 only" '--bind' "$vcmd"
assert_contains "the compose Valkey password is a placeholder" 'local-test-only' "$(jq -r '.services.valkey.environment.REDIS_PASSWORD' <<<"$cfg")"

section "docs"
for f in README.md ARCHITECTURE.md SECURITY.md UPSTREAM.md THIRD_PARTY_NOTICES.md MAINTENANCE.md MARKETPLACE_AUDIT.md marketplace/OVERVIEW.md assets/icon.png licenses/YOPASS-LICENSE licenses/VALKEY-LICENSE LICENSE; do
  [ -s "$f" ] && pass "present: $f" || fail "missing: $f"
done
assert_contains "OVERVIEW has the required Deployment Dependencies heading" '^### Deployment Dependencies' "$(cat marketplace/OVERVIEW.md)"
digest=$(jq -r '.services.yopass.image' <<<"$cfg" | sed 's/.*@//')
assert_contains "UPSTREAM.md records the pinned Yopass digest" "$digest" "$(cat UPSTREAM.md)"

section "secrets hygiene"
mapfile -t tracked < <(git ls-files 2>/dev/null | grep . || find . -type f -not -path './.git/*')
if [ "${#tracked[@]}" -gt 0 ] && grep -lE '(sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{30,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----)' "${tracked[@]}" 2>/dev/null; then
  fail "a credential-shaped string is in the repository"
else
  pass "no credential-shaped strings in ${#tracked[@]} files"
fi

summary
