"""Spelunky 2 (1.28, Steam) online "Syncing" freeze fix.

After a level transition every player appends a sync marker to their input stream,
and the main loop waits until every stream ends with that marker. When it does, the
game sets the next tick to now + 1/60. On the next loop iteration the markers are
still at the end (no tick has run yet, so no new input was added) and the tick is
pushed another 1/60 into the future. With frames shorter than 16.7 ms (high refresh
rate + VSync) this repeats until a random hitch or an alt-tab breaks it.

The fix changes 19 bytes so the barrier schedules the tick at now - 2 * frametime,
which runs one tick right away and lets normal pacing continue.

Usage (double-click = install):
    py syncfix.py               install the fix into Spel2.exe (game must be closed)
    py syncfix.py --uninstall   put the original bytes back
    py syncfix.py --check       read only, show whether the fix is installed
    py syncfix.py "D:\\path\\to\\Spel2.exe"   use a specific exe instead of searching Steam

A Steam update or "verify integrity of game files" restores the original exe, run
this again after that.
"""
import os
import re
import struct
import sys

RVA = 0x22CBF261  # WinMain, sync barrier success (Spelunky 2 1.28 Steam)
ORIGINAL = bytes.fromhex('66410f28c0f20f58c1f20f1105bef41500eb08')
PATCHED = bytes.fromhex('66410f28c0f20f5cc3f20f5cc3eb0c0f1f4000')
GAME_DIR = os.path.join('steamapps', 'common', 'Spelunky 2')


def steam_libraries():
    """Steam library folders from the registry and libraryfolders.vdf."""
    try:
        import winreg
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, r'Software\Valve\Steam') as key:
            steam = winreg.QueryValueEx(key, 'SteamPath')[0]
    except OSError:
        steam = r'C:\Program Files (x86)\Steam'
    libs = [steam]
    try:
        with open(os.path.join(steam, 'steamapps', 'libraryfolders.vdf'), encoding='utf-8') as f:
            libs += [p.replace('\\\\', '\\') for p in re.findall(r'"path"\s+"([^"]+)"', f.read())]
    except OSError:
        pass
    return libs


def find_exe():
    here = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'Spel2.exe')
    candidates = [here] + [os.path.join(lib, GAME_DIR, 'Spel2.exe') for lib in steam_libraries()]
    return next((p for p in candidates if os.path.isfile(p)), None)


def file_offset(f, rva):
    """Translate an RVA to a file offset using the PE section table."""
    f.seek(0x3C)
    pe = struct.unpack('<I', f.read(4))[0]
    f.seek(pe + 6)
    sections = struct.unpack('<H', f.read(2))[0]
    f.seek(pe + 20)
    optional_size = struct.unpack('<H', f.read(2))[0]
    f.seek(pe + 24 + optional_size)
    for _ in range(sections):
        _, vsize, vaddr, rawsize, rawptr = struct.unpack('<8sIIII', f.read(24))
        f.read(16)
        if vaddr <= rva < vaddr + max(vsize, rawsize):
            return rva - vaddr + rawptr
    raise ValueError('patch address is not inside any section')


def main(args):
    paths = [a for a in args if not a.startswith('--')]
    exe = paths[0] if paths else find_exe()
    if not exe or not os.path.isfile(exe):
        return 'Spel2.exe not found. Put this file in the game folder or give the path to Spel2.exe'
    print('game:', exe)
    with open(exe, 'rb') as f:
        off = file_offset(f, RVA)
        f.seek(off)
        cur = f.read(len(ORIGINAL))
    state = {ORIGINAL: 'not installed', PATCHED: 'installed'}.get(cur)
    if state is None:
        return 'unexpected bytes at the patch site (not Spelunky 2 1.28 Steam?), nothing changed: ' + cur.hex()
    if '--check' in args:
        print('sync fix is', state)
        return None
    uninstall = '--uninstall' in args or '--undo' in args
    want = ORIGINAL if uninstall else PATCHED
    if cur == want:
        print('nothing to do, sync fix is already', state)
        return None
    try:
        with open(exe, 'r+b') as f:
            f.seek(off)
            f.write(want)
            f.seek(off)
            ok = f.read(len(want)) == want
    except PermissionError:
        return 'cannot write Spel2.exe, close the game first'
    if not ok:
        return 'verify failed'
    print('original bytes restored' if uninstall else 'sync fix installed, you can play normally now')
    return None


if __name__ == '__main__':
    error = main(sys.argv[1:])
    if error:
        print('error:', error)
    if len(sys.argv) == 1:  # started by double-click: keep the window open
        input('press enter to close')
    sys.exit(1 if error else 0)
