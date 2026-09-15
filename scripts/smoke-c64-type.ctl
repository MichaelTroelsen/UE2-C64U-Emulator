# S14 A3: host keys reach CIA1. Run with --flash run/flash.bin --c64-roms holding the ROMs
# (docs/specs/S14-c64-trx64.md §12).
# Expected: the c64screen dump holds a line " 42".
# `type` follows the firmware keymap, where an upper-case letter is SHIFT + key (keyboard_c64.cc:49-58); the C64
# prints unshifted letters as capitals, so the BASIC text is typed in lower case.
# Self-checking: expect gates on the overlay menu being up before the C64 has had time to reach READY.; screen_text
# (what expect matches) cannot see the C64's own screen, so " 42" stays a documented c64screen dump, not an expect.
expect "F3=HELP" 10000
wait 6000
type print 6*7
key return
wait 500
c64screen
quit
