#!/bin/bash
# =============================================================================
# AFP script tests
# =============================================================================
#
# Offline (default): validation, error mapping and configuration. Needs no
# store; requests go to a closed port.
#
# Live (--live): a full round trip against a real S3 store such as Garage. Uses
# object paths under skilltest/<run-id>/ only and removes what it creates.
#
# Usage:
#   tests/run-tests.sh
#   AFP_TEST_KEYFILE=~/spike.keys tests/run-tests.sh --live
#
# Live settings (environment):
#   AFP_TEST_KEYFILE   file with GARAGE_DEFAULT_ACCESS_KEY= and GARAGE_DEFAULT_SECRET_KEY= lines (required)
#   AFP_TEST_ENDPOINT  default http://100.76.17.128:3900
#   AFP_TEST_BUCKET    default afp-spike
#   AFP_TEST_REGION    default garage
#
# =============================================================================

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SC="$ROOT/scripts"
PASS=0
FAIL=0
LIVE=false
[ "${1:-}" = "--live" ] && LIVE=true

T=$(mktemp -d "${TMPDIR:-/tmp}/afp-tests.XXXXXX")
cleanup() { rm -rf "$T"; }
trap cleanup EXIT

export AFP_HOME="$T/home"
export AFP_OWNER="tester@example.local"
export AFP_CONNECT_TIMEOUT=3

OUT=""; RC=0

pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL $1${2:+ ($2)}"; }

# run <cmd...>: stdout to OUT, exit status to RC. stderr is dropped.
run() { OUT=$("$@" 2>/dev/null </dev/null); RC=$?; }

# is_json: OUT is exactly one JSON value.
is_json() { printf '%s' "$OUT" | jq -e . >/dev/null 2>&1; }

# expect_err <name> <code> <cmd...>
expect_err() {
    local name="$1" code="$2"; shift 2
    run "$@"
    local got
    got=$(printf '%s' "$OUT" | jq -r '.error.code // empty' 2>/dev/null)
    if [ "$RC" -ne 0 ] && [ "$got" = "$code" ] && [ "$(printf '%s' "$OUT" | jq -r '.ok')" = "false" ]; then pass "$name"
    else fail "$name" "wanted error ${code}, got rc=${RC} code='${got}'"; fi
}

# expect_ok <name> <cmd...>
expect_ok() {
    local name="$1"; shift
    run "$@"
    if [ "$RC" -eq 0 ] && [ "$(printf '%s' "$OUT" | jq -r '.ok' 2>/dev/null)" = "true" ]; then pass "$name"
    else fail "$name" "rc=${RC} out=$(printf '%s' "$OUT" | head -c 200)"; fi
}

# jq_is <name> <filter> <expected>: compare a field of OUT
jq_is() {
    local got
    got=$(printf '%s' "$OUT" | jq -r "$2" 2>/dev/null)
    if [ "$got" = "$3" ]; then pass "$1"; else fail "$1" "wanted '$3', got '${got}'"; fi
}

assert() { # <name> <command...>
    local name="$1"; shift
    if "$@" >/dev/null 2>&1; then pass "$name"; else fail "$name"; fi
}

echo "AFP tests ($(/bin/bash --version | head -1 | sed 's/version //'))"

# -----------------------------------------------------------------------------
echo "== configuration"
printf 'not-a-real-secret' | "$SC/afp-config.sh" add dead --endpoint http://127.0.0.1:9 --bucket nothing-here \
    --access-key GKtest --secret-stdin --default >/dev/null 2>&1
assert "config file exists" test -f "$AFP_HOME/spaces.json"
assert "config file is mode 600" test "$(stat -f '%Lp' "$AFP_HOME/spaces.json" 2>/dev/null || stat -c '%a' "$AFP_HOME/spaces.json")" = "600"
run "$SC/afp-config.sh" list
jq_is "list shows the default space" '.default' "dead"
jq_is "list marks the secret as stored, not shown" '.spaces.dead.secret' "inline"
case "$OUT" in *not-a-real-secret*) fail "list output has no secret" ;; *) pass "list output has no secret" ;; esac
expect_err "add rejects a bad space name" invalid_space "$SC/afp-config.sh" add Bad_Name --endpoint http://x:1 --bucket abc --access-key K --secret-key S
expect_err "add rejects a non-http endpoint" usage "$SC/afp-config.sh" add ok1 --endpoint ftp://x --bucket abcd --access-key K --secret-key S
expect_err "add needs a secret" usage "$SC/afp-config.sh" add ok2 --endpoint http://x:1 --bucket abcd --access-key K
expect_ok "add a second space with limited capabilities" "$SC/afp-config.sh" add nolink --endpoint http://127.0.0.1:9 --bucket nothing-here --access-key GKtest --secret-key sekret --capabilities ui
expect_ok "set the default" "$SC/afp-config.sh" default nolink
expect_ok "remove a space" "$SC/afp-config.sh" remove nolink
expect_err "remove an unknown space" invalid_space "$SC/afp-config.sh" remove nolink
run "$SC/afp-config.sh" list
jq_is "removing the default clears it" '.default' ""
expect_ok "restore the default" "$SC/afp-config.sh" default dead
expect_ok "re-add the limited space" "$SC/afp-config.sh" add nolink --endpoint http://127.0.0.1:9 --bucket nothing-here --access-key GKtest --secret-key sekret --capabilities ui

# -----------------------------------------------------------------------------
echo "== validation happens before any request"
echo "hello" > "$T/f.txt"
for P in '../x' 'a/../b' '/abs' 'a//b' 'a%2Fb' 'a/%2e%2e/b' 'a/./b' 'x.afp.json' 'a b' 'a\b' 'a?b' 'a:b'; do
    expect_err "put rejects path '$P'" invalid_path "$SC/afp-put.sh" "$T/f.txt" --path "$P"
done
LONG=$(printf 'a%.0s' $(seq 1 600))
expect_err "put rejects a 600 character path" invalid_path "$SC/afp-put.sh" "$T/f.txt" --path "$LONG"
for N in 'Bad_Name' 'a/b' '-x' 'UPPER' 'a..b' 'sp ace'; do
    expect_err "put rejects space '$N'" invalid_space "$SC/afp-put.sh" "$T/f.txt" --space "$N" --path ok.txt
done
for R in 'afp://dead/../x' 'afp://dead//x' 'afp://dead/a%2Fb' 'afp://dead/%2e%2e/x' 'notaref' 'afp://dead' 'afp:///x'; do
    expect_err "get rejects reference '$R'" invalid_path "$SC/afp-get.sh" "$R"
done
expect_err "get rejects a bad space in a reference" invalid_space "$SC/afp-get.sh" "afp://Bad_Space/x"
expect_err "ls rejects a bad prefix" invalid_path "$SC/afp-ls.sh" --prefix '../x'
expect_err "rm rejects a bad reference" invalid_path "$SC/afp-rm.sh" "afp://dead/../x"
expect_err "link rejects a bad reference" invalid_path "$SC/afp-link.sh" "afp://dead/a%2Fb"
expect_err "put rejects a bad ttl" usage "$SC/afp-put.sh" "$T/f.txt" --path ok.txt --ttl soon
expect_err "put rejects an unknown option" usage "$SC/afp-put.sh" "$T/f.txt" --nope
expect_err "put needs a file" usage "$SC/afp-put.sh"
expect_err "put reports a missing file" not_found "$SC/afp-put.sh" "$T/nope.txt"
expect_err "get rejects a malformed digest" usage "$SC/afp-get.sh" afp://dead/x.txt --digest abc
expect_err "get rejects a reference with a short digest" usage "$SC/afp-get.sh" '{"ref":"afp://dead/x.txt","digest":"sha256:abc"}'
dd if=/dev/zero of="$T/huge.bin" bs=1 count=0 seek=6442450944 2>/dev/null
expect_err "put refuses a file over 5 GiB before any request" too_large "$SC/afp-put.sh" "$T/huge.bin" --path huge.bin
rm -f "$T/huge.bin"

# -----------------------------------------------------------------------------
echo "== error mapping"
expect_err "put to a closed port is unreachable" unreachable "$SC/afp-put.sh" "$T/f.txt" --path ok.txt
expect_err "get from a closed port is unreachable" unreachable "$SC/afp-get.sh" afp://dead/ok.txt --digest sha256:0000000000000000000000000000000000000000000000000000000000000000
expect_err "ls on a closed port is unreachable" unreachable "$SC/afp-ls.sh"
expect_err "rm on a closed port is unreachable" unreachable "$SC/afp-rm.sh" afp://dead/ok.txt
expect_err "link on a closed port is unreachable" unreachable "$SC/afp-link.sh" afp://dead/ok.txt
expect_err "capabilities --probe on a closed port is unreachable" unreachable "$SC/afp-capabilities.sh" --probe
expect_ok "capabilities without --probe answers from config" "$SC/afp-capabilities.sh"
expect_err "link on a space without the link capability is unsupported" unsupported "$SC/afp-link.sh" afp://nolink/ok.txt
expect_err "get of an unknown space without a link is invalid_space" invalid_space "$SC/afp-get.sh" afp://elsewhere/ok.txt
expect_err "get through an unreachable link is unreachable" unreachable "$SC/afp-get.sh" '{"ref":"afp://elsewhere/ok.txt","digest":"sha256:0000000000000000000000000000000000000000000000000000000000000000","url":"http://127.0.0.1:9/x"}'
expect_err "get refuses a link that is not plain http(s)" usage "$SC/afp-get.sh" '{"ref":"afp://elsewhere/ok.txt","digest":"sha256:0000000000000000000000000000000000000000000000000000000000000000","url":"file:///etc/passwd"}'
run "$SC/afp-put.sh" "$T/f.txt" --path ok.txt
assert "an error is one JSON object on stdout" is_json
case "$OUT" in *not-a-real-secret*) fail "the secret never appears in an error" ;; *) pass "the secret never appears in an error" ;; esac

# -----------------------------------------------------------------------------
echo "== helper functions"
# shellcheck disable=SC1090
( . "$SC/afp-helper.sh"
  [ "$(afp_hmac_sha256_hex "$(printf 'key' | od -An -v -tx1 | tr -d ' \n')" 'The quick brown fox jumps over the lazy dog')" = "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8" ] ) \
    && pass "HMAC-SHA256 matches the RFC test vector" || fail "HMAC-SHA256 matches the RFC test vector"
( . "$SC/afp-helper.sh"
  key=$(printf 'k%.0s' $(seq 1 100))
  mine=$(afp_hmac_sha256_hex "$(printf '%s' "$key" | od -An -v -tx1 | tr -d ' \n')" 'hello')
  ref=$(printf '%s' hello | openssl dgst -sha256 -hmac "$key" | awk '{print $NF}')
  [ -n "$mine" ] && [ "$mine" = "$ref" ] ) \
    && pass "HMAC handles keys longer than the block size" || fail "HMAC handles keys longer than the block size"
( . "$SC/afp-helper.sh"
  [ "$(afp_sanitize_filename '../../etc/pass wd?.txt')" = "pass_wd_.txt" ] && [ "$(afp_sanitize_filename 'CON.txt')" = "_CON.txt" ] ) \
    && pass "filenames are sanitized like AMP attachments" || fail "filenames are sanitized like AMP attachments"

if [ "$LIVE" != true ]; then
    echo ""
    echo "Offline: ${PASS} passed, ${FAIL} failed (run with --live for the store round trip)"
    [ "$FAIL" -eq 0 ]; exit $?
fi

# =============================================================================
echo "== live round trip"
[ -r "${AFP_TEST_KEYFILE:-}" ] || { echo "AFP_TEST_KEYFILE must point at a readable key file"; exit 2; }
EP="${AFP_TEST_ENDPOINT:-http://100.76.17.128:3900}"
BK="${AFP_TEST_BUCKET:-afp-spike}"
RG="${AFP_TEST_REGION:-garage}"
AKV=$(sed -n 's/^GARAGE_DEFAULT_ACCESS_KEY=//p' "$AFP_TEST_KEYFILE" | head -1)
SKV=$(sed -n 's/^GARAGE_DEFAULT_SECRET_KEY=//p' "$AFP_TEST_KEYFILE" | head -1)
[ -n "$AKV" ] && [ -n "$SKV" ] || { echo "key file has no GARAGE_DEFAULT_ACCESS_KEY / SECRET_KEY lines"; exit 2; }
printf '%s' "$SKV" | "$SC/afp-config.sh" add live --endpoint "$EP" --bucket "$BK" --region "$RG" \
    --access-key "$AKV" --secret-stdin --capabilities link,expire,ui --default >/dev/null 2>&1
unset SKV

ID="$(date +%s)-$$"
PFX="skilltest/${ID}"
CREATED=()

# Direct S3 access for tampering and for reading manifests, using the helper.
raw_put() { ( . "$SC/afp-helper.sh"; afp_init; afp_load_space live; afp_req PUT "$1" /dev/null -T "$2"; echo "$AFP_HTTP" ); }
raw_get() { ( . "$SC/afp-helper.sh"; afp_init; afp_load_space live; afp_req GET "$1" "$2"; echo "$AFP_HTTP" ); }
raw_head() { ( . "$SC/afp-helper.sh"; afp_init; afp_load_space live; afp_req HEAD "$1" /dev/null; echo "$AFP_HTTP" ); }

head -c 1048576 /dev/urandom > "$T/one.bin"
head -c 8388608 /dev/urandom > "$T/eight.bin"
D1="sha256:$(shasum -a 256 "$T/one.bin" | awk '{print $1}')"
D8="sha256:$(shasum -a 256 "$T/eight.bin" | awk '{print $1}')"

# -- put and manifest
expect_ok "put a 1 MB file" "$SC/afp-put.sh" "$T/one.bin" --path "$PFX/one.bin" --ttl 1d
CREATED+=("$PFX/one.bin")
jq_is "put reports stored" '.stored' "true"
jq_is "put returns the reference" '.ref' "afp://live/$PFX/one.bin"
jq_is "put returns the local SHA-256" '.digest' "$D1"
jq_is "put returns the size" '.size' "1048576"
jq_is "put returns the endpoint" '.endpoint' "$EP"
assert "put sets an expiry from the ttl" bash -c "printf '%s' '$OUT' | jq -e '.expires | test(\"^20[0-9-]+T[0-9:]+Z\$\")'"
raw_get "$PFX/one.bin.afp.json" "$T/m.json" >/dev/null
jq_is_file() { local got; got=$(jq -r "$2" "$T/m.json" 2>/dev/null); if [ "$got" = "$3" ]; then pass "$1"; else fail "$1" "wanted '$3', got '${got}'"; fi; }
jq_is_file "manifest: afp version" '.afp' "0.1"
jq_is_file "manifest: path" '.path' "$PFX/one.bin"
jq_is_file "manifest: digest" '.digest' "$D1"
jq_is_file "manifest: size" '.size' "1048576"
jq_is_file "manifest: owner" '.owner' "$AFP_OWNER"
jq_is_file "manifest: scan" '.scan' "unscanned"
jq_is_file "manifest: content type" '.content_type' "application/octet-stream"
assert "manifest: created and expires are timestamps" bash -c "jq -e '(.created|test(\"Z\$\")) and (.expires|test(\"Z\$\"))' '$T/m.json'"
expect_err "put refuses to overwrite" exists "$SC/afp-put.sh" "$T/one.bin" --path "$PFX/one.bin"
expect_ok "put --force replaces" "$SC/afp-put.sh" "$T/one.bin" --path "$PFX/one.bin" --force
expect_ok "put an 8 MB file" "$SC/afp-put.sh" "$T/eight.bin" --path "$PFX/eight.bin"
CREATED+=("$PFX/eight.bin")
jq_is "8 MB put digest" '.digest' "$D8"

# -- get
mkdir -p "$T/dl"
expect_ok "get by reference" "$SC/afp-get.sh" "afp://live/$PFX/one.bin" --dest "$T/dl/one.bin"
jq_is "get reports verified" '.verified' "true"
jq_is "get returns the digest" '.digest' "$D1"
assert "downloaded bytes are identical" cmp -s "$T/one.bin" "$T/dl/one.bin"
expect_err "get will not overwrite without --force" exists "$SC/afp-get.sh" "afp://live/$PFX/one.bin" --dest "$T/dl/one.bin"
expect_ok "get --force overwrites" "$SC/afp-get.sh" "afp://live/$PFX/one.bin" --dest "$T/dl/one.bin" --force
expect_ok "get into a directory" "$SC/afp-get.sh" "afp://live/$PFX/eight.bin" --dest "$T/dl/"
assert "8 MB bytes are identical" cmp -s "$T/eight.bin" "$T/dl/eight.bin"
printf '{"ref":"afp://live/%s/one.bin","digest":"%s","size":1048576}' "$PFX" "$D1" > "$T/refobj.json"
expect_ok "get from a reference object file" "$SC/afp-get.sh" "@$T/refobj.json" --dest "$T/dl/refobj.bin"
expect_ok "get to the default folder" "$SC/afp-get.sh" "afp://live/$PFX/one.bin"
assert "default folder is under the AFP home" test -f "$AFP_HOME/downloads/live/$PFX/one.bin"
expect_err "get with a wrong --digest is digest_mismatch" digest_mismatch "$SC/afp-get.sh" "afp://live/$PFX/one.bin" --dest "$T/dl/wrong.bin" --digest "sha256:$(printf '0%.0s' $(seq 1 64))"
assert "no file is left after a mismatch" test ! -e "$T/dl/wrong.bin"
assert "no partial file is left after a mismatch" bash -c "! ls -A '$T/dl' | grep -q afp-partial"

# -- tamper: the object changes in the store but the manifest does not
head -c 4096 /dev/urandom > "$T/other.bin"
assert "tamper write accepted" test "$(raw_put "$PFX/one.bin" "$T/other.bin")" = "200"
expect_err "get of a tampered object is digest_mismatch" digest_mismatch "$SC/afp-get.sh" "afp://live/$PFX/one.bin" --dest "$T/dl/tampered.bin"
assert "tampered download was deleted" test ! -e "$T/dl/tampered.bin"
assert "restore the original object" test "$(raw_put "$PFX/one.bin" "$T/one.bin")" = "200"

# -- scan results
for SCANV in suspicious rejected; do
    jq --arg s "$SCANV" '.scan = $s' "$T/m.json" > "$T/m2.json"
    raw_put "$PFX/one.bin.afp.json" "$T/m2.json" >/dev/null
    expect_err "get is blocked when scan is $SCANV" scan_blocked "$SC/afp-get.sh" "afp://live/$PFX/one.bin" --dest "$T/dl/blocked-$SCANV.bin"
    assert "blocked file was never written ($SCANV)" test ! -e "$T/dl/blocked-$SCANV.bin"
done
jq '.scan = "mystery"' "$T/m.json" > "$T/m2.json"; raw_put "$PFX/one.bin.afp.json" "$T/m2.json" >/dev/null
expect_err "get is blocked on an unrecognized scan value" scan_blocked "$SC/afp-get.sh" "afp://live/$PFX/one.bin" --dest "$T/dl/blocked-x.bin"
jq '.scan = "clean"' "$T/m.json" > "$T/m2.json"; raw_put "$PFX/one.bin.afp.json" "$T/m2.json" >/dev/null
expect_ok "get works when scan is clean" "$SC/afp-get.sh" "afp://live/$PFX/one.bin" --dest "$T/dl/clean.bin"
raw_put "$PFX/one.bin.afp.json" "$T/m.json" >/dev/null

# -- list
expect_ok "ls with a prefix" "$SC/afp-ls.sh" --prefix "$PFX/"
jq_is "ls lists both objects" '.items | length' "2"
jq_is "ls item has the reference" '.items[0].ref' "afp://live/$PFX/eight.bin"
jq_is "ls item has the owner" '.items[0].owner' "$AFP_OWNER"
expect_ok "ls --limit 1" "$SC/afp-ls.sh" --prefix "$PFX/" --limit 1
jq_is "ls --limit truncates" '.truncated' "true"
expect_ok "ls of an empty prefix" "$SC/afp-ls.sh" --prefix "skilltest/none-$ID/"
jq_is "ls of an empty prefix is empty" '.items | length' "0"

# -- links
expect_ok "link with a 30 second lifetime" "$SC/afp-link.sh" "afp://live/$PFX/one.bin" --ttl 30s
jq_is "link returns the reference" '.ref' "afp://live/$PFX/one.bin"
jq_is "link returns the digest" '.digest' "$D1"
LINK_OBJ="$OUT"
LINK_URL=$(printf '%s' "$OUT" | jq -r '.url')
CODE=$(curl -s -o "$T/viaurl.bin" -w '%{http_code}' -- "$LINK_URL")
[ "$CODE" = "200" ] && cmp -s "$T/viaurl.bin" "$T/one.bin" && pass "link downloads with no credentials" || fail "link downloads with no credentials" "http=$CODE"
CODE=$(curl -s -o /dev/null -w '%{http_code}' -- "${LINK_URL%X-Amz-Signature=*}X-Amz-Signature=$(printf '0%.0s' $(seq 1 64))")
[ "$CODE" = "403" ] || [ "$CODE" = "400" ] && pass "a link with a bad signature is refused (HTTP $CODE)" || fail "a link with a bad signature is refused" "http=$CODE"
# The link works through afp-get from a machine that has no access to the space.
OTHER_HOME="$T/other-home"; mkdir -p "$OTHER_HOME"
AFP_HOME="$OTHER_HOME" run "$SC/afp-get.sh" "$LINK_OBJ" --dest "$T/dl/viaget.bin"
[ "$RC" -eq 0 ] && [ "$(printf '%s' "$OUT" | jq -r '.mode')" = "url" ] && cmp -s "$T/dl/viaget.bin" "$T/one.bin" && pass "afp-get uses the link when the space is not configured" || fail "afp-get uses the link when the space is not configured" "$(printf '%s' "$OUT" | head -c 200)"
AFP_HOME="$OTHER_HOME" run "$SC/afp-get.sh" "$(printf '%s' "$LINK_OBJ" | jq -c '.digest = "sha256:'"$(printf '1%.0s' $(seq 1 64))"'"')" --dest "$T/dl/viaget2.bin"
[ "$RC" -ne 0 ] && [ "$(printf '%s' "$OUT" | jq -r '.error.code')" = "digest_mismatch" ] && [ ! -e "$T/dl/viaget2.bin" ] && pass "the digest check applies to link downloads" || fail "the digest check applies to link downloads"
# Short link, then wait for it to expire.
"$SC/afp-link.sh" "afp://live/$PFX/one.bin" --ttl 2s > "$T/short.json" 2>/dev/null
SHORT_URL=$(jq -r '.url' "$T/short.json")
sleep 5
CODE=$(curl -s -o /dev/null -w '%{http_code}' -- "$SHORT_URL")
[ "$CODE" = "400" ] || [ "$CODE" = "403" ] && pass "an expired link is refused (HTTP $CODE)" || fail "an expired link is refused" "http=$CODE"
AFP_HOME="$OTHER_HOME" run "$SC/afp-get.sh" "$(cat "$T/short.json")" --dest "$T/dl/expired.bin"
[ "$RC" -ne 0 ] && [ "$(printf '%s' "$OUT" | jq -r '.error.code')" = "forbidden" ] && pass "afp-get reports an expired link as forbidden" || fail "afp-get reports an expired link as forbidden" "$(printf '%s' "$OUT" | head -c 200)"
expect_err "link of a missing object is not_found" not_found "$SC/afp-link.sh" "afp://live/$PFX/missing.bin"
expect_err "link rejects a lifetime over 7 days" usage "$SC/afp-link.sh" "afp://live/$PFX/one.bin" --ttl 8d
# The presigner must also work with LibreSSL, the macOS default.
if [ -x /usr/bin/openssl ] && /usr/bin/openssl version 2>/dev/null | grep -q LibreSSL; then
    mkdir -p "$T/libre"; ln -sf /usr/bin/openssl "$T/libre/openssl"
    PATH="$T/libre:$PATH" run "$SC/afp-link.sh" "afp://live/$PFX/one.bin" --ttl 60s
    LU=$(printf '%s' "$OUT" | jq -r '.url // empty')
    CODE=$(curl -s -o "$T/libre.bin" -w '%{http_code}' -- "$LU")
    [ "$CODE" = "200" ] && cmp -s "$T/libre.bin" "$T/one.bin" && pass "links signed with LibreSSL work" || fail "links signed with LibreSSL work" "http=$CODE"
fi

# -- capabilities
expect_ok "capabilities --probe" "$SC/afp-capabilities.sh" --probe
jq_is "probe says the store answered" '.probed' "true"
assert "probe reports link" bash -c "printf '%s' '$OUT' | jq -e '.capabilities | index(\"link\")'"

# -- owner check on rm
AFP_OWNER="someone-else@example.local" run "$SC/afp-rm.sh" "afp://live/$PFX/eight.bin"
[ "$RC" -ne 0 ] && [ "$(printf '%s' "$OUT" | jq -r '.error.code')" = "forbidden" ] && pass "rm refuses a different owner" || fail "rm refuses a different owner" "$(printf '%s' "$OUT" | head -c 200)"
assert "the object is still there" test "$(raw_head "$PFX/eight.bin")" = "200"
AFP_OWNER="someone-else@example.local" expect_ok "rm --admin deletes another owner's object" "$SC/afp-rm.sh" "afp://live/$PFX/eight.bin" --admin
assert "the object is gone" test "$(raw_head "$PFX/eight.bin")" = "404"
assert "its manifest is gone" test "$(raw_head "$PFX/eight.bin.afp.json")" = "404"
expect_ok "rm by the owner" "$SC/afp-rm.sh" "afp://live/$PFX/one.bin"
assert "owner delete removed the object" test "$(raw_head "$PFX/one.bin")" = "404"
expect_err "get after rm is not_found" not_found "$SC/afp-get.sh" "afp://live/$PFX/one.bin" --dest "$T/dl/gone.bin" --digest "$D1"
expect_err "rm of a missing object is not_found" not_found "$SC/afp-rm.sh" "afp://live/$PFX/one.bin"

# -- an object with no manifest
head -c 100 /dev/urandom > "$T/nomani.bin"
raw_put "$PFX/nomani.bin" "$T/nomani.bin" >/dev/null
CREATED+=("$PFX/nomani.bin")
expect_err "get without a manifest or digest is refused" digest_mismatch "$SC/afp-get.sh" "afp://live/$PFX/nomani.bin" --dest "$T/dl/nomani.bin"
expect_ok "get without a manifest works with --digest" "$SC/afp-get.sh" "afp://live/$PFX/nomani.bin" --dest "$T/dl/nomani.bin" --digest "sha256:$(shasum -a 256 "$T/nomani.bin" | awk '{print $1}')"
jq_is "the missing manifest is reported" '.warnings[0] | test("no manifest")' "true"
expect_err "link without a manifest is refused" not_found "$SC/afp-link.sh" "afp://live/$PFX/nomani.bin"

# -- cleanup
for K in "${CREATED[@]}"; do "$SC/afp-rm.sh" "afp://live/$K" --admin >/dev/null 2>&1; done
# nomani has no manifest: remove the bare object directly.
( . "$SC/afp-helper.sh"; afp_init; afp_load_space live; afp_req DELETE "$PFX/nomani.bin" /dev/null )
run "$SC/afp-ls.sh" --prefix "$PFX/"
jq_is "nothing is left under the test prefix" '.items | length' "0"
assert "no object is left under the test prefix" test "$(raw_head "$PFX/nomani.bin")" = "404"

echo ""
echo "Live: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
