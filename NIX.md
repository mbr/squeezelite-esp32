# Native firmware build

`squeezeampagain` contains the selected upstream release plus Alex's board
patches. `squeezeampagain-mbr` builds on it with our build tooling and firmware
changes. Historical checkpoints are preserved as annotated `archive/*` tags.

Run `nix build` on `x86_64-linux`. The OTA application is
`result/squeezelite.bin`; `result/manifest.json` records its identity and digest.
The build never contacts or flashes a device. Run `./check.sh` for checks and
`./format.sh` for formatting. `nix develop` provides the build tools.

The flake builds the checked-out firmware source with the `I2S-4MFlash`,
16-bit configuration, selecting Alex's `SQUEEZEAMPAGAIN` profile and GPIO `36`
for speaker fault detection. The generic preset otherwise overrides that pin
with `-1`. This is not the upstream `SqueezeAmp` hardware profile.

`flake.lock` pins Nixpkgs. ESP-IDF, submodules, the Espressif GCC distribution,
and CMake are independently hash-pinned. The native compiler executables are
relocated for Nix; no container or FHS environment is used. GDB is omitted to
avoid its obsolete Python dependency. CMake is pinned because newer releases
change the ordering of ESP-IDF's C++ standard flags. The existing linker-generator
patch from `docker/patches` is applied to ESP-IDF, matching the reference
container's `v4.3.5-dirty` identity. Host-only Python compatibility adjustments
do not modify the firmware source. The checked-in web assets are used without
an npm rebuild or network access during compilation.

Changing gitlinks requires updating the corresponding submodule pins in
`flake.nix`. Keep the firmware's short `PROJECT_VER` value in sync when moving
to another upstream version; ESP-IDF stores at most 31 characters. Nix's fixed
`SOURCE_DATE_EPOCH` makes build timestamps independent of wall-clock time.

# Wi-Fi playback experiment

The `squeezeampagain-mbr` branch reports `I2S-4MFlash.16.1737.wifi2`.
It keeps the Wi-Fi modem awake (`WIFI_PS_NONE`), trading increased power
consumption for lower packet-delivery latency. The policy is applied on station
startup as well as AP setup; normal station boots do not run AP configuration. The web UI scans only when the
Scan button is clicked and its HTML is packaged once, avoiding duplicate
initialization and polling. The rebuilt UI passed an isolated browser test:
no scan during page load and exactly one scan per button click.

These changes do not establish that AirPlay stuttering is fixed. Test sustained
playback on the device. Keep `-s -disable` in its startup command if LMS is unused;
OTA preserves that setting rather than overwriting it.

# Spotify credentials

This upstream version requires a Spotify application client ID and secret for
Spotify Connect. The checked-in `components/spotify/client_info.h` contains
placeholders; the default build therefore does not provide working Spotify
application credentials. Boot and network smoke tests do not test Spotify.
Provisioning those credentials is a separate step. Do not commit secrets:
embedding them in a Nix build also exposes them in its store and firmware output.

# Validation and comparison

The build validates the image checksum, SHA-256, ESP32 target, project/version,
board configuration, application size, and partition layout. This detects build
mistakes; it does not establish compatibility with an unknown device's actual
flash layout or prove that audio works.

For a reference build, use the documented container pinned to:

```
docker.io/sle118/squeezelite-esp32-idfv435@sha256:3c0fc970f62e2e79ccba8884f6bf7a089dce15a9cf58dc8353e63550cfb142d8
```

Build a separate checkout with the same `PROJECT_VER`, `DEPTH=16`, and
`BUILD_NUMBER` as the flake. Copy the generic preset to `sdkconfig`, append
`CONFIG_SQUEEZEAMPAGAIN=y` and `CONFIG_SPKFAULT_GPIO=36`, and run `idf.py build`.
Do not use `buildFirmware.sh` after selecting the board: it recopies the generic
preset. Preserve the reference artifacts before subsequent builds.

Put `sdkconfig`, `squeezelite.bin`, `squeezelite.elf`, and `partition-table.bin`
in each comparison directory, then run:

```
nix develop -c python nix/compare.py REFERENCE NIX_OUTPUT PROJECT_VERSION
nix build --rebuild
```

The comparison requires identical configuration, partition bytes, and every
allocated ELF section's contents, address, size and flags. It ignores only the
application descriptor's date/time and ELF-digest fields, not code or board
settings. `--rebuild` independently rebuilds the Nix derivation and checks its
outputs against the previous realization.

# Validation record

Validated on Linux with Alex's `4eed7acd` baseline and upstream release
`I2S-4MFlash.16.1737.master-v4.3` (`f8a2904b`) plus his board patch.
Both versions passed container/native section comparisons and independent
`nix build --rebuild` checks. Three application-only OTAs passed boot, Wi-Fi,
and web-interface smoke tests: container baseline, native baseline, and native
`1737`. Existing settings survived; `1737` added an empty `volume_rotary` setting.
Audio and long-term reliability were not tested.

The validated native `1737` image is 2,652,880 bytes, with SHA-256
`177d76c8f66d0092167f56b04bf81b228b558f12fefa862cd9c21d4655578851`.
The native baseline is preserved at the `archive/baseline-nix-validated` tag.

# OTA and recovery

Back up configuration privately before updating. The application-only upload
does not write the bootloader, partition table, recovery application, or NVS
settings. Wi-Fi should therefore survive an update with this layout, but future
settings migrations still need review.

This firmware has a recovery application and **one** playback application slot,
not two interchangeable playback slots. Reboot into recovery first and confirm
that it reconnects and reports `recovery: 1` from `/status.json`. Local upload to
`/flash.json` buffers the entire image in PSRAM before erasing and writing
`ota_0`. Image validation precedes boot selection, but the old playback image
is overwritten. A failed upload can leave recovery usable; a bad application
boot does not guarantee automatic rollback. Rebooting first is not a guarantee
against power loss or hardware faults.

Upload only `squeezelite.bin`. Wait for the device to report `recovery: 0`, the
expected version, Wi-Fi connectivity and a working web UI. These are smoke tests,
not audio or long-term stability tests. Do not hammer the device with concurrent
monitoring while updating.

`result/serial` contains the separate artifacts and flash arguments for physical
USB recovery. Inspect its partition layout and the device's actual flash size
before using it. It is not an OTA bundle or a backup of device-specific settings.
A complete flash backup requires a suitable serial connection; the web
configuration export is not a substitute.
