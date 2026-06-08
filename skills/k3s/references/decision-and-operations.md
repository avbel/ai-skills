# K3s decision and operations reference

Use this reference when a request needs more detail than the main `SKILL.md`: choosing Docker vs Compose vs K3s, sizing K3s, choosing storage, exposing apps, autoscaling, and secret-manager integration.

## Docker vs Compose vs K3s vs larger platforms

| Question | Plain Docker | Docker Compose | K3s | Managed/full Kubernetes platform |
|---|---|---|---|---|
| Host count | 1 | 1 | 1-N | N, multi-AZ/region |
| Services | 1-few | few-many on one host | many across nodes | many teams/platform workloads |
| Restart | container policy/systemd | Compose restart policies | controller reconciliation | controller reconciliation + platform SLOs |
| Service discovery | manual ports | Compose DNS | Kubernetes Services/DNS | Services, service mesh/Gateway/API management |
| Rollouts | manual | manual-ish recreate | Deployments/RollingUpdate | GitOps/progressive delivery/policy |
| Cron/tasks | host cron/systemd timers | host cron/one-off compose | CronJob/Job | CronJob/Job/workflow engine |
| Autoscaling | external scripts | limited/manual scale | HPA/KEDA/cluster autoscaler variants | HPA/KEDA/VPA/cluster autoscaler + cloud integration |
| Storage | host bind/named volume | named volumes | PVC/StorageClass | CSI, snapshots, backup, topology |
| Secrets | env files / files | env files / secrets | K8s Secret + external secret manager | cloud IAM/KMS/ESO/CSI/policy |
| Operational burden | low | low-medium | medium | high, or outsourced if managed |

### Prefer Docker when

- It is one service on one machine.
- You need the least moving parts and easiest recovery.
- You can model uptime with systemd, healthchecks, and simple backups.
- You do not need service discovery, rolling updates, HPA, CronJobs, or multi-node scheduling.

### Prefer Docker Compose when

- It is a single-host stack: app + DB + cache + worker.
- You want local development parity and simple `compose.yaml` templates.
- You do not need scheduling across hosts.
- You can tolerate whole-host maintenance and simple manual scale.

### Prefer K3s when

- You want Kubernetes APIs but do not want the weight of a full distro.
- You have edge/IoT/ARM/homelab/small production requirements.
- You need Deployments, Services, Ingress, CronJobs, Jobs, StatefulSets, PVCs, or HPA.
- You need self-healing and rolling updates across one or more nodes.
- You want to run shared platform services such as Valkey/Redis, ingress, metrics, and External Secrets Operator inside the same cluster.

### Prefer a more complex solution when

- The cluster is business-critical and spans zones/regions.
- You need mature cloud LoadBalancers, CSI storage, IAM, KMS, and managed upgrades.
- Multiple teams need tenancy boundaries, policy-as-code, audit, SSO, admission controls, and platform support.
- You need standardized node images and immutable OS management (Talos), stronger compliance hardening (RKE2/OpenShift), or managed lifecycle (EKS/GKE/AKS).
- You need reliable cluster autoscaling across cloud instance groups.

## K3s sizing and topology

K3s documented minimums are small, but workloads consume extra resources. Treat minima as control-plane baseline, not application capacity.

| Topology | Use case | Notes |
|---|---|---|
| 1 server, SQLite | dev, homelab, edge, one device | Simple; no control-plane HA. Back up app data separately. |
| 1 server + N agents | small cluster | Control plane is a single point of failure. Agents run workloads. |
| 3 server nodes, embedded etcd | HA small/medium cluster | Use odd number of etcd voters; SSDs strongly recommended. |
| K3s with external DB | larger or DB-managed control plane | External DB becomes critical dependency; size and back it up. |

Hardware baseline from K3s requirements:

- Server: 2 cores / 2 GB minimum baseline.
- Agent: 1 core / 512 MB minimum baseline.
- Use SSD where possible; avoid SD/eMMC for write-heavy control-plane data.

## Networking and exposure

K3s bundles Traefik and ServiceLB by default. That is convenient for small clusters, but confirm the actual environment:

- Homelab/single LAN: Traefik + ServiceLB may be enough.
- Bare metal with real L2/L3 needs: consider MetalLB or kube-vip.
- Cloud: prefer the cloud provider load balancer/controller when available.
- Production HTTP: define Ingress/Gateway explicitly, terminate TLS deliberately, and monitor cert renewal.

Important ports:

- TCP 6443: Kubernetes API / K3s supervisor.
- UDP 8472: Flannel VXLAN, if using default Flannel backend. Do not expose publicly.
- TCP 10250: kubelet metrics/API between nodes.
- TCP 2379-2380: etcd server-to-server only for HA embedded etcd.

## Storage choices

K3s includes local-path-provisioner. It dynamically provisions local node storage and is useful for labs and single-node edge workloads. It does not magically make storage portable.

| Workload | Good storage choice | Avoid |
|---|---|---|
| Stateless web/API | no PVC | PVC just for caches/logs that can be ephemeral. |
| Single-node edge app | local-path PVC + node pinning | Assuming the pod can move nodes with data. |
| Shared uploads/media | RWX storage: NFS, Longhorn RWX, Ceph/Rook, managed file share | Multiple replicas writing to node-local disk. |
| Redis/Valkey cache | StatefulSet PVC if persistence needed; otherwise emptyDir | Treating cache PVC as primary source of truth. |
| Production DB | managed DB or operator + tested backup/restore | Unbacked local-path database PVC. |

## Redis/Valkey shared inside K3s

Use one shared Redis/Valkey instance only when workloads are in the same trust and lifecycle boundary. Otherwise split by namespace/environment or use ACLs and separate databases/instances.

Recommended simple in-cluster pattern:

- `StatefulSet` with one replica for simple cache/queue.
- `Service` named `valkey` for stable DNS.
- PVC for append-only file only when data should survive restarts.
- NetworkPolicy that allows only app/worker namespaces or labels to connect.
- Resource requests/limits, readiness probe, and configured maxmemory/eviction if used as cache.

For production HA, prefer a Valkey/Redis operator or managed service rather than hand-rolling Sentinel/cluster manifests.

## Worker services and scheduled tasks

Do not put every background role in one Deployment. Use separate Deployments:

- `email-worker`
- `image-worker`
- `billing-worker`
- `webhook-worker`

Each gets independent:

- image/command
- replica count
- resources
- HPA/KEDA policy
- rollout history
- logs and alerts

Use Kubernetes `CronJob` for scheduled tasks. Set:

- `concurrencyPolicy: Forbid` for non-reentrant jobs.
- `startingDeadlineSeconds` for missed-run tolerance.
- `successfulJobsHistoryLimit` and `failedJobsHistoryLimit`.
- `ttlSecondsAfterFinished` in the job template when cleanup is desired and supported.

## Autoscaling

Kubernetes HPA requires metrics and resource requests. For K3s:

1. Ensure metrics-server is installed and working: `kubectl top nodes`.
2. Set CPU/memory requests on target containers.
3. Use `autoscaling/v2` HPA.
4. Test under load; inspect `kubectl describe hpa`.

For workers, CPU/memory often correlate poorly with backlog. Use KEDA or a custom/external metrics adapter to scale from queue length, stream lag, pending jobs, or HTTP request rate.

When an HPA targets a Deployment, omit `spec.replicas` from the Deployment manifest after initial setup. Otherwise server-side apply, GitOps tools, or repeated `kubectl apply` can fight the HPA by resetting the replica count back to the manifest value.

Node autoscaling is environment-specific. K3s on a few bare-metal nodes usually does not have transparent node autoscaling. If the requirement is autoscaling infrastructure, managed Kubernetes or a cloud-integrated setup is usually a better fit.

## Host devices on K3s edge nodes

Host devices are common in K3s edge clusters, but they are not normal portable Kubernetes resources.

- Label nodes that physically have the device and pin workloads with `nodeSelector` or node affinity.
- Prefer a device plugin when the device type is reused across a fleet; this avoids broad `hostPath`/`privileged` access and lets Kubernetes schedule based on extended resources.
- `hostPath` device mounts are blocked by `baseline` and `restricted` Pod Security Standards. Use an isolated namespace and make the security exception explicit.
- Many device nodes are blocked by container device cgroups unless the container is privileged or the runtime/device plugin grants the device.
- Do not autoscale replicas for an exclusive physical device unless the scheduler can allocate multiple devices safely.

## Secret management

Kubernetes Secret facts:

- Secret values are base64-encoded, not encrypted by base64.
- Secrets are stored unencrypted by default unless encryption at rest is configured.
- `list` access effectively reveals all Secrets in scope.
- A user who can create Pods that mount a Secret can usually exfiltrate it through that Pod.

Patterns:

| Scenario | Pattern |
|---|---|
| Local/dev only | `kubectl create secret ...` from local files; do not commit generated YAML. |
| GitOps | External Secrets Operator or sealed/encrypted secrets. |
| Cloud secret manager | ESO + AWS/GCP/Azure provider. |
| Vault/OpenBao | ESO or Secrets Store CSI Driver provider. |
| Pod needs secret as file only | Secrets Store CSI Driver can mount external secrets without syncing all values to K8s Secret, depending on provider/config. |

Prefer External Secrets Operator when apps expect normal Kubernetes Secret env vars/volumes. Prefer Secrets Store CSI Driver when mounting secrets as files from external stores is a better fit.

## Manifest conventions

- Put `app.kubernetes.io/name`, `app.kubernetes.io/component`, and `app.kubernetes.io/part-of` labels on every resource.
- Keep selector labels immutable and minimal.
- Use one YAML document per resource separated by `---`.
- Prefer `apps/v1`, `batch/v1`, `autoscaling/v2`, `networking.k8s.io/v1`.
- Avoid the `default` namespace in examples unless demonstrating cluster defaults.
- Use comments for placeholders instead of fake secrets.

## Operational checklist

Before saying a K3s deployment is production-ready:

- [ ] All images are pinned to versions/digests.
- [ ] Every container has requests/limits.
- [ ] Every server has readiness/liveness probes.
- [ ] Secrets are not committed; external secret flow is documented.
- [ ] StorageClass and PVC behavior is understood.
- [ ] Backups and restore tests exist for application data and control-plane datastore.
- [ ] Ingress/TLS/cert renewal are tested.
- [ ] NetworkPolicy isolates sensitive services.
- [ ] RBAC follows least privilege.
- [ ] Metrics/logging/alerts are installed.
- [ ] Upgrade and rollback process is documented.
- [ ] Node/firewall ports are restricted.
