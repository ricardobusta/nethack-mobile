#!/usr/bin/env python3
"""Convert release-matched NetHack text tiles to a PNG atlas (no dependencies)."""
from pathlib import Path
import re
import struct
import sys
import zlib


def convert(source, output):
    tiles = []
    statues = []
    mapping_text = re.search(r'static const int graymappings\[\]\s*=\s*\{(.*?)\};', (source / 'tiletext.c').read_text(), re.S).group(1)
    mapping_text = re.sub(r'/\*.*?\*/', '', mapping_text, flags=re.S)
    grayscale = [int(value) for value in mapping_text.split(',') if value.strip()]
    for name in ('monsters.txt', 'objects.txt', 'other.txt'):
        palette = {}
        rows = None
        for line in (source / name).read_text().splitlines():
            match = re.match(r'^(.+)\s*=\s*\(\s*(\d+),\s*(\d+),\s*(\d+)\s*\)', line)
            if match:
                palette[match[1].strip()] = bytes(int(v) for v in match.groups()[1:])
            elif line.strip() == '{':
                rows = []
            elif line.strip() == '}' and rows is not None:
                if len(rows) != 16 or any(len(row) != 16 for row in rows):
                    raise ValueError('Unexpected tile size')
                tiles.append(b''.join(palette[c] for row in rows for c in row))
                if name == 'monsters.txt':
                    keys = list(palette)
                    mapped = {key: palette[keys[grayscale[i]]] if i < len(grayscale) else palette[key] for i, key in enumerate(keys)}
                    statues.append(b''.join(mapped[c] for row in rows for c in row))
                rows = None
            elif rows is not None:
                rows.append(line.strip())
    tiles.extend(statues)
    columns = 40
    width, height = columns * 16, ((len(tiles) + columns - 1) // columns) * 16
    pixels = bytearray(width * height * 3)
    for i, tile in enumerate(tiles):
        x, y = (i % columns) * 16, (i // columns) * 16
        for row in range(16):
            start = ((y + row) * width + x) * 3
            pixels[start:start + 48] = tile[row * 48:(row + 1) * 48]
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    raw = b''.join(b'\0' + pixels[row * width * 3:(row + 1) * width * 3] for row in range(height))
    output.write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))
    print(f'Generated {len(tiles)} upstream tiles: {width}x{height}')
    return len(tiles)


if __name__ == '__main__':
    convert(Path(sys.argv[1]), Path(sys.argv[2]))
