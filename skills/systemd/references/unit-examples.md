# systemd unit examples

Use these as starting points. Replace paths, identities, dependencies, and
resource limits with values verified on the target host.

## System service

Create `/etc/systemd/system/example-worker.service`:

```ini
[Unit]
Description=Example queue worker
Wants=network-online.target
After=network-online.target

[Service]
Type=exec
User=example
Group=example
WorkingDirectory=/srv/example
EnvironmentFile=-/etc/example/worker.env
ExecStart=/srv/example/bin/worker
Restart=on-failure
RestartSec=5s
TimeoutStopSec=30s
StateDirectory=example
NoNewPrivileges=yes
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
```

Validate and activate:

```bash
systemd-analyze verify /etc/systemd/system/example-worker.service
sudo systemctl daemon-reload
sudo systemctl enable --now example-worker.service
systemctl status example-worker.service --no-pager
journalctl -b -u example-worker.service
```

Do not add hardening directives blindly. Confirm the service still has access
to every required path, socket, device, capability, and namespace.

## Vendor-unit drop-in

Create the override through the manager:

```bash
sudo systemctl edit example.service
```

Replace an inherited `ExecStart=` and add restart behavior:

```ini
[Service]
ExecStart=
ExecStart=/usr/local/libexec/example --config /etc/example/local.conf
Restart=on-failure
RestartSec=10s
```

Inspect and apply:

```bash
systemctl cat example.service
sudo systemctl restart example.service
```

`systemctl edit` reloads the manager configuration when the edit is saved.
Manual filesystem edits require `systemctl daemon-reload`.

## User service

Create `~/.config/systemd/user/example-agent.service`:

```ini
[Unit]
Description=Example user agent

[Service]
Type=exec
WorkingDirectory=%h/.local/share/example
ExecStart=%h/.local/bin/example-agent
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=default.target
```

Activate and inspect:

```bash
systemctl --user daemon-reload
systemctl --user enable --now example-agent.service
systemctl --user status example-agent.service --no-pager
journalctl --user -b -u example-agent.service
```

If it must run before login and after logout:

```bash
loginctl enable-linger "$USER"
loginctl show-user "$USER" -p Linger
```

## Service plus timer

Create `backup.service`:

```ini
[Unit]
Description=Create example backup

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/example-backup
```

Create `backup.timer` in the same unit directory:

```ini
[Unit]
Description=Run example backup daily

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=yes
RandomizedDelaySec=15min

[Install]
WantedBy=timers.target
```

Validate and enable:

```bash
systemd-analyze calendar '*-*-* 03:00:00'
systemd-analyze verify ./backup.service ./backup.timer
sudo systemctl daemon-reload
sudo systemctl enable --now backup.timer
systemctl list-timers --all
```

For user timers, place both files under `~/.config/systemd/user/` and add
`--user` to `systemctl` and `systemd-analyze` commands.

## Mount and automount

Derive the names:

```bash
systemd-escape --path --suffix=mount /srv/archive
systemd-escape --path --suffix=automount /srv/archive
```

Create `srv-archive.mount`:

```ini
[Unit]
Description=Example archive mount

[Mount]
What=server.example:/archive
Where=/srv/archive
Type=nfs
Options=_netdev,nofail
TimeoutSec=30s
```

Create `srv-archive.automount`:

```ini
[Unit]
Description=Automount example archive

[Automount]
Where=/srv/archive
TimeoutIdleSec=10min

[Install]
WantedBy=multi-user.target
```

Enable the automount, not both units:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now srv-archive.automount
systemctl status srv-archive.automount srv-archive.mount
```

The `.automount` activates the same-named `.mount` on access. Keep
network-ordering dependencies off the `.automount` unit.

## `systemd-run`

Run a named background system service:

```bash
sudo systemd-run \
  --unit=example-import \
  -p Type=exec \
  -p MemoryMax=2G \
  /usr/local/bin/example-import /srv/input.json
```

Inspect or stop it:

```bash
systemctl status example-import.service
journalctl -u example-import.service
sudo systemctl stop example-import.service
```

Wait for a user job and automatically collect its unit:

```bash
systemd-run --user \
  --unit=example-import \
  -G --wait --pipe \
  -p Type=exec \
  /usr/local/bin/example-import "$HOME/input.json"
```

`-G` means `--collect`: after completion, including failure, the transient unit
is unloaded. The journal remains queryable, but `systemctl status` may report
that the unit is not found.

Run a temporary timer:

```bash
systemd-run --user \
  --unit=example-reminder \
  --on-active=30min \
  /usr/local/bin/example-reminder
```

Stop both sides of a scheduled transient job:

```bash
systemctl --user stop example-reminder.timer example-reminder.service
```

Transient services and timers do not survive reboot. Use installed unit files
for a durable schedule.
