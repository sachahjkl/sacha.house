{
  description = "sacha.house Go application";

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
    nixpkgs-secretspec.url = "github:NixOS/nixpkgs/master";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, nixpkgs-secretspec, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        secretspec = nixpkgs-secretspec.legacyPackages.${system}.secretspec;
        lib = pkgs.lib;
        pname = "sacha.house";
        versionPrefix = lib.strings.trim (builtins.readFile ./VERSION);
        gitCommitHash =
          if self ? shortRev then self.shortRev
          else if self ? dirtyShortRev then self.dirtyShortRev
          else "dev";
        packageVersion = "${versionPrefix}+${gitCommitHash}";
        linuxArch =
          if system == "x86_64-linux" then "amd64"
          else if system == "aarch64-linux" then "arm64"
          else system;
        source = lib.cleanSource ./.;
        sachaHouse = pkgs.buildGoModule {
          inherit pname;
          version = packageVersion;
          src = source;
          vendorHash = "sha256-xE5teCK+yueLLGycyFl+EFtWhV/5zqBHw8Y3YpLp8LY=";
          subPackages = [ "cmd/sacha-house" ];
          nativeBuildInputs = [
            pkgs.tailwindcss_4
          ];
          overrideModAttrs = _: { preBuild = null; };
          env.CGO_ENABLED = 0;
          ldflags = [
            "-s"
            "-w"
            "-X main.version=${packageVersion}"
            "-X main.commitHash=${gitCommitHash}"
          ];
          preBuild = ''
            export HOME="$TMPDIR"
            go tool templ generate
            tailwindcss -i ./styles/app.css -o ./internal/web/static/css/style.css
          '';
          postInstall = ''
            mv "$out/bin/sacha-house" "$out/bin/sacha.house"
          '';
        };
        linuxBinary = pkgs.runCommand "${pname}-linux-${linuxArch}" { } ''
          install -Dm755 ${sachaHouse}/bin/sacha.house "$out/${pname}-linux-${linuxArch}"
        '';
      in {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            bun
            go
            just
            sops
            secretspec
            watchexec
            git
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
          inherit secretspec;
        } // lib.optionalAttrs pkgs.stdenv.isLinux {
          inherit linuxBinary;
          dockerImage = pkgs.dockerTools.buildLayeredImage {
            name = "sacha.house";
            tag = gitCommitHash;
            contents = [
              sachaHouse
              pkgs.cacert
              pkgs.tzdata
            ];
            fakeRootCommands = ''
              mkdir -p ./data
              chown 65532:65532 ./data
              chmod 0700 ./data
            '';
            config = {
              User = "65532:65532";
              WorkingDir = "/data";
              Env = [
                "CONFIG_PATH=/data/config.json"
                "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
              ];
              Volumes = {
                "/data" = { };
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
          secretspec = self.packages.${pkgs.stdenv.hostPlatform.system}.secretspec;
          secretExec = pkgs.writeShellScript "sacha-house-with-secrets" ''
            export SOPS_AGE_KEY_FILE="$CREDENTIALS_DIRECTORY/sops-age-key"
            exec ${secretspec}/bin/secretspec \
              --file ${self}/secretspec.toml \
              --reason "Start sacha.house service" \
              run --profile production --scope runtime -- ${pkg}/bin/sacha.house
          '';
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
              default = "${cfg.dataDir}/config.json";
              description = "Path to the sacha.house JSON config file.";
            };

            openFirewall = mkOption {
              type = types.bool;
              default = false;
              description = "Open the configured port in the firewall.";
            };

            secrets = {
              enable = mkEnableOption "SecretSpec SOPS secret injection";

              ageKeyFile = mkOption {
                type = types.str;
                example = "/var/lib/sops-nix/key.txt";
                description = "Root-readable age identity passed to the service as a systemd credential.";
              };
            };
          };

          config = mkIf cfg.enable {
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

              path = optionals cfg.secrets.enable [ pkgs.sops ];

              serviceConfig = {
                Type = "simple";
                User = "sacha-house";
                Group = "sacha-house";
                WorkingDirectory = cfg.dataDir;
                ExecStart = if cfg.secrets.enable then secretExec else "${pkg}/bin/sacha.house";
                Restart = "on-failure";
                RestartSec = 5;
                NoNewPrivileges = true;
                PrivateTmp = true;
                ProtectHome = true;
                ProtectSystem = "strict";
                ReadWritePaths = [ cfg.dataDir ];
                Environment = [
                  "CONFIG_PATH=${cfg.configFile}"
                  "PORT=${toString cfg.port}"
                ];
              } // optionalAttrs cfg.secrets.enable {
                LoadCredential = [ "sops-age-key:${cfg.secrets.ageKeyFile}" ];
              };
            };

            networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];
          };
        };
    };
}
