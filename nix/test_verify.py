"""Exercise the image checks against real build artifacts and damaged copies."""

from pathlib import Path
import shutil
import sys
import tempfile
import unittest

from verify import verify


class ImageValidation(unittest.TestCase):
    """Cover successful validation and unsafe image rejection."""

    def test_valid_image(self):
        """Accept the freshly built board image."""
        self.assertEqual(verify(directory, version)["version"], version)

    def test_damaged_images(self):
        """Reject corruption, oversize uploads, and incorrect board configuration."""
        with tempfile.TemporaryDirectory() as temporary:
            target = Path(temporary)
            for name in ("squeezelite.bin", "sdkconfig", "partition-table.bin"):
                shutil.copyfile(directory / name, target / name)
            binary = target / "squeezelite.bin"
            original = binary.read_bytes()
            damaged = bytearray(original)
            damaged[1024] ^= 1
            for label, data in (("corrupt", damaged), ("oversized", bytes(0x2A0001))):
                with self.subTest(label):
                    binary.write_bytes(data)
                    with self.assertRaises(ValueError):
                        verify(target, version)
            binary.write_bytes(original)
            config = target / "sdkconfig"
            config.write_text(
                config.read_text().replace(
                    "CONFIG_SPKFAULT_GPIO=36", "CONFIG_SPKFAULT_GPIO=-1"
                )
            )
            with self.assertRaises(ValueError):
                verify(target, version)


if __name__ == "__main__":
    directory, version = Path(sys.argv[1]), sys.argv[2]
    unittest.main(argv=[sys.argv[0]])
