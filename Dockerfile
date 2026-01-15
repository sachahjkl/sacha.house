# Multi-stage build for lightweight release container
FROM archlinux:base-devel AS builder

ARG GIT_COMMIT_HASH=dev
ARG ODIN_VERSION=dev-2026-01
ARG BUN_VERSION=1.3.1

# Install dependencies
RUN pacman -Syu --noconfirm clang openssl make libbacktrace git odin unzip tar

# Download and install specific Odin release
RUN curl -L https://github.com/odin-lang/Odin/releases/download/${ODIN_VERSION}/odin-linux-amd64-${ODIN_VERSION}.tar.gz -o odin.tar.gz \
    && tar -C /opt -xzf odin.tar.gz \
    && ln -s /opt/odin-linux-amd64-${ODIN_VERSION}-04/odin /usr/local/bin/odin

# Install bun for CSS processing
RUN curl -fsSL https://bun.sh/install | bash -s "bun-v${BUN_VERSION}"
ENV PATH="/root/.bun/bin:$PATH"

# Set working directory
WORKDIR /app

# Copy source files and build configuration
COPY src/ ./src/
COPY styles/ ./styles/
COPY Makefile ./
COPY tailwind.config.js ./
COPY package.json ./

# Install dependencies and build in release mode
RUN bun install --production
RUN make build mode=release GIT_COMMIT_HASH=$GIT_COMMIT_HASH

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
