{
  description = "Development shell for sacha.house";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };
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
      });
}
