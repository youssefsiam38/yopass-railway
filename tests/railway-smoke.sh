#!/usr/bin/env bash
# shellcheck disable=SC2015  # `cond && pass || fail` is intentional; pass/fail always succeed
# Live end-to-end test against a deployed Yopass over HTTPS.
#
#   tests/railway-smoke.sh https://<domain>                       every product flow (default MODE=flows)
#   MODE=plant   STATE_DIR=dir tests/railway-smoke.sh https://…   plant secrets before a redeploy
#   MODE=verify  STATE_DIR=dir tests/railway-smoke.sh https://…   after a redeploy: unread secrets survived
#   MODE=final   STATE_DIR=dir tests/railway-smoke.sh https://…   read the surviving one-time secret, then gone
#   MODE=expired STATE_DIR=dir tests/railway-smoke.sh https://…   >= 1 hour after plant: the 1h secret is gone
#
# STATE_DIR holds the test passphrases/plaintexts (mode 600); nothing secret is printed.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
BASE_URL=${1:?usage: tests/railway-smoke.sh https://<domain>}
BASE_URL=${BASE_URL%/}
MODE=${MODE:-flows}
if [ "$MODE" != flows ]; then
  : "${STATE_DIR:?STATE_DIR is required for MODE=$MODE}"
  mkdir -p "$STATE_DIR"; TEST_TMP=$STATE_DIR
fi
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"
case "$BASE_URL" in https://*) ;; *) die "use the https:// URL";; esac

ids() { cat "$STATE_DIR/ids.json"; }
id_of() { jq -r --arg k "$1" '.[$k]' "$STATE_DIR/ids.json"; }

case "$MODE" in
  flows)
    trap 'rm -rf "$TEST_TMP"' EXIT
    section "HTTPS edge"
    assert_eq "plain HTTP is redirected or refused" "true" \
      "$(c=$(http_code "http://${BASE_URL#https://}/"); [ "$c" = 301 ] || [ "$c" = 302 ] || [ "$c" = 308 ] || [ "$c" = 000 ] && echo true || echo "$c")"
    product_flows
    ;;
  plant)
    section "plant secrets"
    wait_for_code "$BASE_URL/ready" 200 60 || die "not ready"
    new_secret keep;     keep=$(create keep 604800 false)
    new_secret unread;   unread=$(create unread 86400 true)
    new_secret consumed; consumed=$(create consumed 3600 true)
    new_secret short;    short=$(create short 3600 false)
    { [ -n "$keep" ] && [ -n "$unread" ] && [ -n "$consumed" ] && [ -n "$short" ]; } && pass "four secrets created" || die "create failed"
    assert_eq "consume the one-time secret" "200" "$(fetch "$consumed")"
    assert_eq "the 1h secret is readable now" "200" "$(fetch "$short")"
    jq -n --arg keep "$keep" --arg unread "$unread" --arg consumed "$consumed" --arg short "$short" \
      --arg at "$(date +%s)" '{keep:$keep,unread:$unread,consumed:$consumed,short:$short,planted_at:($at|tonumber)}' >"$STATE_DIR/ids.json"
    pass "state written to STATE_DIR"
    ;;
  verify)
    section "after redeploy"
    wait_for_code "$BASE_URL/ready" 200 300 && pass "ready" || die "not ready"
    assert_eq "multi-read secret survived" "200" "$(fetch "$(id_of keep)")"
    decrypts_to keep && pass "it decrypts to the original" || fail "decrypt mismatch"
    assert_eq "unread one-time secret survived (status, not consumed)" "200" "$(http_code "$BASE_URL/secret/$(id_of unread)/status")"
    assert_eq "consumed one-time secret is still gone" "404" "$(fetch "$(id_of consumed)")"
    ;;
  final)
    section "read the surviving one-time secret"
    assert_eq "fetch" "200" "$(fetch "$(id_of unread)")"
    decrypts_to unread && pass "it decrypts to the original" || fail "decrypt mismatch"
    assert_eq "second fetch fails (one-time)" "404" "$(fetch "$(id_of unread)")"
    ;;
  expired)
    section "expiry honoured"
    age=$(( $(date +%s) - $(ids | jq -r .planted_at) ))
    [ "$age" -ge 3600 ] || die "only ${age}s since plant; wait until >= 3600"
    pass "${age}s since the 1h secret was created"
    assert_eq "the 1h secret is gone" "404" "$(fetch "$(id_of short)")"
    assert_eq "its status is gone" "404" "$(http_code "$BASE_URL/secret/$(id_of short)/status")"
    assert_eq "the 1-week secret is still there" "200" "$(http_code "$BASE_URL/secret/$(id_of keep)/status")"
    ;;
  *) die "unknown MODE=$MODE";;
esac

summary
