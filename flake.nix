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
              ({ pkgs, lib, config, ... }: {
                languages.c.enable = true;

                # Only provide the base interpreter — ESP-IDF creates its
                # own venv inside $IDF_TOOLS_PATH during install.
                languages.python.enable = true;

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
                  ESP_IDF_VERSION = esp-idf-version;
                  ESP_IDF_CHIPS = esp-idf-chips;
                  CMAKE_PREFIX_PATH = "${pkgs.cjson}";
                };

                enterShell = ''
                  # Keep ESP-IDF and its toolchains entirely inside .devenv/
                  export IDF_TOOLS_PATH="$DEVENV_STATE/espressif"
                  export IDF_PATH="$DEVENV_STATE/esp-idf"
                  export ESP_IDF_DIR="$IDF_PATH"

                  if [ ! -f "$IDF_PATH/export.sh" ]; then
                    echo ""
                    echo "ESP-IDF not found. Run: zclaw-install-idf"
                    echo ""
                  else
                    source "$IDF_PATH/export.sh" 2>/dev/null

                    if command -v idf.py >/dev/null 2>&1; then
                      echo "zclaw dev shell ready (ESP-IDF $(cat "$IDF_PATH/version.txt" 2>/dev/null || echo "${esp-idf-version}"))"
                    else
                      echo "Warning: ESP-IDF export.sh failed. Try: zclaw-install-idf"
                    fi
                  fi
                '';

                scripts = {
                  zclaw-install-idf.exec = ''
                    set -e
                    export IDF_TOOLS_PATH="$DEVENV_STATE/espressif"
                    export IDF_PATH="$DEVENV_STATE/esp-idf"

                    if [ -d "$IDF_PATH" ]; then
                      echo "Updating ESP-IDF..."
                      cd "$IDF_PATH"
                      git fetch
                      git checkout ${esp-idf-version}
                      git submodule update --init --recursive
                    else
                      echo "Cloning ESP-IDF ${esp-idf-version}..."
                      git clone -b ${esp-idf-version} --recursive \
                        https://github.com/espressif/esp-idf.git "$IDF_PATH"
                    fi

                    cd "$IDF_PATH" && ./install.sh ${esp-idf-chips}
                    echo ""
                    echo "Activating ESP-IDF..."
                    source "$IDF_PATH/export.sh"
                    echo "Done. idf.py is now available."
                  '';
                  zclaw-install-idf.description = "Clone and install ESP-IDF toolchain (self-contained in .devenv/)";

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
