#!/usr/bin/env bash
# Jalankan semua tes NoctisENIX. Pakai: (cd tests && npm install) sekali, lalu bash tests/run_all.sh
set -u
cd "$(dirname "$0")"
ROOT=..
fail=0
run() {
  local name="$1"; shift
  local out
  out=$("$@" 2>&1)
  local code=$?
  if [ $code -ne 0 ] || echo "$out" | grep -qE "^FAIL|FAILURES|ERROR"; then
    echo "FAIL  $name"; echo "$out" | grep -E "FAIL|ERROR| - " | head -20; fail=1
  else
    echo "ok    $name  $(echo "$out" | tail -1)"
  fi
}
python3 $ROOT/tools/build.py >/dev/null && python3 $ROOT/tools/build.py --stub >/dev/null || { echo "build failed"; exit 1; }
for f in $ROOT/NoctisENIX.lua $ROOT/NoctisENIX_Inspector.lua $ROOT/src/modules/*.lua; do
  run "syntax $(basename $f)" node check.mjs "$f"
  run "lint   $(basename $f)" node lint.mjs "$f"
done
run "module game_api"      node modtest.mjs modules/test_game_api.lua
run "module net"           node modtest.mjs modules/test_net.lua NetFactory=$ROOT/src/modules/net.lua
run "module votes"         node modtest.mjs modules/test_votes.lua NetFactory=$ROOT/src/modules/net.lua VotesFactory=$ROOT/src/modules/votes.lua
run "module intel"         node modtest.mjs modules/test_intel.lua IntelFactory=$ROOT/src/modules/intel.lua
run "module intel+net"     node modtest.mjs modules/test_intel_net.lua IntelFactory=$ROOT/src/modules/intel.lua
run "module intel anim"    node modtest.mjs modules/test_intel_anim.lua IntelFactory=$ROOT/src/modules/intel.lua
run "module actions"       node modtest.mjs modules/test_actions.lua ActionsFactory=$ROOT/src/modules/actions.lua
run "module actions+net"   node modtest.mjs modules/test_actions_net.lua ActionsFactory=$ROOT/src/modules/actions.lua
run "module actions seat"  node modtest.mjs modules/test_actions_seat.lua ActionsFactory=$ROOT/src/modules/actions.lua
run "module inspector"     node modtest.mjs modules/test_inspector.lua Inspector=$ROOT/src/inspector.lua
run "module inspector+net" node modtest.mjs modules/test_inspector_net.lua Inspector=$ROOT/src/inspector.lua
run "smoke ui (stubs)"     node smoke.mjs .debug/NoctisENIX_stub.lua smoke_main.lua
run "smoke real modules"   node smoke.mjs $ROOT/NoctisENIX.lua smoke_real.lua smoke_world.lua
exit $fail
