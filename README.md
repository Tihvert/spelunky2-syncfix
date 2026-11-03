# spelunky 2 sync fix

Fixes the online co-op "Syncing" freeze between levels in Spelunky 2 (Steam, version 1.28).

If the game sits on "Syncing" after a level transition and only continues when you alt-tab, this is that bug.

**Status: tested in one online session (2 players, 240 Hz).** Before the fix a normal sync took 0.6 to 1.2 s and a stuck one 11 to 15 s. With the fix the "Syncing" text was up for 66 to 82 ms on all three level transitions, and nobody had to alt-tab.

## How to use

1. Close Spelunky 2.
2. Double-click `install.cmd`. It finds the game through Steam, patches it and shows `sync fix installed`.
3. Play. You don't need to run it again.

`install.cmd` just runs `syncfix.ps1` with PowerShell, which comes with Windows. Both are plain text, open them in notepad if you want to see what they do. `syncfix.py` does the same thing in Python if you prefer that.

A Steam update or "verify integrity of game files" puts the original exe back. If the syncing freeze comes back after an update, just run it again (if the update changed the code, it will say so and change nothing).

Everyone in the lobby with a high refresh rate monitor should install it. It doesn't hurt on a 60 Hz machine.

From a terminal:

```
install.cmd                            install
install.cmd -Check                     read only, shows if the fix is installed
install.cmd -Uninstall                 put the original bytes back
install.cmd -Exe "D:\path\Spel2.exe"   use this exe instead of searching Steam

py syncfix.py [--check | --uninstall | "D:\path\Spel2.exe"]   same in python
```

## What it changes

19 bytes in `Spel2.exe`, nothing else. No dll, no launcher, nothing running in the background. Before writing it checks that those 19 bytes are exactly the original 1.28 ones, otherwise it stops and changes nothing. `--uninstall` writes the original bytes back, the file is then identical to the Steam one.

## Why the game gets stuck

After a level transition every player adds a sync marker to their input stream. The main loop then waits until every player's stream ends with that marker. When that happens it sets the next game tick to `now + 1/60`.

The problem is the next loop iteration. No tick has run yet, so no new input was added and the markers are still at the end of every stream. The barrier passes again and pushes the tick another 1/60 into the future. The tick check `now <= frametime + next_tick` is never false, so the game never ticks.

It only gets out when one loop iteration takes longer than 16.7 ms. On a 60 Hz monitor with VSync that happens quickly, so the sync lasts under a second. On 144 or 240 Hz a frame is 4 to 7 ms, so it can stay stuck for a long time. Alt-tab works because the game runs at about 30 fps when it's not focused, and that one long frame breaks the loop.

Because both players wait for each other's inputs, one stuck player freezes everyone.

## The patch

Code at RVA `0x22CBF261` (file offset `0x22CBE661`), inside WinMain right after the marker check:

```
original                                   patched
movapd xmm0, xmm8     ; now                movapd xmm0, xmm8     ; now
addsd  xmm0, xmm1     ; + 1/60             subsd  xmm0, xmm3     ; - frametime
movsd  [next_tick], xmm0                   subsd  xmm0, xmm3     ; - frametime
jmp    tick_check                          jmp    tick_check
                                           nop
```

So when everyone has sent the marker, the next tick is scheduled in the past and runs right away. The tick loop then stores `next_tick` itself, which is why the store can go. After one tick new input is added, the markers are no longer at the end and normal frame pacing continues.

Bytes:

```
original 66 41 0f 28 c0 f2 0f 58 c1 f2 0f 11 05 be f4 15 00 eb 08
patched  66 41 0f 28 c0 f2 0f 5c c3 f2 0f 5c c3 eb 0c 0f 1f 40 00
```

Can this fire during normal play? The barrier compares the last byte of every input stream with the marker, which is always `0x10` to `0x2F`. In normal play the last byte is the high byte of the input word, and that only holds the direction bits (`0x00` to `0x0F`). In about 8500 logged samples the high bytes were `0x00` to `0x0A`, and `0x21` to `0x2B` only showed up as markers, one per level transition. So the patched path only runs at the real sync point.

## How it was found

Static analysis of Spel2.exe 1.28 in IDA and Ghidra, plus a read-only memory logger during real online games. The "Syncing" text is drawn when `0x162E0CD81` is set, the marker barrier is in WinMain, and the logs showed both players stuck on the same frame with every marker in place and the next tick being pushed forward on every loop.

Offsets and structure names from [Overlunky](https://github.com/spelunky-fyi/overlunky) helped a lot.

## License

MIT, see LICENSE.
