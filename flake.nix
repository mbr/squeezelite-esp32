{
  description = "Native ESP-IDF firmware build for SqueezeAMPagain";

  # `nix develop` takes its interactive shell from the input named `nixpkgs`.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-23.11-darwin";
  inputs.nixpkgs-linux.url = "github:NixOS/nixpkgs/nixos-23.11";

  outputs = { self, nixpkgs, nixpkgs-linux }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [ "x86_64-linux" "x86_64-darwin" "aarch64-darwin" ];
      perSystem = system:
        let
          pkgs = import (if nixpkgs.lib.hasSuffix "-darwin" system then nixpkgs else nixpkgs-linux) { inherit system; };
          lib = pkgs.lib;
          python = pkgs.python311.override {
            packageOverrides = final: prev: {
              pyparsing = prev.pyparsing.overridePythonAttrs (_: {
                version = "2.3.1";
                pyproject = null;
                format = "setuptools";
                src = pkgs.fetchurl {
                  url = "https://files.pythonhosted.org/packages/source/p/pyparsing/pyparsing-2.3.1.tar.gz";
                  hash = "sha256-ZskmiGJkGrysSpa6dFBuWUyITj9XaQppbSGtghDtZno=";
                };
                postPatch = ''
                  substituteInPlace pyparsing.py --replace 'collections.MutableMapping' 'collections.abc.MutableMapping'
                '';
                doCheck = false;
              });
              kconfiglib = prev.kconfiglib.overridePythonAttrs (_: {
                version = "13.7.1";
                src = pkgs.fetchurl {
                  url = "https://files.pythonhosted.org/packages/source/k/kconfiglib/kconfiglib-13.7.1.tar.gz";
                  hash = "sha256-ou6PsGECRCxFllsFlpRPAsKhUX8JL6IIyjB/P9EqCiI=";
                };
                doCheck = false;
              });
              bitstring = prev.bitstring.overridePythonAttrs (_: {
                version = "3.1.9";
                pyproject = null;
                format = "setuptools";
                src = pkgs.fetchurl {
                  url = "https://files.pythonhosted.org/packages/source/b/bitstring/bitstring-3.1.9.tar.gz";
                  hash = "sha256-pYSKP2MRF4UiTcqLtMCnW2Ls3vVqBCyNa+dLFvfoYOc=";
                };
                doCheck = false;
              });
            };
          };
          pythonEnv = python.withPackages (p: with p; [
            setuptools
            click
            pyserial
            future
            cryptography
            pyparsing
            pyelftools
            kconfiglib
            reedsolo
            bitstring
            ecdsa
            construct
            pyyaml
            protobuf
          ]);
          toolchain = pkgs.stdenv.mkDerivation {
            pname = "xtensa-esp32-elf";
            version = "esp-2021r2-patch3-8.4.0";
            src = pkgs.fetchurl (if pkgs.stdenv.isDarwin then {
              url = "https://github.com/espressif/crosstool-NG/releases/download/esp-2021r2-patch3/xtensa-esp32-elf-gcc8_4_0-esp-2021r2-patch3-macos.tar.gz";
              hash = "sha256-3aPXpD79mV2aUdWldBYm2/kV30YHiu8LWupxY6yCOYs=";
            } else {
              url = "https://github.com/espressif/crosstool-NG/releases/download/esp-2021r2-patch3/xtensa-esp32-elf-gcc8_4_0-esp-2021r2-patch3-linux-amd64.tar.gz";
              sha256 = "9edd1e77627688f435561922d14299f6a0021ba1f6ff67e472e1108695a69e53";
            });
            nativeBuildInputs = lib.optionals pkgs.stdenv.isLinux [ pkgs.autoPatchelfHook ];
            buildInputs = lib.optionals pkgs.stdenv.isLinux [ pkgs.stdenv.cc.cc.lib pkgs.ncurses5 pkgs.expat ];
            postPatch = ''
              rm bin/xtensa-esp32-elf-gdb bin/xtensa-esp32-elf-gdb-add-index
            '';
            dontConfigure = true;
            dontBuild = true;
            dontStrip = true;
            installPhase = ''
              mkdir -p $out
              cp -a . $out/
            '';
          };
          cmake = pkgs.stdenv.mkDerivation ({
            pname = "cmake-esp-idf";
            version = "3.16.4";
            src = pkgs.fetchurl (if pkgs.stdenv.isDarwin then {
              url = "https://github.com/Kitware/CMake/releases/download/v3.16.4/cmake-3.16.4-Darwin-x86_64.tar.gz";
              hash = "sha256-9g4O+W2khyXNjafWq+g82VARZ6pRYlyQ3U0xCBpjEnk=";
            } else {
              url = "https://github.com/Kitware/CMake/releases/download/v3.16.4/cmake-3.16.4-Linux-x86_64.tar.gz";
              sha256 = "12a577aa04b6639766ae908f33cf70baefc11ac4499b8b1c8812d99f05fb6a02";
            });
            nativeBuildInputs = lib.optionals pkgs.stdenv.isLinux [ pkgs.autoPatchelfHook ];
            buildInputs = lib.optionals pkgs.stdenv.isLinux [ pkgs.stdenv.cc.cc.lib ];
            dontConfigure = true;
            dontBuild = true;
            installPhase = ''
              rm bin/ccmake bin/cmake-gui
              mkdir -p $out
              cp -a . $out/
            '';
          } // lib.optionalAttrs pkgs.stdenv.isDarwin {
            postUnpack = ''
              sourceRoot="$sourceRoot/CMake.app/Contents"
            '';
          });
          idf = pkgs.stdenvNoCC.mkDerivation {
            pname = "esp-idf";
            version = "4.3.5";
            src = pkgs.fetchurl {
              url = "https://github.com/espressif/esp-idf/releases/download/v4.3.5/esp-idf-v4.3.5.zip";
              hash = "sha256-nhlj+Z1emiELadQDbBRgemFRn3uIuDHqKY3AeqfHQ9w=";
            };
            nativeBuildInputs = [ pkgs.unzip ];
            dontConfigure = true;
            dontBuild = true;
            installPhase = ''
              find . -name .git -prune -exec rm -rf {} +
              cp ${./docker/patches/tools/ldgen/fragments.py} tools/ldgen/fragments.py
              printf 'v4.3.5-dirty\n' > version.txt
              mkdir -p $out
              cp -a . $out/
            '';
          };
          submodules = [
            {
              path = "components/esp-dsp";
              src = pkgs.fetchFromGitHub {
                owner = "philippe44";
                repo = "esp-dsp";
                rev = "8b082c1071497d49346ee6ed55351470c1cb4264";
                sha256 = "0r3xx19mkpgzsvbhc86yx4ch21g3147mki2rznv80mz4wv5b7r5n";
              };
            }
            {
              path = "components/telnet/libtelnet";
              src = pkgs.fetchFromGitHub {
                owner = "seanmiddleditch";
                repo = "libtelnet";
                rev = "4218ce9c01f6edb7d219b7a3590d9b3f75e12a74";
                sha256 = "1v76768y7fimx7hyfpvnq1an6l20r3rzrmgxdicrh6izvcyglk71";
              };
            }
            {
              path = "components/wifi-manager/UML-State-Machine-in-C";
              src = pkgs.fetchFromGitHub {
                owner = "kiishor";
                repo = "UML-State-Machine-in-C";
                rev = "96264241ad7a247ee143acbf81005ba82802d1fa";
                sha256 = "193hq73bzkbcaxpm30x6znfqxkq6w1awxsywcvgjflvxd1s8894z";
              };
            }
          ];
          tools = [ toolchain pythonEnv cmake pkgs.ninja pkgs.git pkgs.protobuf pkgs.pkg-config ];
          firmware = pkgs.stdenvNoCC.mkDerivation {
            pname = "squeezeampagain-firmware";
            version = "1737-wifi2";
            src = lib.cleanSourceWith {
              src = self;
              filter = path: type:
                lib.cleanSourceFilter path type && !(builtins.elem (baseNameOf path) [
                  "flake.nix"
                  "flake.lock"
                  "nix"
                  "NIX.md"
                  "check.sh"
                  "format.sh"
                ]);
            };
            nativeBuildInputs = tools;
            IDF_PATH = idf;
            IDF_CCACHE_ENABLE = "0";
            IDF_COMPONENT_MANAGER = "0";
            PROJECT_VER = "I2S-4MFlash.16.1737.wifi2";
            dontUseCmakeConfigure = true;
            dontUseNinjaBuild = true;
            dontUseNinjaInstall = true;
            dontFixup = true;
            doInstallCheck = true;
            installCheckPhase = ''
              python ${./nix}/verify.py $out "$PROJECT_VER" > $out/manifest.json
              python ${./nix}/test_verify.py $out "$PROJECT_VER"
            '';
            postUnpack = lib.concatMapStringsSep "\n"
              (sub: ''
                mkdir -p "$sourceRoot/${sub.path}"
                cp -a ${sub.src}/. "$sourceRoot/${sub.path}/"
                chmod -R u+w "$sourceRoot/${sub.path}"
              '')
              submodules;
            configurePhase = ''
              runHook preConfigure
              export HOME=$TMPDIR
              patchShebangs components/spotify/cspot/bell/external/nanopb/generator
              cp build-scripts/I2S-4MFlash-sdkconfig.defaults sdkconfig
              printf '\nCONFIG_SQUEEZEAMPAGAIN=y\nCONFIG_SPKFAULT_GPIO=36\n' >> sdkconfig
              cmake -S . -B build -G Ninja -DPYTHON=${pythonEnv}/bin/python \
                -DPYTHON_DEPS_CHECKED=1 -DIDF_TARGET=esp32 -DCCACHE_ENABLE=0 \
                -DDEPTH=16 -DBUILD_NUMBER=1737-16
              runHook postConfigure
            '';
            buildPhase = ''
              runHook preBuild
              ninja -C build -j$NIX_BUILD_CORES
              runHook postBuild
            '';
            installPhase = ''
              runHook preInstall
              mkdir -p $out
              cp build/squeezelite.bin build/squeezelite.elf build/squeezelite.map sdkconfig partitions.csv $out/
              cp build/partition_table/partition-table.bin $out/
              mkdir -p $out/serial/bootloader $out/serial/partition_table
              cp build/recovery.bin build/squeezelite.bin build/ota_data_initial.bin \
                build/flash_project_args build/flasher_args.json $out/serial/
              cp build/bootloader/bootloader.bin $out/serial/bootloader/
              cp build/partition_table/partition-table.bin $out/serial/partition_table/
              runHook postInstall
            '';
          };
        in
        {
          packages = { default = firmware; inherit firmware toolchain idf; };
          checks.firmware = firmware;
          formatter = pkgs.nixpkgs-fmt;
          devShells.default = pkgs.mkShell {
            packages = tools ++ [ pkgs.python311Packages.black ];
            IDF_PATH = idf;
            IDF_CCACHE_ENABLE = "0";
            IDF_COMPONENT_MANAGER = "0";
          };
        };
    in
    {
      packages = forAllSystems (system: (perSystem system).packages);
      checks = forAllSystems (system: (perSystem system).checks);
      formatter = forAllSystems (system: (perSystem system).formatter);
      devShells = forAllSystems (system: (perSystem system).devShells);
    };
}
