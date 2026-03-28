# Bifrost AI Gateway — Docker Compose Setup

Self-hosted [Bifrost](https://docs.getbifrost.ai) AI gateway running on Docker with PostgreSQL persistence. Exposes a unified OpenAI-compatible API across 24+ AI providers (OpenAI, Anthropic, Bedrock, Gemini, etc.) with a built-in Web UI for configuration, monitoring, and governance.

---

## Repository Structure

```
bifrost/
├── docker-compose.yml        # Full stack definition (Bifrost + PostgreSQL)
├── config.json.template      # Bifrost bootstrap config — copy to data dir before first start
├── postgres/
│   └── init-db.sql           # Creates bifrost_logs DB with required UTF8 encoding
├── .env.example              # All configurable variables with descriptions
├── .gitignore                # Prevents secrets and runtime data from being committed
└── README.md                 # This file
```

---

## Prerequisites

- Docker Engine and Docker Compose v2
- Portainer (optional, recommended for management)
- A directory on your host defined by `DOCKER_DATA_PATH` for persistent storage

---

## First-Time Setup

### 1. Create your environment file

```bash
cp .env.example .env
```

Edit `.env` and fill in all values — especially `POSTGRES_PASSWORD`. See [Generating Secure Passwords](#generating-secure-passwords) below.

### 2. Create the data directory and place the Bifrost config

Bifrost requires a `config.json` in its data directory to use PostgreSQL instead of SQLite. This file bootstraps the database on first start and is then ignored — Bifrost uses the database exclusively after that.

```bash
# Create the data directory (adjust path to match your DOCKER_DATA_PATH)
mkdir -p /your/DOCKER_DATA_PATH/bifrost/data

# Copy the template into place
cp config.json.template /your/DOCKER_DATA_PATH/bifrost/data/config.json
```

> **Note:** Do not put API keys or secrets directly in `config.json`. Provider keys are added via the Web UI after the stack is running. The `env.VARNAME` references in `config.json` are resolved from the container's environment variables at startup.

### 3. Start the stack

```bash
docker compose up -d
```

Or deploy via Portainer using this repository as a Git-backed stack.

### 4. Open the Web UI

Navigate to `http://<your-host>:8080` (or whatever `BIFROST_PORT` is set to).

Use the Web UI to add your AI provider API keys. No restart required — changes apply immediately.

---

## Generating Secure Passwords

Never use simple or guessable passwords for `POSTGRES_PASSWORD`. Use one of the following methods to generate a strong random password:

**Option A — openssl (recommended, available on most systems):**
```bash
openssl rand -base64 32
```

**Option B — /dev/urandom:**
```bash
cat /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 32; echo
```

**Option C — Python:**
```bash
python3 -c "import secrets; print(secrets.token_urlsafe(32))"
```

Paste the output directly as the value of `POSTGRES_PASSWORD` in your `.env` file. Do not wrap it in quotes unless the password itself contains spaces.

---

## PostgreSQL Configuration

### Why PostgreSQL?

By default, Bifrost uses SQLite stored in the data directory. PostgreSQL is preferred for production use because:

- **Config store** (`bifrost_config`) — holds provider keys, virtual keys, governance policies, MCP configs, and all UI settings
- **Logs store** (`bifrost_logs`) — holds request/response logs, metrics, and analytics data. Logs can grow significantly over time; keeping them in a separate database makes independent backup and retention management straightforward

### How it works

The `config.json.template` file configures both stores to use PostgreSQL. All connection credentials are passed as `env.VARNAME` references — Bifrost resolves these from the container's environment at startup, so no credentials are hardcoded in the file.

```
config.json  →  "host": "env.POSTGRES_HOST"
                        ↓
docker-compose.yml  →  POSTGRES_HOST: "bifrost-postgres"
```

### Database initialization

On first start, PostgreSQL:
1. Creates the `bifrost_config` database (via `POSTGRES_DB` env var) with UTF8 encoding
2. Runs `postgres/init-db.sql` which creates the `bifrost_logs` database with UTF8 encoding via `template0`

Both databases must use UTF8 encoding — this is a hard requirement from Bifrost. The `POSTGRES_INITDB_ARGS: "--encoding=UTF8 --locale=C.UTF-8"` and `template0` in the init script ensure this.

### PostgreSQL version requirement

Bifrost's logs store requires **PostgreSQL 16 or higher**. This is enforced at startup — the container will fail to start if the version is lower. The compose file uses `postgres:16`.

### Connecting to PostgreSQL directly

If you need to connect to the database (e.g. for inspection or manual backup):

```bash
docker exec -it bifrost-postgres psql -U bifrost -d bifrost_config
```

Verify both databases exist and use UTF8:
```sql
SELECT datname, pg_encoding_to_char(encoding) AS encoding
FROM pg_database
WHERE datname IN ('bifrost_config', 'bifrost_logs');
```

Expected output:
```
    datname     | encoding
----------------+----------
 bifrost_config | UTF8
 bifrost_logs   | UTF8
```

### Log retention

The logs store is configured with `retention_days: 30` in `config.json.template`. Bifrost automatically deletes logs older than 30 days. Set to `0` to disable automatic deletion.

### Resetting the database

If you need to start fresh (e.g. after a misconfiguration on first boot):

```bash
# Stop the stack
docker compose down

# Remove the PostgreSQL data volume
rm -rf /your/DOCKER_DATA_PATH/bifrost/postgres

# Start again — databases will be re-created from scratch
docker compose up -d
```

> **Warning:** This permanently deletes all stored configuration, API keys, and logs. Re-add your provider keys via the Web UI after restart.

---

## Environment Variables Reference

All variables are defined in `.env` (copied from `.env.example`).

| Variable | Default | Description |
|---|---|---|
| `DOCKER_DATA_PATH` | *(required)* | Host path for all persistent data |
| `BIFROST_PORT` | `8080` | Host port for the Bifrost Web UI and API |
| `LOG_LEVEL` | `info` | Log verbosity: `debug`, `info`, `warn`, `error` |
| `LOG_STYLE` | `json` | Log format: `json`, `pretty` |
| `POSTGRES_USER` | `bifrost` | PostgreSQL username |
| `POSTGRES_PASSWORD` | *(required)* | PostgreSQL password — generate securely, see above |
| `POSTGRES_CONFIG_DB` | `bifrost_config` | Database name for Bifrost configuration |
| `POSTGRES_LOGS_DB` | `bifrost_logs` | Database name for request logs |

---

## API Usage

Bifrost exposes an OpenAI-compatible API. The model format is `<provider>/<model>`.

```bash
curl -X POST http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "openai/gpt-4o-mini",
    "messages": [{"role": "user", "content": "Hello, Bifrost!"}]
  }'
```

Point any OpenAI-compatible SDK at `http://<host>:8080` as the base URL. Provider API keys are managed by Bifrost — pass any dummy value for `api_key` in your SDK config.

---

## Reverse Proxy (NGINX Proxy Manager)

This stack exposes Bifrost directly on `BIFROST_PORT`. To front it with NGINX Proxy Manager:

1. Add a new **Proxy Host** in NPM pointing to `http://<docker-host-ip>:<BIFROST_PORT>`
2. Enable **Websocket Support** if you plan to use the Bifrost WebSocket features
3. Apply an SSL certificate via Let's Encrypt as normal

The Bifrost container is on an internal `bifrost-internal` bridge network and does not need to be on the same Docker network as NPM when using host-IP routing.

---

## Useful Commands

```bash
# View logs
docker compose logs -f bifrost
docker compose logs -f bifrost-postgres

# Stop the stack
docker compose down

# Pull latest Bifrost image and restart
docker compose pull bifrost && docker compose up -d bifrost

# Check PostgreSQL health
docker exec bifrost-postgres pg_isready -U bifrost
```
