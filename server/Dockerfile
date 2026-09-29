# The co-op server: the game itself, exported for Linux as a dedicated
# (headless) server. Build it first: ./tools/build_server.sh
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates libfontconfig1 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY deeptime.x86_64 /app/deeptime
RUN chmod +x /app/deeptime && useradd -m game
USER game
EXPOSE 8910
CMD ["/app/deeptime", "--headless", "--", "server", "port=8910"]
