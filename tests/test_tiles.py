from pathlib import Path
import struct
import sys
import tempfile
import unittest
import zlib

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from tiles import convert


class TileTests(unittest.TestCase):
    def test_atlas_includes_statues_and_preserves_palette(self):
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / 'tiles.png'
            count = convert(ROOT / 'vendor/nethack/win/share', output)
            self.assertEqual(count, 2304)  # Pinned 5.0.0 artwork, including statue variants.
            data = output.read_bytes()
            self.assertEqual(data[:8], b'\x89PNG\r\n\x1a\n')
            width, height = struct.unpack('>II', data[16:24])
            self.assertEqual((width, height), (640, 928))
            compressed = bytearray()
            offset = 8
            while offset < len(data):
                size = struct.unpack('>I', data[offset:offset + 4])[0]
                if data[offset + 4:offset + 8] == b'IDAT':
                    compressed.extend(data[offset + 8:offset + 8 + size])
                offset += size + 12
            pixels = zlib.decompress(compressed)
            def tile(index):
                x, y = (index % 40) * 16, (index // 40) * 16
                return [tuple(pixels[(y + row) * (width * 3 + 1) + 1 + (x + col) * 3:(y + row) * (width * 3 + 1) + 4 + (x + col) * 3]) for row in range(16) for col in range(16)]
            original, statue = tile(0), tile(1515)
            self.assertNotEqual(original, statue)
            self.assertEqual(original[0], statue[0])  # Upstream background is retained.
            self.assertTrue(any(r != g for r, g, b in original if (r, g, b) != original[0]))
            self.assertTrue(all(r == g == b for r, g, b in statue if (r, g, b) != statue[0]))


if __name__ == '__main__':
    unittest.main()
