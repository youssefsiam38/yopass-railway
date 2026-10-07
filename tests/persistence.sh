#!/usr/bin/env bash
# shellcheck disable=SC2015  # `cond && pass || fail` is intentional; pass/fail always succeed
# Persistence: unread secrets survive restarts of Yopass AND of Valkey (volume + append-only file);
# consumed one-time secrets stay gone; TTLs keep counting down (not reset).
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"
BASE_URL="http://127.0.0.1:${YOPASS_TEST_PORT:-18337}"

cleanup() {
  local rc=$?
  if [ "$rc" -ne 0 ]; then compose logs --no-color --tail 80 || true; fi
  compose down -v --remove-orphans >/dev/null 2>&1 || true
  rm -rf "$TEST_TMP"
  exit "$rc"
}
trap cleanup EXIT

section "start and plant secrets"
compose down -v --remove-orphans >/dev/null 2>&1 || true
compose up -d --quiet-pull >/dev/null 2>&1 || compose up -d
wait_for_code "$BASE_URL/ready" 200 || die "Yopass did not become ready"
new_secret keep;     keep=$(create keep 604800 false)
new_secret unread;   unread=$(create unread 86400 true)
new_secret consumed; consumed=$(create consumed 3600 true)
{ [ -n "$keep" ] && [ -n "$unread" ] && [ -n "$consumed" ]; } && pass "three secrets created" || die "could not create secrets"
assert_eq "consume the one-time secret" "200" "$(fetch "$consumed")"
ttl_before=$(vk TTL "$keep" | tr -d '\r')
sleep 3

section "restart Yopass only"
compose restart yopass >/dev/null
wait_for_code "$BASE_URL/ready" 200 || die "Yopass did not come back"
assert_eq "unread one-time secret still there (status)" "200" "$(http_code "$BASE_URL/secret/$unread/status")"

section "recreate both containers, keeping the volume"
compose down >/dev/null 2>&1
compose up -d >/dev/null 2>&1
wait_for_code "$BASE_URL/ready" 200 || die "Yopass did not come back"
assert_eq "multi-read secret survived" "200" "$(fetch "$keep")"
decrypts_to keep && pass "it still decrypts to the original" || fail "decrypt mismatch after restart"
assert_eq "unread one-time secret survived" "200" "$(fetch "$unread")"
decrypts_to unread && pass "it still decrypts to the original" || fail "decrypt mismatch after restart"
assert_eq "...and is consumed by that read" "404" "$(fetch "$unread")"
assert_eq "the consumed secret is still gone" "404" "$(fetch "$consumed")"
ttl_after=$(vk TTL "$keep" | tr -d '\r')
if [ "$ttl_after" -lt "$ttl_before" ] && [ "$ttl_after" -gt $((ttl_before - 300)) ]; then
  pass "the TTL kept counting down across the restart ($ttl_before -> $ttl_after)"
else fail "TTL not preserved ($ttl_before -> $ttl_after)"; fi

summary
