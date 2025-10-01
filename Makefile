# Makefile for the Odin rewrite of sacha.house

.PHONY: all build css run clean templates run-ssl

# Variables
ODIN_SRC = src
ODIN_OUT = sacha.house.exe
BUN = bun
TEMPLE_CLI = temple_cli.exe
TEMPLE_PATH = $(ODIN_SRC)/temple
OUT_TEMPLATE_FILE = $(ODIN_SRC)/temple/templates.odin
TEMPLATE_FILES = $(wildcard $(ODIN_SRC)/templates/*.temple.twig)
GIT_COMMIT_HASH ?= dev # git rev-parse --short HEAD
VERSION_TAG ?= dev
ODIN_SOURCE_FILES = $(wildcard $(ODIN_SRC)/*.odin)
CSS_SOURCE_FILES = styles/app.css
OUT_CSS_FILE = $(ODIN_SRC)/static/css/style.css
STATIC_EMBEDDED_FILES = $(ODIN_SRC)/static/**/*
TAILWIND_CONFIG_FILE = tailwind.config.js
PORT = 6969
SSL_PORT = 3000


# Build mode configuration
# Usage: make [target] mode=[debug|release]
# Defaults to debug mode.
mode ?= debug

ifeq ($(mode),release)
	ODIN_FLAGS = -o:speed -define:TRACK_LEAKS=false -build-mode:exe
else
	ODIN_FLAGS = -debug -define:TRACK_LEAKS=true -build-mode:exe
endif


all: build

$(ODIN_OUT): $(OUT_TEMPLATE_FILE) $(ODIN_SOURCE_FILES) $(STATIC_EMBEDDED_FILES) $(OUT_CSS_FILE)
	@echo "Building Odin application in $(mode) mode..."
	@odin build $(ODIN_SRC) -out:$(ODIN_OUT) -define:GIT_COMMIT_HASH="$(GIT_COMMIT_HASH)" -define:VERSION_TAG="$(VERSION_TAG)" $(ODIN_FLAGS)

$(TEMPLE_CLI): $(TEMPLE_PATH)/cli/*.odin
	@echo "Building temple CLI..."
	@odin build $(TEMPLE_PATH)/cli -o:speed -out:$(TEMPLE_CLI)

$(OUT_TEMPLATE_FILE): $(TEMPLE_CLI) $(TEMPLATE_FILES)
	@echo "Transpiling templates..." $(TEMPLATE_FILES)
	@./$(TEMPLE_CLI) $(ODIN_SRC) $(TEMPLE_PATH)

templates: $(OUT_TEMPLATE_FILE)
css: $(OUT_CSS_FILE)

$(OUT_CSS_FILE): $(CSS_SOURCE_FILES) $(TEMPLATE_FILES) $(TAILWIND_CONFIG_FILE)
	@echo "Building Tailwind CSS..."
	@$(BUN) run build:css

build: $(ODIN_OUT)

run: $(ODIN_OUT)
	@echo "Running 'sacha.house' web server..."
	@./$(ODIN_OUT)

run-ssl:
	@echo "Running 'sacha.house' web server with SSL..."
	@$(BUN) x local-ssl-proxy --source $(SSL_PORT) --target $(PORT) --cert localhost.pem --key localhost-key.pem

clean:
	@echo "Cleaning up build artifacts..."
	@rm -f $(ODIN_OUT)
	@rm -f $(OUT_CSS_FILE)
	@rm -f $(TEMPLE_CLI)
	@rm -rf temple
