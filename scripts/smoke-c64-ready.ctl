# S14 A2: the C64 boots to BASIC READY, first without and then behind the overlay menu.
# Run with --flash run/flash.bin --c64-roms (docs/specs/S14-c64-trx64.md §12).
# Expected: the c64screen dump holds "**** COMMODORE 64 BASIC V2 ****", "64K RAM SYSTEM  38911 BASIC BYTES FREE" and
# "READY."; run/c64-ready.png is 384x272 (border 6D6AEF at 4,4, background 2C29B1 at 340,220); the screen dump after
# the button is the M3 menu; run/c64-overlay.png shows the menu over the C64 picture.
# Self-checking: expect asserts the overlay menu is up, both before boot and after the button toggles it visible.
# screen_text (what expect matches) ignores overlay visibility and cannot see the C64's own screen, so the BASIC
# READY text above stays a documented c64screen dump, not an expect.
expect "F3=HELP" 10000
wait 6000
c64screen
png run/c64-ready.png
button
wait 800
expect "-F3=HELP-"
screen
png run/c64-overlay.png
quit
