"""Compare firmware builds, permitting only timestamp and ELF-digest metadata drift."""

from pathlib import Path
import sys

from elftools.elf.elffile import ELFFile

from verify import require, verify


def compare(left, right, version):
    """Require identical configuration, layout, and allocated ELF sections."""
    reports = [verify(directory, version) for directory in (left, right)]
    for name in ("sdkconfig", "partition-table.bin"):
        require((left / name).read_bytes() == (right / name).read_bytes(), f"Different {name}")
    with (left / "squeezelite.elf").open("rb") as a, (right / "squeezelite.elf").open("rb") as b:
        a, b = ELFFile(a), ELFFile(b)
        require(a["e_machine"] == b["e_machine"], "Different architecture")
        require(a["e_entry"] == b["e_entry"], "Different entry point")
        sections = [{s.name: s for s in elf.iter_sections() if s["sh_flags"] & 2} for elf in (a, b)]
        require(sections[0].keys() == sections[1].keys(), "Different allocated sections")
        for name, first in sections[0].items():
            second = sections[1][name]
            for field in ("sh_type", "sh_flags", "sh_addr", "sh_size", "sh_addralign"):
                require(first[field] == second[field], f"Different {name} {field}")
            if first["sh_type"] == "SHT_NOBITS":
                continue
            data = [bytearray(section.data()) for section in (first, second)]
            if name == ".flash.appdesc":
                for value in data:
                    value[80:112] = bytes(32)
                    value[144:176] = bytes(32)
            require(data[0] == data[1], f"Different contents in {name}")
            print(f"Identical: {name}")
    print("Image SHA-256:", *(report["sha256"] for report in reports))
    print("Firmware matches apart from allowed build metadata; this is not a hardware test.")


if __name__ == "__main__":
    compare(Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3])
