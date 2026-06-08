---
name: docker-compose
description: Docker Compose v2 / Compose Specification — compose.yaml, services, build/deploy/develop, networks, volumes, configs, secrets, models, include, profiles, templates, best practices, and antipatterns. Use when writing or reviewing Docker Compose files.
---

# Docker Compose v2 / Compose Specification

Use this skill when creating or reviewing a Docker Compose project: local dev stacks, service dependencies, databases, queues, reverse proxies, GPUs, Docker Model Runner, `develop.watch`, or multi-file overrides.

This skill tracks the Compose Specification and Docker Docs as of **June 2026**.

## Defaults for new projects

- **File name:** create `compose.yaml`, not `docker-compose.yml`. Docker Compose discovers `compose.yaml` / `compose.yml` before legacy `docker-compose.yaml` / `docker-compose.yml`, and current Docker docs use `compose.yaml`.
- **Command:** use `docker compose` (space) for Compose v2. The old `docker-compose` binary is legacy.
- **Top-level `version`:** omit it. `version:` is obsolete in the Compose Specification and does not select supported features.
- **Validation:** run `docker compose config` before saying the file is ready.
- **Secrets:** never hardcode secret values in YAML. Use Docker secrets, mounted files, or gitignored env files; prefer `_FILE` env vars when images support them.
- **Images:** pin tags or digests. Avoid `latest` except disposable demos.
- **Ports:** bind local-only services as `127.0.0.1:HOST:CONTAINER`; do not publish databases publicly unless explicitly requested.

## Authoring workflow

1. Detect project needs: runtime, DB/cache/broker, reverse proxy, test runner, host services, profiles, GPU/model needs, and persistence.
2. Start from a template:
   - [`templates/compose.yaml`](templates/compose.yaml) — dev stack baseline.
   - [`templates/compose.dev.yaml`](templates/compose.dev.yaml) — bind mounts and `develop.watch` overrides.
   - [`templates/compose.prod.yaml`](templates/compose.prod.yaml) — hardened runtime, resources, logging, secrets.
   - [`templates/compose.test.yaml`](templates/compose.test.yaml) — test runner with ephemeral DB.
3. Replace example image names, build targets, env vars, secrets, and healthchecks with project-specific values. The templates assume a multi-stage Dockerfile with `development`, `runtime`, and/or `test` targets; adjust `build.target` if the project does not use those stages.
4. Validate the resolved model:
   ```bash
   docker compose -f compose.yaml config
   docker compose -f compose.yaml config --profiles
   ```
5. If the file references external images, verify pullability before relying on them: `docker pull postgres:17-alpine`.

## Complete Compose file sections

Top-level keys in the current Compose schema:

| Section | Use | Notes |
|---|---|---|
| `name` | Project name | Stable alternative to `-p`; lowercase/digits/dash/underscore. |
| `services` | Containers/processes | Required for runnable apps. |
| `networks` | Named networks | Use custom backend/frontend networks; `internal: true` for private tiers. |
| `volumes` | Named volumes | Use for durable DB/cache data; avoid anonymous volumes for persistence. |
| `configs` | Non-secret files/config blobs | `file`, `content`, or `environment`; mounted read-only. |
| `secrets` | Sensitive files | `file`, `environment`, external, or driver-backed. |
| `models` | Docker Model Runner models | Top-level model declarations consumed by service `models`. |
| `include` | Include Compose projects/files | Better than huge monolith files for subprojects. |
| `version` | Legacy compatibility only | **Do not add** to new files; Compose v2 warns/ignores it. |

Additional Compose file features are not top-level app sections but still matter: `fragments`/YAML anchors, `x-*` extensions, variable interpolation, merge rules, profiles, multi-file overrides (`-f`), `build`, `deploy`, and `develop`.

For all known keys and values, read [`references/compose-key-reference.md`](references/compose-key-reference.md).

## Healthy dependencies

Use `depends_on` long syntax only when the dependent service truly needs a startup gate. Gate on healthchecks, not just container start.

```yaml
services:
  api:
    build: .
    depends_on:
      db: { condition: service_healthy, restart: true }
      redis: { condition: service_started }

  db:
    image: postgres:17-alpine
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $${POSTGRES_USER} -d $${POSTGRES_DB}"]
      interval: 5s
      timeout: 5s
      retries: 20
      start_period: 10s
```

Use `service_completed_successfully` for one-shot jobs such as migrations.

## Networks by trust boundary

```yaml
services:
  web:
    networks: [frontend, backend]
    ports: ["127.0.0.1:${WEB_PORT:-8080}:8080"]
  db:
    networks: [backend]

networks:
  frontend: {}
  backend:
    internal: true
```

## Host access from Linux containers

Inside a container, `localhost` is the container. For host services, use `host.docker.internal` instead of hardcoded bridge IPs:

```yaml
services:
  app:
    extra_hosts:
      - "host.docker.internal:host-gateway"
    environment:
      API_URL: http://host.docker.internal:3001
```

## Profiles for optional services

```yaml
services:
  api: { build: . }
  adminer:
    image: adminer:5
    profiles: [debug]
    ports: ["127.0.0.1:8081:8080"]
```

Run with `docker compose --profile debug up -d`.

## Multi-file overrides

Keep `compose.yaml` safe defaults. Put dev bind mounts and local-only helpers in `compose.dev.yaml`; production hardening in `compose.prod.yaml`.

```bash
docker compose -f compose.yaml -f compose.dev.yaml up --watch
docker compose -f compose.yaml -f compose.prod.yaml config
```

## Compose Watch / `develop`

Use `develop.watch` for source sync/rebuild instead of giant bind mounts when file sync semantics matter:

```yaml
services:
  api:
    build: .
    develop:
      watch:
        - action: sync
          path: ./src
          target: /app/src
          ignore: [node_modules/, dist/]
        - action: rebuild
          path: package.json
```

## Reproducible builds

```yaml
services:
  api:
    image: ghcr.io/example/api:${APP_VERSION:-dev}
    build:
      context: .
      dockerfile: Dockerfile
      target: runtime
      args:
        NODE_ENV: production
      cache_from:
        - type=registry,ref=ghcr.io/example/api:buildcache
      cache_to:
        - type=registry,ref=ghcr.io/example/api:buildcache,mode=max
      provenance: true
      sbom: true
```

## Antipatterns

| Antipattern | Why it fails | Prefer |
|---|---|---|
| Creating `docker-compose.yml` in new projects | Legacy name encourages v1-era habits | `compose.yaml` |
| Adding `version: "3.9"` | Obsolete; no longer gates features | Omit `version` |
| `image: postgres:latest` | Non-reproducible upgrades | Pin `postgres:17-alpine` or digest |
| Publishing DB ports as `5432:5432` | Exposes local DB on every interface | `127.0.0.1:5432:5432` or no port |
| `depends_on` without healthchecks | Start order is not readiness | `healthcheck` + `condition: service_healthy` |
| Passwords in `environment:` | Secrets leak via config/process inspection | `secrets:` + `_FILE` env vars |
| Anonymous volumes for databases | Data is hard to find/backup; easy to delete | Named top-level `volumes:` |
| One giant default network | No isolation | Custom networks, `internal: true` |
| `container_name:` everywhere | Breaks scaling and project isolation | Let Compose name containers |
| `network_mode: host` as shortcut | Loses isolation/portability | Precise ports and networks |
| Bind-mounting whole repos over built artifacts | Hides build-time files; slow on Desktop | Narrow mounts or `develop.watch` |
| `privileged: true` by default | Broad host attack surface | Specific `cap_add`, `devices`, `security_opt` |
| Assuming `deploy.resources` always works locally | Some `deploy` keys are platform-dependent | Validate on target; use service limits where needed |
| Running `docker compose restart` after YAML/env edits | Restart does not recreate containers or reload config | `docker compose up -d --force-recreate <svc>` |
| Hardcoding `172.17.0.1` for host access | Bridge IP changes | `host.docker.internal:host-gateway` |
| Copy-pasting private registry images unchecked | Pull fails later | `docker pull <image>` before finalizing |

## Troubleshooting

| Symptom | Check | Fix |
|---|---|---|
| YAML parses but Compose rejects it | `docker compose config` | Fix schema/merge/interpolation errors first. |
| App cannot reach DB | Is host `db`, not `localhost`? Is DB healthy? | Use service DNS name and healthcheck. |
| Env var is empty | `.env` interpolation vs `env_file` runtime env | Use `${VAR:-default}` for interpolation; inspect `docker compose config`. |
| Edited `.env` but container still has old value | Existing container was only restarted | Recreate: `docker compose up -d --force-recreate <svc>`. |
| Port already allocated | `docker compose ps`, `ss -ltnp` | Change host port or stop conflicting service. |
| Volume data vanished | Anonymous volume or `down -v` | Use named volume; avoid `down -v` unless wiping data. |
| Bind mount hides dependencies | Host path overlays image path | Add anonymous/named dependency volume or use `develop.watch`. |
| `service_healthy` never arrives | Healthcheck command wrong or too strict | Check logs and run the probe inside the container. |
| Interpolation mangles `$` in commands | Compose expands `$VAR` | Escape as `$$VAR` when the container shell should expand it. |

## Source map

Primary sources used (Docker Docs / Compose Spec, June 2026):

- Docker Compose docs: `https://docs.docker.com/compose/`
- Compose file reference: `https://docs.docker.com/reference/compose-file/`
- Compose Specification: `https://compose-spec.github.io/compose-spec/spec.html`
- Compose JSON Schema: `https://raw.githubusercontent.com/compose-spec/compose-spec/master/schema/compose-spec.json`
- Docker docs pages for build, deploy, develop, interpolation, merge, include, models, secrets, networking, production, Compose Watch, and trust model.

## Installation

```bash
# Claude Code
cp -r skills/docker-compose ~/.claude/skills/
```

For claude.ai, upload `SKILL.md` plus the `references/` and `templates/` files, or paste the relevant sections into project knowledge.
