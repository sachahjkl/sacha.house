# Multi-stage build for lightweight release container
FROM archlinux:base-devel AS builder

ARG GIT_COMMIT_HASH=dev
ARG ODIN_RELEASE_VERSION=dev-2026-03
ARG ODIN_NIGHTLY_URL=
ARG BUN_VERSION=1.3.1

# Install dependencies
RUN pacman -Syu --noconfirm clang openssl just libbacktrace git odin unzip tar

# Download and install specific Odin release or nightly
RUN if [ -n "$ODIN_NIGHTLY_URL" ]; then \
    curl -L "$ODIN_NIGHTLY_URL" -o odin.tar.gz; \
    else \
    curl -L https://github.com/odin-lang/Odin/releases/download/${ODIN_RELEASE_VERSION}/odin-linux-amd64-${ODIN_RELEASE_VERSION}.tar.gz -o odin.tar.gz; \
    fi \
    && tar -C /opt -xzf odin.tar.gz \
    && ln -s $(find /opt -maxdepth 1 -type d -name "odin-linux-amd64*" | head -n 1)/odin /usr/local/bin/odin

# Install bun for CSS processing
RUN curl -fsSL https://bun.sh/install | bash -s "bun-v${BUN_VERSION}"
ENV PATH="/root/.bun/bin:$PATH"

# Set working directory
WORKDIR /app

# Copy source files and build configuration
COPY src/ ./src/
COPY styles/ ./styles/
COPY justfile ./
COPY tailwind.config.js ./
COPY package.json ./

# Install dependencies and build in release mode
RUN bun install --production
RUN GIT_COMMIT_HASH=$GIT_COMMIT_HASH just build release

# Final lightweight stage
FROM alpine:3.21

# Install only runtime dependencies and create user
RUN apk add --no-cache \
    ca-certificates \
    openssl \
    gcompat \
    tzdata \
    && adduser -D -s /bin/false appuser

# Copy only the binary
COPY --from=builder /app/sacha.house.exe /app/sacha.house

# Set ownership and permissions
RUN chown -R appuser:appuser /app && chmod +x /app/sacha.house

# Switch to non-root user
USER appuser
WORKDIR /app

# edit the hosts config

# Expose port
EXPOSE 6969

# Run the application
ENTRYPOINT ["./sacha.house"]
