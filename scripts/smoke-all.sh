#!/usr/bin/env bash
# Build ue2emu, then run every smoke script headless at --speed max in a fresh temporary run directory. Stops at
# the first failure, prints that run's log tail, and exits non-zero.
#
#   scripts/smoke-all.sh
#
# Firmware: $UE2_FIRMWARE (default: firmware/1541ultimate under the repo root) must hold
# target/u64ii/riscv/ultimate/result/ultimate.elf and roms/. The run directory (logs, SD image, flash images,
# PNGs) is removed after a pass and kept after a failure. The SD image is built with
# scripts/make-sd-image.py (portable: Linux, WSL, Windows, macOS); set UE2_SD_IMAGE_SCRIPT=sh to use
# scripts/make-sd-image.sh instead, which needs a macOS login session.
#
# Runs, in order:
#   menu        smoke-menu.ctl      --flash run/flash.bin (seeded on first use)
#   sd          smoke-sd.ctl        --flash run/flash.bin --sd run/sd.img
#   flash-1     smoke-flash-1.ctl   --flash run/flash-ui.bin (fresh: Color Scheme must not be C128 Style yet)
#   flash-2     smoke-flash-2.ctl   --flash run/flash-ui.bin --no-overlay-ui
#   usb         smoke-usb.ctl       --flash run/flash-usb.bin --usb run/usb.img --usb-keyboard
#   c64-ready   smoke-c64-ready.ctl   --flash run/flash-c64-ready.bin --c64-roms
#   c64-type    smoke-c64-type.ctl    --flash run/flash-c64-type.bin --c64-roms
#   c64-prg     smoke-c64-prg.ctl     --flash run/flash-c64-prg.bin --c64-roms --sd run/sd.img
#   c64-freeze  smoke-c64-freeze.ctl  --flash run/flash-c64-freeze.bin --c64-roms --no-overlay-ui
#   negative    an expect that cannot match; passes only when ue2emu exits non-zero and names its line
# Each of the five scripts above gets its own flash image and its own --control port (6401-6405), so no two
# runs ever share one, even though smoke-all.sh runs them one at a time.

set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
fw=${UE2_FIRMWARE:-$repo/firmware/1541ultimate}
elf=$fw/target/u64ii/riscv/ultimate/result/ultimate.elf
if [[ ! -f $elf || ! -f $fw/roms/chars.bin ]]; then
    echo "firmware not found: need $elf and $fw/roms (set UE2_FIRMWARE)" >&2
    exit 2
fi

cargo build --release --manifest-path "$repo/Cargo.toml"
bin=${CARGO_TARGET_DIR:-$repo/target}/release/ue2emu

rundir=$(mktemp -d "${TMPDIR:-/tmp}/ue2-smoke.XXXXXX")
cd "$rundir"
mkdir run
echo "run directory: $rundir"

# emu <name> <script> [ue2emu run options]: run one script headless; stdout to run/<name>.log, stderr to
# run/<name>.err; returns ue2emu's exit code.
emu() {
    local name=$1 script=$2
    shift 2
    "$bin" run --headless --speed max --firmware "$elf" --roms "$fw/roms" "$@" --script "$script" \
        >"run/$name.log" 2>"run/$name.err"
}

fail() {
    local name=$1
    shift
    echo "FAIL $name: $*"
    echo "--- run/$name.log (last 40 lines)"
    tail -n 40 "run/$name.log"
    echo "--- run/$name.err"
    cat "run/$name.err"
    echo "kept: $rundir"
    exit 1
}

# smoke <name> <script> [ue2emu run options]: run a script that must pass.
smoke() {
    local name=$1 start=$SECONDS rc=0
    emu "$@" || rc=$?
    ((rc == 0)) || fail "$name" "exit code $rc"
    # The emulation thread's stats line on stderr: "<n> instructions, <t> s emulated, ...".
    local emulated
    emulated=$(grep -o '[0-9.]* s emulated' "run/$name.err" | tail -n 1)
    echo "PASS $name (${emulated:-? s emulated}, $((SECONDS - start)) s wall)"
}

smoke menu "$repo/scripts/smoke-menu.ctl" --flash run/flash.bin
if [[ ${UE2_SD_IMAGE_SCRIPT:-py} == sh ]]; then
    "$repo/scripts/make-sd-image.sh" run/sd.img
else
    # Through the interpreter, not the shebang: make-sd-image.py is mode 100644 in the index, so a clean
    # checkout cannot execute it directly. make-sd-image.py runs ue2-mkimage with cwd=$repo, so the image
    # path must be absolute here or it would land under $repo/run instead of this run directory's run/.
    "${UE2_PYTHON:-python3}" "$repo/scripts/make-sd-image.py" "$PWD/run/sd.img"
fi
smoke sd "$repo/scripts/smoke-sd.ctl" --flash run/flash.bin --sd run/sd.img
smoke flash-1 "$repo/scripts/smoke-flash-1.ctl" --flash run/flash-ui.bin
smoke flash-2 "$repo/scripts/smoke-flash-2.ctl" --flash run/flash-ui.bin --no-overlay-ui

if [[ ${UE2_SD_IMAGE_SCRIPT:-py} == sh ]]; then
    "$repo/scripts/make-sd-image.sh" run/usb.img 48
else
    "${UE2_PYTHON:-python3}" "$repo/scripts/make-sd-image.py" "$PWD/run/usb.img" 48
fi
smoke usb "$repo/scripts/smoke-usb.ctl" --flash run/flash-usb.bin --usb run/usb.img --usb-keyboard \
    --control 127.0.0.1:6401
smoke c64-ready "$repo/scripts/smoke-c64-ready.ctl" --flash run/flash-c64-ready.bin --c64-roms \
    --control 127.0.0.1:6402
smoke c64-type "$repo/scripts/smoke-c64-type.ctl" --flash run/flash-c64-type.bin --c64-roms \
    --control 127.0.0.1:6403
smoke c64-prg "$repo/scripts/smoke-c64-prg.ctl" --flash run/flash-c64-prg.bin --c64-roms --sd run/sd.img \
    --control 127.0.0.1:6404
smoke c64-freeze "$repo/scripts/smoke-c64-freeze.ctl" --flash run/flash-c64-freeze.bin --c64-roms \
    --no-overlay-ui --control 127.0.0.1:6405

printf '# must fail\nexpect "NO SUCH TEXT ON THE SCREEN" 500\nquit\n' >run/negative.ctl
rc=0
emu negative run/negative.ctl --flash run/flash.bin || rc=$?
((rc != 0)) || fail negative "a failing expect exited 0"
grep -q 'line 2' "run/negative.err" || fail negative "the error does not name the failing line"
echo "PASS negative (exit code $rc)"

cd /
rm -rf "$rundir"
echo "all smoke tests passed"
