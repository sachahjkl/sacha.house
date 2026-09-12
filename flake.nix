{
  description = "sacha.house Go application";

  nixConfig = {
    extra-substituters = [
      "https://nix-community.cachix.org"
      "https://sachahjkl.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "sachahjkl.cachix.org-1:cepX7PCUV88hCchnh9prZM5V72wRkCf6oSJL6JfgWs0="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-secretspec.url = "github:NixOS/nixpkgs/master";
    flake-utils.url = "github:numtide/flake-utils";
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    nixpkgs-secretspec,
    flake-utils,
    git-hooks,
  }:
    flake-utils.lib.eachSystem [
      "x86_64-linux"
      "aarch64-linux"
    ] (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      secretspec = nixpkgs-secretspec.legacyPackages.${system}.secretspec;
      lib = pkgs.lib;
      pname = "sacha.house";
      vendorHash = "sha256-iHJ7Hl7GVWU9kdjuostzgdSdq1Fo+AINCuH5bTHUpY8=";
      versionPrefix = lib.strings.trim (builtins.readFile ./VERSION);
      gitCommitHash =
        if self ? shortRev
        then self.shortRev
        else if self ? dirtyShortRev
        then self.dirtyShortRev
        else "dev";
      packageVersion = "${versionPrefix}+${gitCommitHash}";
      linuxArch =
        if system == "x86_64-linux"
        then "amd64"
        else if system == "aarch64-linux"
        then "arm64"
        else system;
      source = lib.cleanSource ./.;
      sachaHouse = pkgs.buildGoModule {
        inherit pname;
        version = packageVersion;
        src = source;
        inherit vendorHash;
        subPackages = ["cmd/sacha-house"];
        nativeBuildInputs = [
          pkgs.tailwindcss_4
        ];
        overrideModAttrs = _: {preBuild = null;};
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
      linuxBinary = pkgs.runCommand "${pname}-linux-${linuxArch}" {} ''
        install -Dm755 ${sachaHouse}/bin/sacha.house "$out/${pname}-linux-${linuxArch}"
      '';
      dockerImage = pkgs.dockerTools.buildLayeredImage {
        name = "sacha.house";
        tag = gitCommitHash;
        contents = [
          sachaHouse
          pkgs.busybox
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
            "HOST=0.0.0.0"
            "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
          ];
          Volumes = {
            "/data" = {};
          };
          ExposedPorts = {
            "6969/tcp" = {};
          };
          Cmd = ["/bin/sacha.house"];
        };
      };
      goTests = pkgs.buildGoModule {
        pname = "${pname}-go-tests";
        version = packageVersion;
        src = source;
        inherit vendorHash;
        overrideModAttrs = _: {preBuild = null;};
        env.CGO_ENABLED = 0;
        doCheck = false;
        buildPhase = ''
          runHook preBuild
          go vet ./...
          go test ./...
          runHook postBuild
        '';
        installPhase = ''
          runHook preInstall
          touch "$out"
          runHook postInstall
        '';
      };
      preCommitCheck = git-hooks.lib.${system}.run {
        package = pkgs.prek;
        src = ./.;
        hooks = {
          actionlint.enable = true;
          alejandra.enable = true;
          check-added-large-files.enable = true;
          check-json.enable = true;
          check-merge-conflicts.enable = true;
          check-yaml.enable = true;
          end-of-file-fixer = {
            enable = true;
            excludes = [
              "^internal/web/static/(atom|rss)\\.svg$"
              "^internal/web/static/(robots\\.txt|sachahjkl\\.gpg)$"
            ];
          };
          gofmt.enable = true;
          shellcheck = {
            enable = true;
            args = ["-e" "SC2034,SC2155,SC2329"];
            excludes = ["^\\.envrc$"];
          };
          trim-trailing-whitespace = {
            enable = true;
            excludes = ["^data/blog/"];
          };
        };
      };
    in {
      formatter = pkgs.alejandra;

      devShells.default = pkgs.mkShell {
        packages =
          preCommitCheck.enabledPackages
          ++ (with pkgs; [
            bun
            go
            just
            sops
            secretspec
            watchexec
            git
          ]);

        shellHook = ''
          ${preCommitCheck.shellHook}
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

      packages =
        {
          default = sachaHouse;
          inherit secretspec;
        }
        // lib.optionalAttrs pkgs.stdenv.isLinux {
          inherit linuxBinary dockerImage;
        };

      checks =
        {
          go-tests = goTests;
          package = sachaHouse;
          pre-commit = preCommitCheck;
        }
        // lib.optionalAttrs pkgs.stdenv.isLinux {
          inherit linuxBinary dockerImage;
        };
    });
}
