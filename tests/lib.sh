#!/usr/bin/env bash
# shellcheck disable=SC2015  # `cond && pass || fail` is intentional; pass/fail always succeed
# Shared helpers for yopass-railway tests. Source this file; do not execute it.
# Secrets are encrypted client-side with gpg (OpenPGP, symmetric), exactly like the Yopass web client
# does with OpenPGP.js. Decryption keys and plaintexts live in mode-600 temp files and are never printed.

: "${BASE_URL:=http://127.0.0.1:18337}"
: "${TEST_TIMEOUT:=180}"
: "${YOPASS_IMAGE:=jhaals/yopass:14.10.0@sha256:6c33d9c813f77bae70787e1bce76710840ff654f454998b01f8dacc0a7988fd3}"

TEST_TMP="${TEST_TMP:-$(mktemp -d)}"
chmod 700 "$TEST_TMP"
export TEST_TMP
export GNUPGHOME="$TEST_TMP/gnupg"
mkdir -p "$GNUPGHOME" && chmod 700 "$GNUPGHOME"
umask 077
_PASS=0; _FAIL=0

pass() { _PASS=$((_PASS+1)); printf '  PASS  %s\n' "$*"; }
fail() { _FAIL=$((_FAIL+1)); printf '  FAIL  %s\n' "$*" >&2; }
die()  { printf 'FATAL: %s\n' "$*" >&2; exit 1; }
section() { printf '\n== %s ==\n' "$*"; }
summary() { printf '\n%d passed, %d failed\n' "$_PASS" "$_FAIL"; [ "$_FAIL" -eq 0 ]; }

assert_eq() { if [ "$2" = "$3" ]; then pass "$1 ($3)"; else fail "$1: expected [$2] got [$3]"; fi; }
assert_contains() { if grep -q -- "$2" <<<"$3"; then pass "$1"; else fail "$1: missing [$2]"; fi; }
assert_not_contains() { if grep -q -- "$2" <<<"$3"; then fail "$1: found forbidden [$2]"; else pass "$1"; fi; }

http_code() { curl -s -o /dev/null -w '%{http_code}' --max-time 30 "$@"; }

wait_for_code() {
  local url=$1 want=$2 timeout=${3:-$TEST_TIMEOUT} start code
  start=$(date +%s)
  while :; do
    code=$(http_code "$url" || true)
    [ "$code" = "$want" ] && return 0
    if [ $(( $(date +%s) - start )) -ge "$timeout" ]; then printf 'timed out waiting for %s -> %s (last %s)\n' "$url" "$want" "$code" >&2; return 1; fi
    sleep 2
  done
}

# new_secret NAME -> creates $TEST_TMP/NAME.{key,plain}: a random passphrase and a random plaintext.
new_secret() {
  head -c 24 /dev/urandom | base64 | tr -d '/+=' >"$TEST_TMP/$1.key"
  printf 'yopass-railway test %s %s' "$1" "$(head -c 12 /dev/urandom | base64 | tr -d '/+=')" >"$TEST_TMP/$1.plain"
}

# encrypt NAME -> armored OpenPGP message of NAME.plain (symmetric, passphrase NAME.key) on stdout
encrypt() {
  gpg --batch --quiet --yes --pinentry-mode loopback --passphrase-file "$TEST_TMP/$1.key" \
    --symmetric --armor --output - "$TEST_TMP/$1.plain"
}

# body NAME EXPIRATION_SECONDS ONE_TIME(true|false) -> writes $TEST_TMP/NAME.body (the create request)
body() {
  encrypt "$1" >"$TEST_TMP/$1.asc"
  jq -n --rawfile m "$TEST_TMP/$1.asc" --argjson e "$2" --argjson o "$3" \
    '{message:$m, expiration:$e, one_time:$o}' >"$TEST_TMP/$1.body"
}

# post_create FILE -> "HTTP_CODE BODY" for POST /create/secret with FILE as the JSON body
post_create() {
  curl -s -w '\n%{http_code}' --max-time 30 -X POST -H 'Content-Type: application/json' \
    --data-binary "@$1" "$BASE_URL/create/secret"
}

# create NAME EXPIRATION_SECONDS ONE_TIME -> prints the secret id (empty on failure)
create() {
  local out
  body "$1" "$2" "$3"
  out=$(post_create "$TEST_TMP/$1.body" || true)
  [ "${out##*$'\n'}" = "200" ] || return 0
  jq -r '.message // empty' <<<"${out%$'\n'*}"
}

# fetch ID -> HTTP status of GET /secret/ID; the response body lands in $TEST_TMP/fetch.json
fetch() { curl -s -o "$TEST_TMP/fetch.json" -w '%{http_code}' --max-time 30 "$BASE_URL/secret/$1"; }

# decrypts_to NAME -> succeeds when $TEST_TMP/fetch.json decrypts with NAME.key to NAME.plain
decrypts_to() {
  jq -r '.message' "$TEST_TMP/fetch.json" >"$TEST_TMP/$1.got.asc" &&
    gpg --batch --quiet --yes --pinentry-mode loopback --passphrase-file "$TEST_TMP/$1.key" \
      --decrypt --output "$TEST_TMP/$1.got" "$TEST_TMP/$1.got.asc" 2>/dev/null &&
    cmp -s "$TEST_TMP/$1.got" "$TEST_TMP/$1.plain"
}

# The product flows shared by the local smoke test and the live HTTPS test.
product_flows() {
  local code page cfg id id2 t

  section "web app and health"
  assert_eq "GET /health" "200" "$(http_code "$BASE_URL/health")"
  assert_eq "GET /ready (Valkey reachable)" "200" "$(http_code "$BASE_URL/ready")"
  page=$(curl -s --max-time 30 "$BASE_URL/")
  assert_contains "the web app is served" '<div id="root">' "$page"
  assert_contains "the web app loads its bundle" '<script' "$page"
  t=$(curl -s -D - -o /dev/null --max-time 30 "$BASE_URL/")
  grep -qi '^content-security-policy:' <<<"$t" && pass "a Content-Security-Policy header is sent" || fail "no Content-Security-Policy header"
  cfg=$(curl -s --max-time 30 "$BASE_URL/config")
  assert_eq "creation is enabled (READ_ONLY false)" "false" "$(jq -r '.READ_ONLY' <<<"$cfg")"
  assert_eq "default expiry is 1 hour" "3600" "$(jq -r '.DEFAULT_EXPIRY' <<<"$cfg")"

  section "one-time secret: create via API, fetch once, then gone"
  new_secret onetime
  id=$(create onetime 3600 true)
  if [ -n "$id" ]; then pass "secret created (id length ${#id})"; else fail "secret was not created"; fi
  assert_eq "status before read" '{"oneTime":true,"requireAuth":false}' "$(curl -s --max-time 30 "$BASE_URL/secret/$id/status")"
  assert_eq "status does not consume it (still 200)" "200" "$(http_code "$BASE_URL/secret/$id/status")"
  assert_eq "first fetch" "200" "$(fetch "$id")"
  assert_not_contains "the server only stores ciphertext" "$(cat "$TEST_TMP/onetime.plain")" "$(cat "$TEST_TMP/fetch.json")"
  assert_contains "the stored message is an OpenPGP message" 'BEGIN PGP MESSAGE' "$(cat "$TEST_TMP/fetch.json")"
  decrypts_to onetime && pass "the fetched ciphertext decrypts client-side to the original plaintext" \
    || fail "the fetched ciphertext did not decrypt to the original plaintext"
  assert_eq "second fetch fails (one-time)" "404" "$(fetch "$id")"
  assert_eq "status after read" "404" "$(http_code "$BASE_URL/secret/$id/status")"

  section "multi-read secret and early deletion"
  new_secret multi
  id2=$(create multi 86400 false)
  [ -n "$id2" ] && pass "multi-read secret created" || fail "multi-read secret was not created"
  assert_eq "first fetch" "200" "$(fetch "$id2")"
  assert_eq "second fetch still works (not one-time)" "200" "$(fetch "$id2")"
  decrypts_to multi && pass "it decrypts to the original plaintext" || fail "multi-read decrypt mismatch"
  assert_eq "DELETE removes it early" "204" "$(http_code -X DELETE "$BASE_URL/secret/$id2")"
  assert_eq "fetch after DELETE" "404" "$(fetch "$id2")"

  section "expiry options and validation"
  for t in 3600 86400 604800; do
    new_secret "exp$t"
    id=$(create "exp$t" "$t" true)
    [ -n "$id" ] && pass "expiration $t s accepted" || fail "expiration $t s rejected"
  done
  new_secret badexp
  body badexp 120 true
  code=$(post_create "$TEST_TMP/badexp.body"); code=${code##*$'\n'}
  assert_eq "an unsupported expiration (120 s) is rejected" "400" "$code"
  jq -n '{message:"plaintext, not encrypted", expiration:3600, one_time:true}' >"$TEST_TMP/plain.body"
  code=$(post_create "$TEST_TMP/plain.body"); code=${code##*$'\n'}
  assert_eq "a non-OpenPGP (unencrypted) message is rejected" "400" "$code"
  head -c 30000 /dev/zero | tr '\0' 'A' >"$TEST_TMP/big.plain"
  jq -n --rawfile m "$TEST_TMP/big.plain" '{message:$m, expiration:3600, one_time:true}' >"$TEST_TMP/big.body"
  code=$(post_create "$TEST_TMP/big.body"); code=${code##*$'\n'}
  if [ "$code" = 400 ] || [ "$code" = 413 ]; then pass "an oversized message is rejected ($code)"; else fail "oversized message: got $code"; fi
  assert_eq "an unknown id is 404" "404" "$(fetch "AAAAAAAAAAAAAAAAAAAAAA")"

  section "file secret"
  new_secret file
  # files are uploaded as binary OpenPGP (the web client does the same)
  gpg --batch --quiet --yes --pinentry-mode loopback --passphrase-file "$TEST_TMP/file.key" \
    --symmetric --output "$TEST_TMP/file.gpg" "$TEST_TMP/file.plain"
  code=$(curl -s -o "$TEST_TMP/file.resp" -w '%{http_code}' --max-time 60 -X POST \
    -H 'Content-Type: application/octet-stream' -H 'X-Yopass-Expiration: 3600' -H 'X-Yopass-OneTime: true' \
    --data-binary "@$TEST_TMP/file.gpg" "$BASE_URL/create/file")
  id=$(jq -r '.message // empty' "$TEST_TMP/file.resp" 2>/dev/null || true)
  if [ "$code" = 200 ] && [ -n "$id" ]; then
    pass "encrypted file uploaded"
    assert_eq "file download" "200" "$(curl -s -o "$TEST_TMP/file.dl" -w '%{http_code}' --max-time 60 "$BASE_URL/file/$id")"
    if gpg --batch --quiet --yes --pinentry-mode loopback --passphrase-file "$TEST_TMP/file.key" \
        --decrypt --output - "$TEST_TMP/file.dl" 2>/dev/null | cmp -s - "$TEST_TMP/file.plain"; then
      pass "the downloaded file decrypts to the original"
    else fail "file decrypt mismatch"; fi
    assert_eq "second file download fails (one-time)" "404" "$(http_code "$BASE_URL/file/$id")"
  else
    fail "file upload failed ($code)"
  fi

  section "the official yopass CLI client"
  if [ "${SKIP_CLI:-0}" = 1 ] || ! command -v docker >/dev/null; then
    echo "  SKIP  CLI leg (SKIP_CLI=1 or no docker)"
  else
    new_secret cli
    # shellcheck disable=SC2086
    if docker run -i --rm ${CLI_DOCKER_NET:-} --entrypoint /yopass "$YOPASS_IMAGE" --api "$BASE_URL" --url "$BASE_URL" \
         --expiration 1h --one-time <"$TEST_TMP/cli.plain" >"$TEST_TMP/cli.url" 2>/dev/null; then
      pass "the CLI encrypted and stored a secret"
      assert_contains "the CLI returned a link on this instance" "^$BASE_URL/#/s/" "$(sed -E 's/#\/s\/([^/]+)\/.*/#\/s\/\1\//' "$TEST_TMP/cli.url")"
      # shellcheck disable=SC2086
      docker run --rm ${CLI_DOCKER_NET:-} --entrypoint /yopass "$YOPASS_IMAGE" --api "$BASE_URL" --url "$BASE_URL" \
        --decrypt "$(cat "$TEST_TMP/cli.url")" >"$TEST_TMP/cli.got" 2>/dev/null || true
      cmp -s "$TEST_TMP/cli.got" "$TEST_TMP/cli.plain" && pass "the CLI decrypted its own link" || fail "CLI decrypt mismatch"
      # shellcheck disable=SC2086
      if docker run --rm ${CLI_DOCKER_NET:-} --entrypoint /yopass "$YOPASS_IMAGE" --api "$BASE_URL" --url "$BASE_URL" \
          --decrypt "$(cat "$TEST_TMP/cli.url")" >/dev/null 2>&1; then
        fail "the CLI link decrypted twice"
      else pass "the CLI link fails the second time (one-time)"; fi
    else
      fail "the CLI could not store a secret"
    fi
  fi
}

compose() { docker compose -f "$REPO_ROOT/compose.yaml" "$@"; }
# vk ARGS... -> valkey-cli inside the local valkey container (password from its env, never printed)
# shellcheck disable=SC2016  # expanded inside the container
vk() { compose exec -T valkey sh -c 'REDISCLI_AUTH="$REDIS_PASSWORD" valkey-cli --no-auth-warning "$@"' vk "$@"; }
