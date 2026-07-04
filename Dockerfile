# Toolchain image: everything build.sh + serve.py need (cosmo, duckdb,
# curl, python3) so a host never installs deps. The repo is bind-mounted
# at /app (see compose.yaml) — data/, baked/, party/ persist in the
# working tree exactly as they do running natively.

FROM rust:1-slim AS cosmo
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/*
RUN cargo install --git https://codeberg.org/mvexel/cosmo --locked

FROM python:3.13-slim
ARG DUCKDB_VERSION=v1.5.4
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl unzip ca-certificates \
    && rm -rf /var/lib/apt/lists/*
RUN curl -L --fail -o /tmp/duckdb.zip \
      "https://github.com/duckdb/duckdb/releases/download/${DUCKDB_VERSION}/duckdb_cli-linux-$(dpkg --print-architecture).zip" \
    && unzip /tmp/duckdb.zip -d /usr/local/bin && rm /tmp/duckdb.zip
COPY --from=cosmo /usr/local/cargo/bin/cosmo /usr/local/bin/

WORKDIR /app
EXPOSE 8765
# Bake once if there are no baked assets yet, then serve.
# Rebake: delete baked/ (or run ./build.sh) and restart.
CMD ["sh", "-c", "ls baked/*.parquet >/dev/null 2>&1 || ./build.sh; exec python3 serve.py 8765"]
