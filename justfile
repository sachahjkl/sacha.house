# sacha.house — `just --list` for recipes. Usage: `just build release`, env: GIT_COMMIT_HASH, VERSION

set windows-shell := ['cmd.exe', '/c']

odin_src := 'src'
arch_dir := arch()
bin_root := 'bin'
debug_dir := bin_root / 'debug' / arch_dir
release_dir := bin_root / 'release' / arch_dir
odin_out := debug_dir / 'sacha.house.exe'
odin_out_release := release_dir / 'sacha.house.exe'
out_pdb := debug_dir / 'sacha.house.pdb'
odin_out_dev := debug_dir / 'sacha.house.dev.exe'
out_pdb_dev := debug_dir / 'sacha.house.dev.pdb'
dev_watcher_out := debug_dir / 'dev_watcher.exe'
legacy_dev_out := 'sacha.house.dev.exe'
legacy_temple_cli := 'temple_cli.exe'
lib := 'lib'
bun := 'bun'
tools_dir := bin_root / 'tools'
temple_cli := tools_dir / 'temple_cli.exe'
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
  @mkdir -p {{ tools_dir }}
  @echo Building temple CLI...
  odin build {{ temple_path / 'cli' }} -o:speed -out:{{ temple_cli }}
  @echo Transpiling templates...
  ./{{ temple_cli }} {{ odin_src }} {{ temple_path }}

[windows]
templates:
  @if not exist {{ replace(tools_dir, '/', '\\') }} mkdir {{ replace(tools_dir, '/', '\\') }}
  @if exist {{ replace(temple_cli, '/', '\\') }} (echo Temple CLI up to date.) else (echo Building temple CLI... & odin build {{ temple_path / 'cli' }} -o:speed -out:{{ temple_cli }})
  @echo Transpiling templates...
  .\\{{ replace(temple_cli, '/', '\\') }} {{ odin_src }} {{ temple_path }}

css:
  @echo Building Tailwind CSS...
  {{ bun }} run build:css

[windows]
_ensure-bin-dirs:
  @if not exist {{ replace(debug_dir, '/', '\\') }} mkdir {{ replace(debug_dir, '/', '\\') }}
  @if not exist {{ replace(release_dir, '/', '\\') }} mkdir {{ replace(release_dir, '/', '\\') }}

[unix]
_ensure-bin-dirs:
  @mkdir -p {{ debug_dir }} {{ release_dir }}

build mode='debug' out='': templates css _ensure-bin-dirs
  @echo Building Odin application in {{ mode }} mode...
  odin build {{ odin_src }} -out:{{ if out != '' { out } else if mode == 'release' { odin_out_release } else { odin_out } }} -define:GIT_COMMIT_HASH="'{{ git_commit_hash }}'" -define:VERSION="{{ version }}" {{ odin_default_flags }} {{ if mode == 'release' { '-o:speed -define:TRACK_LEAKS=false -build-mode:exe ' + linker_flags } else { '-debug -define:TRACK_LEAKS=true -build-mode:exe ' + linker_flags } }}

[windows]
build-dev: templates css _ensure-bin-dirs
  @echo Building Odin application in debug-dev mode...
  odin build {{ odin_src }} -out:{{ odin_out_dev }} -define:GIT_COMMIT_HASH="'{{ git_commit_hash }}'" -define:VERSION="{{ version }}" {{ odin_default_flags }} -debug -define:TRACK_LEAKS=true -build-mode:exe {{ linker_flags }}
  @copy /Y {{ replace(odin_out_dev, '/', '\\') }} {{ legacy_dev_out }} >nul

[unix]
build-dev: templates css _ensure-bin-dirs
  @echo Building Odin application in debug-dev mode...
  odin build {{ odin_src }} -out:{{ odin_out_dev }} -define:GIT_COMMIT_HASH="'{{ git_commit_hash }}'" -define:VERSION="{{ version }}" {{ odin_default_flags }} -debug -define:TRACK_LEAKS=true -build-mode:exe {{ linker_flags }}
  @cp -f {{ odin_out_dev }} {{ legacy_dev_out }}

[unix]
run: build
  @echo Running 'sacha.house' web server...
  ./{{ odin_out }}

[windows]
run: build
  @echo Running 'sacha.house' web server...
  .\\{{ replace(odin_out, '/', '\\') }}

run-ssl:
  @echo Running 'sacha.house' web server with SSL...
  {{ bun }} x local-ssl-proxy --source {{ ssl_port }} --target {{ port }} --cert localhost.pem --key localhost-key.pem

[windows]
clean:
  @echo Cleaning up build artifacts...
  @-rmdir /S /Q {{ replace(bin_root, '/', '\\') }} 2>nul
  @-del /F /Q {{ replace(out_css_file, '/', '\\') }} 2>nul & del /F /Q {{ replace(temple_cli, '/', '\\') }} 2>nul & del /F /Q {{ legacy_temple_cli }} 2>nul & del /F /Q {{ legacy_dev_out }} 2>nul

[unix]
clean:
  @echo Cleaning up build artifacts...
  rm -rf {{ bin_root }}
  rm -f {{ out_css_file }} {{ temple_cli }} {{ legacy_temple_cli }} {{ legacy_dev_out }}

[unix]
dev: build-watcher
  ./{{ dev_watcher_out }}

[windows]
dev: build-watcher
  .\\{{ replace(dev_watcher_out, '/', '\\') }}

build-watcher: _ensure-bin-dirs
  @echo Building dev watcher...
  odin build tools/dev-watcher -out:{{ dev_watcher_out }}
