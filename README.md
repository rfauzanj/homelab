# Homelab Infrastructure

A self-hosted homelab on Ubuntu Server, built around **Docker Compose**, an **Nginx reverse proxy**, and **Cloudflare Zero Trust Tunnel**. No ports are exposed to the internet and the router has no port forwarding.

## Highlights

- **Single entry point:** only the `reverse-proxy` container binds host ports 80/443. Every backend uses `expose`, never `ports`.
- **Host-based routing:** Nginx selects the backend from the `Host` header (`server_name`), so adding a service never requires a new public port.
- **Modular Compose projects:** each app lives in its own folder with its own `docker-compose.yml`, all sharing one external network.
- **Network segmentation:** databases and caches sit on an `internal: true` network with no route to the internet.
- **Secrets out of Git:** credentials live in `.env` files (git-ignored); the repo ships `.env.example` templates only.
- **Resilient Nginx:** variable-based `proxy_pass` plus Docker's embedded DNS, so one dead backend cannot crash the proxy.

## Architecture

```
Internet
   |
Cloudflare (DNS + Zero Trust)
   |
cloudflare_tunnel            (outbound-only connection, no inbound ports)
   |  HTTP reverse-proxy:80
reverse-proxy (Nginx)        host :80 / :443
   |-- budget.example.com      -> actual_budget:5006
   |-- vault.example.com       -> password_vault:80
   |-- cloud.example.com       -> owncloud_server:8080
   |-- devops-lab.example.com  -> devops-app:80
   |-- api.example.com         -> finance_api:5000
   `-- unknown host            -> 444 (connection closed)

All containers share the external bridge network: homelab-network
Databases/caches additionally sit on a per-app internal network (no internet route)
```

## Stack

| Layer | Technology |
|---|---|
| OS | Ubuntu Server |
| Containers | Docker Engine, Docker Compose v2 |
| Reverse proxy | Nginx (alpine) |
| Edge / access | Cloudflare Zero Trust Tunnel (cloudflared) |
| Services | Vaultwarden, Actual Budget, ownCloud, custom DevOps lab app, Finance API |
| Auto-update | Watchtower (scoped to selected containers) |

## Repository Structure

```
.
├── nginx/
│   ├── docker-compose.yml
│   └── conf.d/
│       ├── 00-global.conf      # resolver, real_ip, websocket map (loaded first)
│       ├── default.conf        # catch-all: return 444
│       ├── vault.conf
│       ├── actual.conf
│       ├── owncloud.conf
│       └── devops-lab.conf
├── cloudflared/
├── actual/
├── vaultwarden/
├── owncloud/
├── devops-lab/
├── finance-api/
├── docs/
└── README.md
```

Each project folder contains a `docker-compose.yml` and a `.env.example`.

## Quick Start

```bash
# 1. Create the shared network (once)
docker network create --driver bridge --subnet 172.20.0.0/16 homelab-network

# 2. Configure secrets for each project
cd <project>
cp .env.example .env
nano .env

# 3. Start in this order
cd nginx       && docker compose up -d
cd ../actual   && docker compose up -d
cd ../vaultwarden && docker compose up -d
cd ../cloudflared && docker compose up -d
```

In the Cloudflare dashboard, set every Public Hostname to type `HTTP` and URL `reverse-proxy:80`.

## Adding a New Service

1. Create `<service>/docker-compose.yml` with **no `ports:`**, `networks: [homelab-network]` and `external: true`.
2. Create `nginx/conf.d/<service>.conf` with a unique `server_name` and a variable-based `proxy_pass`.
3. Validate and reload Nginx:
   ```bash
   docker exec reverse-proxy nginx -t && docker exec reverse-proxy nginx -s reload
   ```
4. Add a Public Hostname in Cloudflare pointing to `reverse-proxy:80`.

## Design Decisions

| Decision | Reason |
|---|---|
| Tunnel target `reverse-proxy:80`, not `localhost` | `localhost` inside the cloudflared container is the container itself, not the host |
| `proxy_pass` via variable | Nginx resolves the name per request, so a stopped backend returns 502 instead of crashing Nginx at startup |
| `00-global.conf` prefix | Nginx loads `conf.d/*.conf` alphabetically; shared directives such as `map` must load before they are used |
| `default_server` returns 444 | Unknown or misspelled hostnames no longer fall through to a real application |
| `internal: true` backend network | A compromised database cannot reach other apps or exfiltrate data |
| `no-new-privileges`, log rotation | Reduces privilege escalation risk and prevents disks filling up with logs |
| TLS terminated at Cloudflare | Backends speak plain HTTP; upstream `https://` caused `wrong version number` errors |

## Troubleshooting Log

| Symptom | Cause | Fix |
|---|---|---|
| `container name "/reverse-proxy" is already in use` | A stale container with the same name existed | Stop and remove it, then `compose up -d` |
| Nginx restart loop: `unknown "connection_upgrade" variable` | `map` defined in a file loaded after its first use | Move shared directives to `00-global.conf` |
| `SSL_do_handshake() failed ... wrong version number` | `proxy_pass https://` to a plain HTTP backend | Use `http://` |
| cloudflared: `dial tcp ...:5006: connection refused` | Public Hostname still pointed at a closed raw port | Point it to `reverse-proxy:80` |
| Wrong site served for a hostname | Hostname missing from `server_name`, fell to `default_server` | Add the hostname and make the catch-all return 444 |

## Verification Checklist

```bash
# Only the proxy publishes host ports
docker ps --format '{{.Names}}\t{{.Ports}}' | grep -v '^reverse-proxy' | grep '0.0.0.0' || echo "OK"

# Host-based routing: same address and port, different Host header
docker run --rm --network homelab-network curlimages/curl \
  -sI -H "Host: vault.example.com" http://reverse-proxy:80

# Config syntax
docker exec reverse-proxy nginx -t
```

## Security Notes

- Real `.env` files, data volumes, database dumps and tunnel tokens are never committed (see `.gitignore`).
- Public signups are disabled on Vaultwarden.
- Container images should be pinned to explicit versions for production use.

## Roadmap

- [ ] Ansible playbooks to provision the host and deploy all stacks
- [ ] CI pipeline (GitHub Actions) to lint Compose files and validate Nginx config
- [ ] Monitoring with Prometheus and Grafana, logs with Loki
- [ ] Automated, encrypted backups
- [ ] Secret management with Vault or SOPS