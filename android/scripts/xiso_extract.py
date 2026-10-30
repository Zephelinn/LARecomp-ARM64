"""xiso_extract.py <game.iso> <output folder> [--list]: extract an Xbox 360 game ISO (XDVDFS), the same way
LARecomp's install wizard does (src/isoinstaller/larecomp_iso_installer.cpp: game-partition offsets, magic at
sector 32, the directory entries' binary trees), and check that default.xex is MCLA: Complete Edition
(title ID 545407F8). Standard library only; run with `python -I`.

The output folder then holds default.xex and the xarchive_*.rpf archives: the folder LARecomp calls
MCLA_Game_Files (on Android: /sdcard/Android/data/org.larecomp.android/files/game)."""
import os
import struct
import sys

SECTOR = 2048
GAME_OFFSETS = (0x00000000, 0x0000FB20, 0x00020600, 0x02080000, 0x0FD90000)
MAGIC = b"MICROSOFT*XBOX*MEDIA"
MCLA_TITLE_ID = 0x545407F8
REQUIRED = ("default.xex", "xarchive_audio.rpf", "xarchive_audlo.rpf", "xarchive_cache.rpf")


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    iso_path, out_dir = sys.argv[1], sys.argv[2]
    only_list = "--list" in sys.argv[3:]
    size = os.path.getsize(iso_path)
    with open(iso_path, "rb") as iso:
        def read(offset, n):
            iso.seek(offset)
            data = iso.read(n)
            if len(data) != n:
                sys.exit(f"short read at {offset:#x}")
            return data

        game = None
        for candidate in GAME_OFFSETS:
            at = candidate + 32 * SECTOR
            if at + len(MAGIC) <= size and read(at, len(MAGIC)) == MAGIC:
                game = candidate
                break
        if game is None:
            sys.exit("not an Xbox 360 game ISO (no XDVDFS volume found)")
        root_sector, root_size = struct.unpack("<II", read(game + 32 * SECTOR + 20, 8))
        if not 13 <= root_size <= 32 << 20:
            sys.exit("invalid root directory")

        entries = []  # (path, offset, length)
        pending = [(game + root_sector * SECTOR, 0, "")]
        while pending:
            directory, node, prefix = pending.pop()
            left, right, sector, length, attributes, name_length = struct.unpack("<HHIIBB",
                                                                                  read(directory + node, 14))
            if left == 0xFFFF:  # padding at the end of a directory sector
                continue
            if not 0 < name_length <= 240:
                sys.exit(f"invalid directory entry at {directory + node:#x}")
            name = read(directory + node + 14, name_length).decode("latin-1")
            if left:
                pending.append((directory, left * 4, prefix))
            if right:
                pending.append((directory, right * 4, prefix))
            if attributes & 0x10:
                if length:
                    pending.append((game + sector * SECTOR, 0, prefix + name + "/"))
            else:
                entries.append((prefix + name, game + sector * SECTOR, length))

        by_name = {p.lower(): (p, o, n) for p, o, n in entries}
        xex = by_name.get("default.xex")
        if not xex:
            sys.exit("the ISO has no default.xex")
        header = read(xex[1], min(16384, xex[2]))
        if header[:4] != b"XEX2":
            sys.exit("default.xex is not an XEX2 executable")
        title_id = None
        for i in range(struct.unpack(">I", header[0x14:0x18])[0]):
            key, value = struct.unpack(">II", header[0x18 + i * 8:0x20 + i * 8])
            if key == 0x00040006:  # execution info
                title_id = struct.unpack(">I", header[value + 0xC:value + 0x10])[0]
                break
        if title_id != MCLA_TITLE_ID:
            sys.exit(f"not MCLA: Complete Edition (title ID {title_id:08X})" if title_id else "no title ID")
        missing = [r for r in REQUIRED if r not in by_name]
        total = sum(n for _, _, n in entries)
        print(f"MCLA: CE, title ID {title_id:08X}, {len(entries)} files, {total / 2**30:.2f} GiB"
              + (f", MISSING {missing}" if missing else ""))
        if only_list:
            for p, o, n in sorted(entries):
                print(f"{n:>12}  {p}")
            return
        done = 0
        for path, offset, length in sorted(entries):
            parts = path.split("/")
            if any(part in ("", ".", "..") for part in parts):
                sys.exit(f"unsafe path in the ISO: {path!r}")
            target = os.path.join(out_dir, *parts)
            os.makedirs(os.path.dirname(target), exist_ok=True)
            with open(target, "wb") as out:
                iso.seek(offset)
                left = length
                while left:
                    chunk = iso.read(min(left, 8 << 20))
                    if not chunk:
                        sys.exit(f"ISO ends inside {path}")
                    out.write(chunk)
                    left -= len(chunk)
            done += length
            print(f"[{100 * done / max(total, 1):5.1f}%] {path}")
        print(f"extracted to {out_dir}")


if __name__ == "__main__":
    main()
