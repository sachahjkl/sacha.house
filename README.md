# sacha.house

The personal website of Sacha Froment, built with **Odin**.

## Overview

This project is a custom web server written in the [Odin programming language](https://odin-lang.org/), featuring a handmade templating engine, GraphQL integrations, and modern web technologies.

### Key Features

*   **Odin Backend**: Built on top of `odin-http`, utilizing a custom router and middleware.
*   **Temple**: A custom templating engine (`lib/temple`) that transpiles Twig-like syntax into native Odin code for type-safe, high-performance rendering.
*   **Hot Reloading**: A custom-built development watcher (`tools/dev-watcher`) that monitors source files, recompiles the server, and hot-reloads the browser automatically. Supports both Windows and Linux.
*   **GraphQL Integration**: Fetches blog content from [Hygraph](https://hygraph.com/).
*   **External APIs**:
    *   Fetches pinned repositories from **GitHub** and **GitLab**.
    *   Loads user profile data from a **GitHub Gist**.
*   **WebAuthn**: Implements Passkey authentication for the admin panel (`/admin`).
*   **Tailwind CSS**: Styled with Tailwind, processed via Bun.

## Prerequisites

*   [Odin](https://odin-lang.org/) (latest version recommended)
*   [Bun](https://bun.sh/) (for Tailwind CSS and JS dependencies)
*   `make` (or `gmake` on Linux)
*   `cl` (MSVC) on Windows or `gcc`/`clang` on Linux

## Development

To start the development server with **hot reloading**:

```bash
make dev
```

This command:
1.  Builds and runs the `tools/dev-watcher` utility.
2.  Watches `src/` and `lib/` for changes.
3.  Recompiles the project and restarts the server automatically.
4.  Injects a hot-reload script into the browser to refresh the page on server restart.

## Build

To build for production:

```bash
make build mode=release
```

This generates the `sacha.house.exe` binary.

## Configuration

Configuration is loaded from `config.json` (looked for in `CONFIG_PATH` env var or default location) and environment variables.

See `config.example.json` for required fields:

*   `HYGRAPH_API_ENDPOINT`: URL for the blog CMS.
*   `GITHUB_TOKEN`: For fetching repositories.
*   `GITLAB_TOKEN`: For fetching repositories.
*   `ADMIN_USERNAME`/`PASSWORD`: Fallback credentials.

## Project Structure

*   `src/`: Main application source code.
    *   `src/templates/`: `.temple.twig` templates.
    *   `src/static/`: Static assets (images, css, js).
*   `lib/`:
    *   `odin-http/`: HTTP server library.
    *   `temple/`: Templating engine compiler and runtime.
*   `tools/`:
    *   `dev-watcher/`: Development tool for hot reloading.
*   `deploy/`: Deployment scripts (systemd, fail2ban).
*   `styles/`: Tailwind CSS input files.

## License

MIT
