#!/usr/bin/env bash
# shellcheck disable=SC2015  # `cond && pass || fail` is intentional; pass/fail always succeed
# Local smoke test: start the compose stack, run every product flow, then check expiry in Valkey.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"
BASE_URL="http://127.0.0.1:${YOPASS_TEST_PORT:-18337}"
CLI_DOCKER_NET="--network host"

cleanup() {
  local rc=$?
  if [ "$rc" -ne 0 ]; then compose logs --no-color --tail 80 || true; fi
  [ "${KEEP_STACK:-0}" = 1 ] || compose down -v --remove-orphans >/dev/null 2>&1 || true
  rm -rf "$TEST_TMP"
  exit "$rc"
}
trap cleanup EXIT

section "start"
compose down -v --remove-orphans >/dev/null 2>&1 || true
compose up -d --quiet-pull >/dev/null 2>&1 || compose up -d
wait_for_code "$BASE_URL/ready" 200 && pass "Yopass is ready" || die "Yopass did not become ready"

product_flows

section "expiry is enforced by the store (Valkey TTL)"
for t in 3600 86400 604800; do
  new_secret "ttl$t"
  id=$(create "ttl$t" "$t" false)
  ttl=$(vk TTL "$id" | tr -d '\r')
  if [ "$ttl" -gt $((t - 60)) ] && [ "$ttl" -le "$t" ]; then pass "a ${t}s secret is stored with TTL $ttl"; else fail "${t}s secret has TTL [$ttl]"; fi
done
# Simulate the passage of time: shorten the TTL of a live secret and confirm Yopass then reports it gone.
new_secret expiring
id=$(create expiring 3600 false)
assert_eq "fetchable before expiry" "200" "$(fetch "$id")"
vk PEXPIRE "$id" 1500 >/dev/null
sleep 3
assert_eq "gone once its TTL elapses" "404" "$(fetch "$id")"
assert_eq "status gone once its TTL elapses" "404" "$(http_code "$BASE_URL/secret/$id/status")"

section "store hardening"
assert_eq "Valkey requires a password" "NOAUTH" "$(compose exec -T valkey valkey-cli ping 2>&1 | grep -o NOAUTH | head -1)"
assert_eq "append-only persistence is on" "yes" "$(vk CONFIG GET appendonly | tail -1 | tr -d '\r')"
assert_eq "memory is capped" "268435456" "$(vk CONFIG GET maxmemory | tail -1 | tr -d '\r')"
assert_eq "eviction drops the soonest-expiring secrets first" "volatile-ttl" "$(vk CONFIG GET maxmemory-policy | tail -1 | tr -d '\r')"
assert_eq "Valkey listens on IPv4 and IPv6" "* -::*" "$(vk CONFIG GET bind | tail -1 | tr -d '\r')"

summary
