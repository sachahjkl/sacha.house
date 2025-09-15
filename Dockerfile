# Multi-stage build for lightweight release container
FROM archlinux:base-devel AS builder

ARG GIT_COMMIT_HASH=dev

# Install dependencies
RUN pacman -Syu --noconfirm clang openssl make libbacktrace git odin unzip tar

# Download and install specific Odin release
RUN curl -L https://github.com/odin-lang/Odin/releases/download/dev-2025-09/odin-linux-amd64-dev-2025-09.zip -o odin.zip \
    && unzip odin.zip -d /tmp \
    && tar -C /opt -xzf /tmp/dist.tar.gz \
    && ln -s /opt/odin-linux-amd64-nightly+2025-09-08/odin /usr/local/bin/odin

# Install bun for CSS processing
RUN curl -fsSL https://bun.sh/install | bash -s "bun-v1.2.19"
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
