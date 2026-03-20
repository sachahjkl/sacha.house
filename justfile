# sacha.house — `just --list` for recipes. Usage: `just build release`, env: GIT_COMMIT_HASH, VERSION

set windows-shell := ['cmd.exe', '/c']

odin_src := 'src'
odin_out := 'sacha.house.exe'
out_pdb := 'sacha.house.pdb'
odin_out_dev := 'sacha.house.dev.exe'
out_pdb_dev := 'sacha.house.dev.pdb'
dev_watcher_out := 'dev_watcher.exe'
lib := 'lib'
bun := 'bun'
temple_cli := 'temple_cli.exe'
temple_path := lib / 'temple'
out_css_file := odin_src / 'static' / 'css' / 'style.css'
port := '6969'
ssl_port := '3000'

git_commit_hash := env_var_or_default('GIT_COMMIT_HASH', 'dev')
version := env_var_or_default('VERSION', 'dev')

linker_flags := if os() == 'windows' {
  '-extra-linker-flags:/ignore:4099'
} else {
  ''
}

odin_default_flags := '-collection:lib=' + lib

default: build

# Optional: `just templates`, `just css`
[unix]
templates:
  @echo Building temple CLI...
  odin build {{ temple_path / 'cli' }} -o:speed -out:{{ temple_cli }}
  @echo Transpiling templates...
  ./{{ temple_cli }} {{ odin_src }} {{ temple_path }}

[windows]
templates:
  @if exist {{ temple_cli }} (echo Temple CLI up to date.) else (echo Building temple CLI... & odin build {{ temple_path / 'cli' }} -o:speed -out:{{ temple_cli }})
  @echo Transpiling templates...
  .\\{{ temple_cli }} {{ odin_src }} {{ temple_path }}

css:
  @echo Building Tailwind CSS...
  {{ bun }} run build:css

build mode='debug' out=odin_out: templates css
  @echo Building Odin application in {{ mode }} mode...
  odin build {{ odin_src }} -out:{{ out }} -define:GIT_COMMIT_HASH="'{{ git_commit_hash }}'" -define:VERSION="{{ version }}" {{ odin_default_flags }} {{ if mode == 'release' { '-o:speed -define:TRACK_LEAKS=false -build-mode:exe -lto:thin ' + linker_flags } else { '-debug -define:TRACK_LEAKS=true -build-mode:exe ' + linker_flags } }}

[unix]
run: build
  @echo Running 'sacha.house' web server...
  ./{{ odin_out }}

[windows]
run: build
  @echo Running 'sacha.house' web server...
  .\\{{ odin_out }}

run-ssl:
  @echo Running 'sacha.house' web server with SSL...
  {{ bun }} x local-ssl-proxy --source {{ ssl_port }} --target {{ port }} --cert localhost.pem --key localhost-key.pem

[windows]
clean:
  @echo Cleaning up build artifacts...
  @-del /F /Q {{ replace(odin_out, '/', '\\') }} 2>nul & del /F /Q {{ replace(out_pdb, '/', '\\') }} 2>nul & del /F /Q {{ replace(out_css_file, '/', '\\') }} 2>nul & del /F /Q {{ replace(temple_cli, '/', '\\') }} 2>nul & del /F /Q {{ replace(odin_out_dev, '/', '\\') }} 2>nul & del /F /Q {{ replace(out_pdb_dev, '/', '\\') }} 2>nul & del /F /Q {{ replace(dev_watcher_out, '/', '\\') }} 2>nul

[unix]
clean:
  @echo Cleaning up build artifacts...
  rm -f {{ odin_out }} {{ out_pdb }} {{ out_css_file }} {{ temple_cli }} {{ odin_out_dev }} {{ out_pdb_dev }} {{ dev_watcher_out }}

[unix]
dev: build-watcher
  ./dev_watcher.exe

[windows]
dev: build-watcher
  .\\dev_watcher.exe

build-watcher:
  @echo Building dev watcher...
  odin build tools/dev-watcher -out:dev_watcher.exe
