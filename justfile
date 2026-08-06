# sacha.house: run `just --list` for available recipes.

bin_root := 'bin'
version := env_var_or_default('VERSION', 'dev')
commit_hash := env_var_or_default('GIT_COMMIT_HASH', 'dev')
ldflags := '-X main.version=' + version + ' -X main.commitHash=' + commit_hash

default: build

templates:
  go tool templ generate

css:
  bun run build:css

build mode='debug': templates css
  mkdir -p {{ bin_root }}/{{ mode }}
  CGO_ENABLED=0 go build {{ if mode == 'release' { '-trimpath' } else { '' } }} -ldflags "{{ if mode == 'release' { '-s -w ' } else { '' } }}{{ ldflags }}" -o {{ bin_root }}/{{ mode }}/sacha.house ./cmd/sacha-house

test:
  go test ./...

run: build
  ./{{ bin_root }}/debug/sacha.house

_dev-run: build
  ./{{ bin_root }}/debug/sacha.house -dev

dev:
  watchexec --restart --exts go,templ,js,css --ignore 'internal/**/*_templ.go' --ignore 'internal/web/static/css/**' --watch cmd --watch internal --watch internal/web/static/js --watch styles -- just _dev-run

clean:
  rm -rf {{ bin_root }}
