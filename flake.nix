{
  description = "zclaw - ESP32 AI assistant development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    devenv.url = "github:cachix/devenv";
  };

  nixConfig = {
    extra-trusted-public-keys = "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw=";
    extra-substituters = "https://devenv.cachix.org";
  };

  outputs = { self, nixpkgs, devenv, ... } @ inputs:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forEachSystem = nixpkgs.lib.genAttrs systems;

      esp-idf-version = "v5.4";
      esp-idf-dir = "$HOME/esp/esp-idf";
      esp-idf-chips = "esp32,esp32c3,esp32c6,esp32s3";
    in
    {
      devShells = forEachSystem (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = devenv.lib.mkShell {
            inherit inputs pkgs;
            modules = [
              ({ pkgs, lib, ... }: {
                languages.c.enable = true;

                languages.python = {
                  enable = true;
                  venv.enable = true;
                };

                packages = with pkgs; [
                  cmake
                  ninja
                  ccache
                  git
                  wget
                  curl
                  dfu-util
                  libusb1
                  libffi
                  openssl
                  cjson
                  qemu
                ] ++ lib.optionals stdenv.isLinux [
                  flex
                  bison
                  gperf
                ];

                env = {
                  ESP_IDF_DIR = esp-idf-dir;
                  ESP_IDF_VERSION = esp-idf-version;
                  ESP_IDF_CHIPS = esp-idf-chips;
                  CMAKE_PREFIX_PATH = "${pkgs.cjson}";
                };

                enterShell = ''
                  if [ ! -f "$ESP_IDF_DIR/export.sh" ]; then
                    echo ""
                    echo "ESP-IDF not found at $ESP_IDF_DIR"
                    echo "Run: zclaw-install-idf"
                    echo ""
                  else
                    source "$ESP_IDF_DIR/export.sh" 2>/dev/null

                    if command -v idf.py >/dev/null 2>&1; then
                      echo "zclaw dev shell ready (ESP-IDF $(cat "$ESP_IDF_DIR/version.txt" 2>/dev/null || echo "${esp-idf-version}"))"
                    else
                      echo "Warning: ESP-IDF export.sh failed. Try: zclaw-install-idf"
                    fi
                  fi
                '';

                scripts = {
                  zclaw-install-idf.exec = ''
                    set -e
                    mkdir -p ~/esp
                    if [ -d "${esp-idf-dir}" ]; then
                      echo "Updating ESP-IDF..."
                      cd "${esp-idf-dir}"
                      git fetch
                      git checkout ${esp-idf-version}
                      git submodule update --init --recursive
                    else
                      echo "Cloning ESP-IDF ${esp-idf-version}..."
                      git clone -b ${esp-idf-version} --recursive \
                        https://github.com/espressif/esp-idf.git ${esp-idf-dir}
                    fi
                    cd ${esp-idf-dir} && ./install.sh ${esp-idf-chips}
                    echo ""
                    echo "Done. Re-enter the shell with: nix develop"
                  '';
                  zclaw-install-idf.description = "Clone and install ESP-IDF toolchain";

                  zclaw-build.exec = "idf.py build";
                  zclaw-build.description = "Build zclaw firmware";

                  zclaw-flash.exec = ''./scripts/flash.sh "$@"'';
                  zclaw-flash.description = "Flash firmware to ESP32";

                  zclaw-provision.exec = ''./scripts/provision.sh "$@"'';
                  zclaw-provision.description = "Provision WiFi + LLM + Telegram credentials";

                  zclaw-monitor.exec = ''./scripts/monitor.sh "$@"'';
                  zclaw-monitor.description = "Open serial monitor";
                };
              })
            ];
          };
        }
      );
    };
}
