# Docker Compose key reference (Compose Specification, June 2026)

Use this as the exhaustive key checklist when writing or reviewing `compose.yaml`.
The official JSON Schema top-level keys are `name`, `services`, `networks`, `volumes`, `configs`, `secrets`, `models`, `include`, and legacy `version`.
Implementation support can still be platform-dependent; validate with the target Compose implementation.

## Top-level keys

| Key | Value shape | Notes |
|---|---|---|
| `name` | string | Project name; exposed as `COMPOSE_PROJECT_NAME` for interpolation. |
| `services` | map of service name → service object | Main runnable containers/processes. |
| `networks` | map of network name → network object | Named networks. |
| `volumes` | map of volume name → volume object | Named persistent volumes. |
| `configs` | map of config name → config object | Non-secret file/config data. |
| `secrets` | map of secret name → secret object | Sensitive data mounted into services. |
| `models` | map of model name → model object | Docker Model Runner model declarations. |
| `include` | string/list/object | Include other Compose files/projects. |
| `version` | string | Legacy only; do not use in new files. |

## Service keys

Official service keys:

`annotations`, `attach`, `blkio_config`, `build`, `cap_add`, `cap_drop`, `cgroup`, `cgroup_parent`, `command`, `configs`, `container_name`, `cpu_count`, `cpu_percent`, `cpu_period`, `cpu_quota`, `cpu_rt_period`, `cpu_rt_runtime`, `cpu_shares`, `cpus`, `cpuset`, `credential_spec`, `depends_on`, `deploy`, `develop`, `device_cgroup_rules`, `devices`, `dns`, `dns_opt`, `dns_search`, `domainname`, `entrypoint`, `env_file`, `environment`, `expose`, `extends`, `external_links`, `extra_hosts`, `gpus`, `group_add`, `healthcheck`, `hostname`, `image`, `init`, `ipc`, `isolation`, `label_file`, `labels`, `links`, `logging`, `mac_address`, `mem_limit`, `mem_reservation`, `mem_swappiness`, `memswap_limit`, `models`, `network_mode`, `networks`, `oom_kill_disable`, `oom_score_adj`, `pid`, `pids_limit`, `platform`, `ports`, `post_start`, `pre_stop`, `privileged`, `profiles`, `provider`, `pull_policy`, `pull_refresh_after`, `read_only`, `restart`, `runtime`, `scale`, `secrets`, `security_opt`, `shm_size`, `stdin_open`, `stop_grace_period`, `stop_signal`, `storage_opt`, `sysctls`, `tmpfs`, `tty`, `ulimits`, `use_api_socket`, `user`, `userns_mode`, `uts`, `volumes`, `volumes_from`, `working_dir`.

### Common service value sets

| Key | Known values / shape | Notes |
|---|---|---|
| `image` | OCI image reference | Prefer pinned tag/digest. |
| `build` | string path or object | See Build keys below. |
| `pull_policy` | `always`, `never`, `missing`/`if_not_present`, `build`, `daily`, `weekly`, `every_<duration>` | Controls pull/build precedence and refresh. |
| `pull_refresh_after` | duration | Separate schema key for explicit refresh timing where supported. |
| `restart` | `no`, `always`, `on-failure[:max-retries]`, `unless-stopped` | Container-runtime restart policy, not deploy policy. |
| `cgroup` | `host`, `private` | Platform dependent. |
| `command`, `entrypoint`, `healthcheck.test` | string or list | Prefer exec-list form for deterministic signal handling. |
| `depends_on` | list or map | Long syntax keys: `condition`, `restart`, `required`. |
| `depends_on.<svc>.condition` | `service_started`, `service_healthy`, `service_completed_successfully` | Use `service_healthy` only with a healthcheck. |
| `depends_on.<svc>.restart` | boolean | Restart dependent service after an explicit Compose update of dependency. |
| `depends_on.<svc>.required` | boolean | `false` downgrades missing dependency to warning. |
| `env_file` | string/list or object list | Object keys: `path`, `required`, `format`; `format: raw` avoids interpolation. |
| `environment` | map or list | Map syntax is clearer; never store secrets here. |
| `profiles` | list of strings | Optional services enabled with `--profile`. |
| `ports` | string or object list | Object keys below. |
| `volumes` | string or object list | Object keys below. |
| `networks` | list or map | Per-network object keys below. |
| `configs`, `secrets` | list of names or objects | Object keys: `source`, `target`, `uid`, `gid`, `mode`. |
| `models` | list of names or map | Per-model keys: `endpoint_var`, `model_var`. |
| `post_start`, `pre_stop` | list of hook objects | Hook keys: `command`, `environment`, `privileged`, `user`, `working_dir`. |
| `provider` | object | Keys: `type`, `options`; for provider services. |
| `gpus` | `all` or device request list | Object keys: `capabilities`, `count`, `device_ids`, `driver`, `options`. |
| `devices` | strings or objects | Object keys: `source`, `target`, `permissions`; CDI syntax is allowed. |
| `ulimits` | map | Value is number or `{soft, hard}`. |

### Build keys (`services.<name>.build`)

`build` can be a string context path or an object with:

`context`, `dockerfile`, `dockerfile_inline`, `target`, `args`, `additional_contexts`, `cache_from`, `cache_to`, `extra_hosts`, `isolation`, `labels`, `network`, `no_cache`, `platforms`, `privileged`, `pull`, `secrets`, `ssh`, `shm_size`, `tags`, `ulimits`, `entitlements`, `provenance`, `sbom`.

Best defaults: set `context`, `dockerfile`, `target`, `args`, `cache_from/cache_to` for CI, and `provenance: true` / `sbom: true` when publishing images. Keep `context` aligned with Dockerfile `COPY` paths.

### Healthcheck keys

`test`, `interval`, `timeout`, `retries`, `start_period`, `start_interval`, `disable`.

Use `$$VAR` in `CMD-SHELL` probes when the container shell, not Compose, should expand the variable.

### Port object keys

`target`, `published`, `host_ip`, `protocol`, `app_protocol`, `mode`, `name`.

- `target`: container port.
- `published`: host port/range.
- `host_ip`: bind address; prefer `127.0.0.1` for local-only services.
- `protocol`: usually `tcp` or `udp`.
- `mode`: commonly `host` or `ingress` depending on platform.

### Volume mount object keys

Top-level mount object: `type`, `source`, `target`, `read_only`, `consistency`, `bind`, `volume`, `tmpfs`, `image`.

- `type`: `bind`, `volume`, `tmpfs`, `cluster`, `npipe`, `image`.
- `bind`: `propagation`, `create_host_path`, `recursive`, `selinux`.
  - `recursive`: `enabled`, `disabled`, `writable`, `readonly`.
  - `selinux`: `z`, `Z`.
- `volume`: `nocopy`, `subpath`, `labels`.
- `tmpfs`: `size`, `mode`.
- `image`: `subpath`.

### Per-service network object keys

`aliases`, `driver_opts`, `gw_priority`, `interface_name`, `ipv4_address`, `ipv6_address`, `link_local_ips`, `mac_address`, `priority`.

## Top-level `networks`

Network object keys: `driver`, `driver_opts`, `attachable`, `enable_ipv4`, `enable_ipv6`, `external`, `internal`, `ipam`, `labels`, `name`.

- `external`: boolean or `{name}` depending on syntax; external networks must already exist.
- `ipam`: `driver`, `options`, `config`; each config may include subnet/gateway and IP range fields supported by the driver.
- `internal: true`: isolates the network from external connectivity; use for DB tiers when possible.

## Top-level `volumes`

Volume object keys: `driver`, `driver_opts`, `external`, `labels`, `name`.

Use named volumes for persistent DB/cache state. `external` means Compose does not create/delete it.

## Top-level `configs`

Config object keys: `file`, `content`, `environment`, `external`, `name`, `labels`, `template_driver`.

Use `configs` for non-secret files such as nginx snippets, app config templates, or registry values. Do not put credentials here.

## Top-level `secrets`

Secret object keys: `file`, `environment`, `external`, `name`, `labels`, `driver`, `driver_opts`, `template_driver`.

Mount into services with service-level `secrets`. If the image supports it, set an env var like `POSTGRES_PASSWORD_FILE=/run/secrets/db_password` rather than passing the password value directly.

## Top-level `models`

Model object keys: `model`, `name`, `context_size`, `runtime_flags`.

Service `models` can be a list of model names or a map:

```yaml
models:
  llama:
    model: ai/llama3.2
    context_size: 4096

services:
  app:
    image: myapp
    models:
      llama:
        endpoint_var: LLM_URL
        model_var: LLM_MODEL
```

## `include`

`include` accepts a path/string, list, or object with `path`, `env_file`, and `project_directory`. Use it to assemble independent Compose subprojects without copying everything into one file. Prefer explicit paths; keep each included file valid on its own.

## Deploy keys (`services.<name>.deploy`)

Deploy object keys: `mode`, `replicas`, `endpoint_mode`, `labels`, `placement`, `resources`, `restart_policy`, `update_config`, `rollback_config`.

- `mode`: usually `replicated` or `global`.
- `endpoint_mode`: usually `vip` or `dnsrr`.
- `placement`: `constraints`, `preferences`, `max_replicas_per_node`.
- `resources.limits`: `cpus`, `memory`, `pids`.
- `resources.reservations`: `cpus`, `memory`, `devices`, `generic_resources`.
- `restart_policy`: `condition`, `delay`, `max_attempts`, `window`; conditions are commonly `none`, `on-failure`, `any`.
- `update_config` / `rollback_config`: `parallelism`, `delay`, `failure_action`, `monitor`, `max_failure_ratio`, `order`.
  - `order`: `start-first`, `stop-first`.
  - `failure_action`: commonly `pause`, `continue`, `rollback` for updates; rollback config normally uses `pause` or `continue`.

Remember: several `deploy` keys are Swarm/cloud-platform concepts and may be ignored or only partially supported by local Compose.

## Develop keys (`services.<name>.develop`)

`develop` keys: `watch`.

Each `watch` rule keys: `action`, `path`, `target`, `ignore`, `include`, `initial_sync`, `exec`.

`action` values: `rebuild`, `sync`, `restart`, `sync+restart`, `sync+exec`. `exec` uses service hook keys: `command`, `environment`, `privileged`, `user`, `working_dir`.

## Merge/interpolation/extensions checklist

- Variable interpolation uses shell-like `${VAR}`, `${VAR:-default}`, `${VAR?err}` forms. Escape as `$$` for runtime shell expansion.
- `.env` values feed interpolation; `env_file` values feed container runtime environment. They are not interchangeable.
- Merging multiple files: later files override mappings/scalars and append many sequences. Use `docker compose config` to inspect the resolved result.
- Use `x-*` extension fields and YAML anchors for DRY fragments; extension fields are ignored by Compose but can be merged into services.
- Profiles control optional services, not top-level section parsing.

## Legacy / deprecated compatibility

- `version:` is obsolete. Do not use it in new `compose.yaml` files.
- `links` and `external_links` are legacy; prefer user-defined networks and DNS service names.
- `container_name` prevents scaling and causes name collisions; only use for rare integration points that require a fixed container name.
- The v1 `docker-compose` binary is legacy; prefer `docker compose`.
