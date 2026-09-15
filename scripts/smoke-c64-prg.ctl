# S14 A4: run a PRG from the SD image through the boot cartridge (DMA load).
# Image: scripts/make-sd-image.sh run/sd.img; run with --flash run/flash.bin --c64-roms --sd run/sd.img
# (docs/specs/S14-c64-trx64.md §12).
# Expected: the console has "DMA load complete: $0801-" and "Cart got disabled, now restoring.", not
# "Error.. cart did not get disabled."; the c64screen dump holds "HELLO FROM UE2EMU" followed by "READY.".
# Self-checking: expect/expect-console assert the SD browse, the Run context-menu entry and the DMA-load/cart-
# restore console lines below. screen_text (what expect matches) cannot see the C64's own screen, so
# "HELLO FROM UE2EMU" and "READY." stay a documented c64screen dump, not an expect.
expect "F3=HELP" 10000
wait 6000
button
expect "SD      SD Card                Ready"
key right
expect-console "3 children fetched from SD."
wait 300
key down
wait 300
# RETURN opens the context menu of hello.prg with Run first (tree_browser.cc:118-128, filetype_prg.cc:70).
key return
expect "+Run       |"
key return
expect-console "Action set was: Run"
expect-console "DMA load complete: $0801-"
expect-console "Cart got disabled, now restoring."
wait 5000
c64screen
png run/c64-prg.png
quit
