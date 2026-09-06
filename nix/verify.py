"""Validate a SqueezeAMPagain application against its build configuration and layout."""

import hashlib
import json
import os
from pathlib import Path
import struct
import sys

idf = Path(os.environ["IDF_PATH"])
sys.path[:0] = [
    str(idf / "components/esptool_py/esptool"),
    str(idf / "components/partition_table"),
]
import esptool
import gen_esp32part


def require(condition, message):
    """Reject artifacts that violate the board's firmware contract."""
    if not condition:
        raise ValueError(message)


def verify(directory, version):
    """Check image integrity, board selection, metadata and flash boundaries."""
    config = dict(
        line.split("=", 1)
        for line in (directory / "sdkconfig").read_text().splitlines()
        if line.startswith("CONFIG_") and "=" in line
    )
    expected = {
        "CONFIG_SQUEEZEAMPAGAIN": "y",
        "CONFIG_PROJECT_NAME": '"SqueezeAMPagain"',
        "CONFIG_DAC_CONFIG": '"model=TAS57xx,bck=33,ws=25,do=32,sda=21,scl=22,mute=14:0"',
        "CONFIG_SPKFAULT_GPIO": "36",
        "CONFIG_ESPTOOLPY_FLASHSIZE": '"4MB"',
        "CONFIG_ESP32_SPIRAM_SUPPORT": "y",
    }
    for key, value in expected.items():
        require(config.get(key) == value, f"Unexpected {key}: {config.get(key)}")

    table = gen_esp32part.PartitionTable.from_binary(
        (directory / "partition-table.bin").read_bytes()
    )
    table.verify()
    layout = [(p.name, p.type, p.subtype, p.offset, p.size) for p in table]
    require(
        layout
        == [
            ("nvs", 1, 2, 0x9000, 0x4000),
            ("otadata", 1, 0, 0xD000, 0x2000),
            ("phy_init", 1, 1, 0xF000, 0x1000),
            ("recovery", 0, 0, 0x10000, 0x140000),
            ("ota_0", 0, 16, 0x150000, 0x2A0000),
            ("settings", 1, 2, 0x3F0000, 0x10000),
        ],
        "Unexpected partition layout; do not assume OTA compatibility",
    )
    binary = directory / "squeezelite.bin"
    data = binary.read_bytes()
    require(len(data) <= 0x2A0000, "Application exceeds OTA partition")
    with binary.open("rb") as stream:
        image = esptool.ESP32FirmwareImage(stream)
    require(struct.unpack_from("<H", data, 12)[0] == 0, "Image is not for ESP32")
    require(image.checksum == image.calculate_checksum(), "Invalid image checksum")
    require(image.append_digest, "Image lacks SHA-256 validation")
    require(image.stored_digest == image.calc_digest, "Invalid image SHA-256")
    require(
        struct.unpack_from("<I", data, 32)[0] == 0xABCD5432, "Missing app descriptor"
    )
    require(
        data[48:80].split(b"\0")[0].decode() == version, "Unexpected firmware version"
    )
    require(data[80:112].split(b"\0")[0] == b"SqueezeAMPagain", "Unexpected board name")
    return {
        "version": version,
        "bytes": len(data),
        "ota_capacity": 0x2A0000,
        "sha256": hashlib.sha256(data).hexdigest(),
        "idf_version": data[144:176].split(b"\0")[0].decode(),
    }


if __name__ == "__main__":
    print(json.dumps(verify(Path(sys.argv[1]), sys.argv[2]), indent=2))
