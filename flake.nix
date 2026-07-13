{
  description = "Development shell for sacha.house";

  nixConfig = {
    extra-substituters = [
      "https://sachahjkl.cachix.org"
    ];
    extra-trusted-public-keys = [
      "sachahjkl.cachix.org-1:cepX7PCUV88hCchnh9prZM5V72wRkCf6oSJL6JfgWs0="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        lib = pkgs.lib;
        pname = "sacha.house";
        versionPrefix = lib.strings.trim (builtins.readFile ./VERSION);
        gitCommitHash =
          if self ? shortRev then self.shortRev
          else if self ? dirtyShortRev then self.dirtyShortRev
          else "dev";
        packageVersion = "${versionPrefix}+${gitCommitHash}";
        stdcppLibbacktraceCompat = pkgs.runCommand "stdcxx-libbacktrace-compat"
          {
            nativeBuildInputs = [ pkgs.clang ];
          } ''
          mkdir -p "$out/lib"

          cat > compat.c <<'EOF'
          #include <backtrace.h>
          #include <stdlib.h>

          struct backtrace_state *__glibcxx_backtrace_create_state(
            const char *filename,
            int threaded,
            void (*error_callback)(void *data, const char *msg, int errnum),
            void *data
          ) {
            return backtrace_create_state(filename, threaded, error_callback, data);
          }

          int __glibcxx_backtrace_simple(
            struct backtrace_state *state,
            int skip,
            int (*callback)(void *data, uintptr_t pc),
            void (*error_callback)(void *data, const char *msg, int errnum),
            void *data
          ) {
            return backtrace_simple(state, skip, callback, error_callback, data);
          }

          int __glibcxx_backtrace_pcinfo(
            struct backtrace_state *state,
            uintptr_t pc,
            int (*callback)(void *data, uintptr_t pc, const char *filename, int lineno, const char *function),
            void (*error_callback)(void *data, const char *msg, int errnum),
            void *data
          ) {
            return backtrace_pcinfo(state, pc, callback, error_callback, data);
          }

          int __glibcxx_backtrace_syminfo(
            struct backtrace_state *state,
            uintptr_t addr,
            void (*callback)(void *data, uintptr_t pc, const char *symname, uintptr_t symval, uintptr_t symsize),
            void (*error_callback)(void *data, const char *msg, int errnum),
            void *data
          ) {
            return backtrace_syminfo(state, addr, callback, error_callback, data);
          }

          void __glibcxx_backtrace_free(struct backtrace_state *state) {
            free(state);
          }
          EOF

          clang -shared -fPIC compat.c \
            -I${pkgs.libbacktrace}/include \
            -L${pkgs.libbacktrace}/lib -lbacktrace \
            -o "$out/lib/libstdc++_libbacktrace.so"
        '';
        runtimeLibraries = [
          pkgs.openssl
          pkgs.cmark
          pkgs.libbacktrace
          pkgs.stdenv.cc.cc.lib
          stdcppLibbacktraceCompat
        ];
        runtimeLibraryPath = lib.makeLibraryPath runtimeLibraries;
        linuxArch =
          if system == "x86_64-linux" then "amd64"
          else if system == "aarch64-linux" then "arm64"
          else system;
        fhsDynamicLinker =
          if system == "x86_64-linux" then "/lib64/ld-linux-x86-64.so.2"
          else if system == "aarch64-linux" then "/lib/ld-linux-aarch64.so.1"
          else null;
        fhsLibraryPath = lib.concatStringsSep ":" [
          "/usr/lib/${pkgs.stdenv.hostPlatform.config}"
          "/lib/${pkgs.stdenv.hostPlatform.config}"
          "/usr/lib64"
          "/usr/lib"
          "/lib64"
          "/lib"
        ];
        sachaHouse = pkgs.stdenv.mkDerivation {
          inherit pname;
          version = packageVersion;
          src = lib.cleanSourceWith {
            src = ./.;
            filter = path: type:
              let
                name = baseNameOf path;
              in
                lib.cleanSourceFilter path type
                && name != "config.json"
                && !(lib.hasPrefix "paste-secrets" name && lib.hasSuffix ".json" name);
          };
          npmDeps = pkgs.importNpmLock {
            npmRoot = ./.;
          };
          nativeBuildInputs = [
            pkgs.nodejs
            pkgs.odin
            pkgs.importNpmLock.hooks.npmConfigHook
          ];
          buildInputs = runtimeLibraries;
          LD_LIBRARY_PATH = runtimeLibraryPath;
          LIBRARY_PATH = runtimeLibraryPath;
          buildPhase = ''
            runHook preBuild
            export HOME="$TMPDIR"
            odin build lib/temple/cli -o:speed -out:temple_cli
            ./temple_cli src lib/temple
            npm run build:css
            odin build src \
              -out:sacha.house \
              -define:GIT_COMMIT_HASH="'${gitCommitHash}'" \
              -define:VERSION="'${packageVersion}'" \
              -collection:lib=lib \
              -o:speed \
              -define:TRACK_LEAKS=false \
              -build-mode:exe
            runHook postBuild
          '';
          installPhase = ''
            runHook preInstall
            mkdir -p $out/bin
            cp sacha.house $out/bin/sacha.house
            runHook postInstall
          '';
        };
        linuxBinary = pkgs.runCommand "${pname}-linux-${linuxArch}"
          {
            nativeBuildInputs = [ pkgs.patchelf ];
          } ''
          install -Dm755 ${sachaHouse}/bin/sacha.house "$out/${pname}-linux-${linuxArch}"
          chmod u+w "$out/${pname}-linux-${linuxArch}"
          patchelf \
            --set-interpreter ${fhsDynamicLinker} \
            --set-rpath ${lib.escapeShellArg fhsLibraryPath} \
            "$out/${pname}-linux-${linuxArch}"
        '';
      in {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            bun
            just
            odin
            clang
            pkg-config
            openssl
            cmark
            libbacktrace
            stdenv.cc.cc.lib
            git
            stdcppLibbacktraceCompat
          ];

          LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath [
            pkgs.openssl
            pkgs.cmark
            pkgs.libbacktrace
            pkgs.stdenv.cc.cc.lib
            stdcppLibbacktraceCompat
          ];

          LIBRARY_PATH = pkgs.lib.makeLibraryPath [
            pkgs.openssl
            pkgs.cmark
            pkgs.libbacktrace
            pkgs.stdenv.cc.cc.lib
            stdcppLibbacktraceCompat
          ];

          shellHook = ''
            export CONFIG_PATH="$PWD/config.json"

            if [ ! -f config.json ] && [ -f config.example.json ]; then
              cp config.example.json config.json
              echo "Created config.json from config.example.json"
            fi

            if [ -f bun.lock ]; then
              bun install --frozen-lockfile
            else
              bun install
            fi

            echo "Dev shell ready. Common commands: just dev, just build release"
          '';
        };

        packages = {
          default = sachaHouse;
        } // lib.optionalAttrs pkgs.stdenv.isLinux {
          inherit linuxBinary;
          dockerImage = pkgs.dockerTools.buildLayeredImage {
            name = "sacha.house";
            tag = gitCommitHash;
            contents = [
              sachaHouse
              pkgs.cacert
              pkgs.tzdata
            ] ++ runtimeLibraries;
            extraCommands = ''
              mkdir -p ./etc ./data/tmp
              chmod 0755 ./etc
              chmod 0700 ./data ./data/tmp
              printf '%s\n' 'sacha-house:x:10001:10001:sacha.house:/data:/bin/false' > ./etc/passwd
              printf '%s\n' 'sacha-house:x:10001:' > ./etc/group
              chmod 0644 ./etc/passwd ./etc/group
            '';
            fakeRootCommands = ''
              chown -R 10001:10001 ./data
            '';
            config = {
              WorkingDir = "/data";
              User = "10001:10001";
              Env = [
                "CONFIG_PATH=/config/config.json"
                "HOME=/data"
                "TMPDIR=/data/tmp"
                "LD_LIBRARY_PATH=${runtimeLibraryPath}"
                "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
              ];
              Volumes = {
                "/data" = { };
                "/run/secrets" = { };
              };
              ExposedPorts = {
                "6969/tcp" = { };
              };
              Cmd = [ "/bin/sacha.house" ];
            };
          };
        };
      })
    // {
      nixosModules.default = { config, lib, pkgs, ... }:
        with lib;
        let
          cfg = config.services.sacha-house;
          pkg = cfg.package;
        in {
          options.services.sacha-house = {
            enable = mkEnableOption "sacha.house web service";

            package = mkOption {
              type = types.package;
              default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
              defaultText = literalExpression "sacha-house.packages.\${pkgs.stdenv.hostPlatform.system}.default";
              description = "Package to run for the sacha.house service.";
            };

            port = mkOption {
              type = types.port;
              default = 6969;
              description = "Port to listen on.";
            };

            dataDir = mkOption {
              type = types.path;
              default = "/var/lib/sacha.house";
              description = "Writable directory for runtime data and caches.";
            };

            configFile = mkOption {
              type = types.path;
              default = "/etc/sacha.house/config.json";
              description = "Path to the sacha.house JSON config file.";
            };

            pasteSecretsFile = mkOption {
              type = types.nullOr types.str;
              default = null;
              example = "/run/secrets/sacha-house-pastes.json";
              description = "Optional paste secrets JSON path to grant read-only access; set the same path in PASTE_SECRETS_FILE inside config.json.";
            };

            openFirewall = mkOption {
              type = types.bool;
              default = false;
              description = "Open the configured port in the firewall.";
            };
          };

          config = mkIf cfg.enable {
            assertions = [
              {
                assertion = !hasPrefix "/nix/store/" (toString cfg.configFile);
                message = "services.sacha-house.configFile must be a runtime path, not a Nix store path";
              }
              {
                assertion = cfg.pasteSecretsFile == null || !hasPrefix "/nix/store/" cfg.pasteSecretsFile;
                message = "services.sacha-house.pasteSecretsFile must be a runtime path, not a Nix store path";
              }
            ];
            users.users.sacha-house = {
              isSystemUser = true;
              group = "sacha-house";
              home = cfg.dataDir;
              createHome = true;
            };
            users.groups.sacha-house = { };

            systemd.services.sacha-house = {
              description = "sacha.house web service";
              after = [ "network.target" ];
              wantedBy = [ "multi-user.target" ];

              serviceConfig = {
                Type = "simple";
                User = "sacha-house";
                Group = "sacha-house";
                WorkingDirectory = cfg.dataDir;
                ExecStart = "${pkg}/bin/sacha.house";
                Restart = "on-failure";
                RestartSec = 5;
                UMask = "0077";
                NoNewPrivileges = true;
                PrivateTmp = true;
                ProtectHome = true;
                ProtectSystem = "strict";
                ReadWritePaths = [ cfg.dataDir ];
                ReadOnlyPaths = optional (cfg.pasteSecretsFile != null) cfg.pasteSecretsFile;
                PrivateDevices = true;
                ProtectClock = true;
                ProtectControlGroups = true;
                ProtectKernelLogs = true;
                ProtectKernelModules = true;
                ProtectKernelTunables = true;
                ProtectProc = "invisible";
                RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
                RestrictSUIDSGID = true;
                LockPersonality = true;
                SystemCallArchitectures = "native";
                Environment = [
                  "CONFIG_PATH=${cfg.configFile}"
                  "PORT=${toString cfg.port}"
                ];
              };
            };

            networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];
          };
        };
    };
}
