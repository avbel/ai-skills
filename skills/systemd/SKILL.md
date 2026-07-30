---
name: systemd
description: Create, edit, extend, validate, operate, and troubleshoot systemd system and user units, including services, drop-ins, timers, mounts, automounts, and transient jobs with systemd-run. Use when writing unit files, changing vendor units, managing user services and lingering, replacing cron, applying resource limits, or diagnosing systemctl and journalctl failures.
---

# systemd

Create the smallest correct unit, preserve vendor files with drop-ins, validate
before activation, and leave the user with commands to inspect and recover it.

## Start with the target host

1. Inspect the installed version and unit:

   ```bash
   systemctl --version
   systemctl cat example.service
   systemctl show example.service -p FragmentPath -p DropInPaths
   ```

2. Choose the manager and persistence model:

   | Need | Use |
   |---|---|
   | Boot-wide privileged service | system unit |
   | Service owned by one login user | user unit |
   | Durable unit or schedule across reboots | installed unit file |
   | One-off command or experiment | `systemd-run` transient unit |
   | Static filesystem mount | `/etc/fstab` by default |
   | Mount with explicit unit dependencies | `.mount`, optionally `.automount` |

3. Read the host's `man systemd.<type>` and `man systemd.exec` before using
   version-sensitive directives. Do not copy a directive merely because a newer
   online man page lists it.

## System and user unit paths

| Scope | Local unit path | Control command | Common install target |
|---|---|---|---|
| System | `/etc/systemd/system/` | `sudo systemctl` | `multi-user.target` |
| Current user | `~/.config/systemd/user/` | `systemctl --user` | `default.target` |
| All users | `/etc/systemd/user/` | `systemctl --user` per user manager | `default.target` |

Treat `/usr/lib/systemd/system/` and `/lib/systemd/system/` as
package/vendor-owned. Do not edit those files in place.

## Create a service

Use `Type=exec` for a normal long-running foreground process when supported. It
reports startup success only after the executable was invoked. Use
`Type=oneshot` for a command that should finish. Avoid `Type=forking` unless
integrating a legacy daemon that truly double-forks.

```ini
[Unit]
Description=Example API
Wants=network-online.target
After=network-online.target

[Service]
Type=exec
User=example
Group=example
WorkingDirectory=/srv/example
ExecStart=/srv/example/bin/server --config /etc/example/config.toml
Restart=on-failure
RestartSec=5s
StateDirectory=example

[Install]
WantedBy=multi-user.target
```

Apply dependency semantics deliberately:

- `After=` and `Before=` set ordering only.
- `Wants=` pulls in a non-fatal dependency.
- `Requires=` pulls in a dependency and propagates some failures.
- Do not add `network-online.target` unless the service truly requires
  configured networking at startup.

`ExecStart=` is not a shell command line. Do not use pipes, redirections,
globbing, `&&`, or shell built-ins unless a shell is intentionally invoked:
`ExecStart=/bin/sh -c '...'`. Prefer a direct executable and separate arguments.
Keep secrets out of `Environment=` and unit files; use credentials or
permission-restricted files supported by the target systemd version.

For reusable examples, read
[`references/unit-examples.md`](references/unit-examples.md).

## Edit or extend an existing unit

Prefer a drop-in:

```bash
sudo systemctl edit example.service
systemctl --user edit example.service
```

This creates an override under the appropriate `*.service.d/` directory and
reloads manager configuration after a successful edit. Use
`systemctl edit --full` only when intentionally replacing the complete unit;
full copies can hide later vendor improvements.

Drop-ins merge with the original. For list-valued settings such as
`ExecStart=`, clear the inherited list before replacing it:

```ini
[Service]
ExecStart=
ExecStart=/srv/example/bin/server --safe-mode
```

Inspect the effective source with `systemctl cat`. Remove local overrides with
`systemctl revert example.service` only after confirming that all local changes
for that unit should be discarded. If files were edited manually, run
`systemctl daemon-reload` or `systemctl --user daemon-reload`; reloading unit
definitions does not restart running services, so restart or reload the unit
separately when required.

## User-level units

Create units under `~/.config/systemd/user/` and consistently pass `--user`:

```bash
systemctl --user daemon-reload
systemctl --user enable --now example.service
systemctl --user status example.service
journalctl --user -u example.service
```

Do not add `User=` or `Group=` to a normal user unit: the user manager cannot
switch to another identity or grant root privileges.

By default, the user manager is tied to login lifecycle. If enabled user units
must start at boot and remain after logout, enable lingering with appropriate
authorization:

```bash
loginctl enable-linger "$USER"
loginctl show-user "$USER" -p Linger
```

Enable lingering only when that lifecycle is intended.

## Timers

Use a `.timer` plus the unit it activates. A timer named `backup.timer`
activates `backup.service` by default. Use a `Type=oneshot` service without
`RemainAfterExit=yes` for repeating work.

```ini
[Unit]
Description=Run backup every day

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=yes
RandomizedDelaySec=15min

[Install]
WantedBy=timers.target
```

- `Persistent=yes` catches up a missed `OnCalendar=` activation when the timer
  becomes active again.
- `AccuracySec=` permits coalescing wakeups; it is not random jitter.
- `RandomizedDelaySec=` spreads load over an interval.
- Validate calendar syntax with
  `systemd-analyze calendar '*-*-* 03:00:00'`.
- Enable the timer, not the service:
  `systemctl enable --now backup.timer`.
- Inspect schedules with `systemctl list-timers --all`.
- Add `--user` to every command for a user timer.

## Mounts and automounts

Prefer `/etc/fstab` for ordinary static mounts. Use native units when explicit
unit dependencies, resource controls, or on-demand activation make them
clearer.

A `.mount` filename must encode its absolute `Where=` path:

```bash
systemd-escape --path --suffix=mount /srv/data
# srv-data.mount
```

The unit's filename and `Where=` must match. A minimal unit contains:

```ini
[Mount]
What=/dev/disk/by-uuid/UUID
Where=/srv/data
Type=ext4
Options=defaults

[Install]
WantedBy=local-fs.target
```

For network filesystems, mark the mount as network-backed with `_netdev` when
systemd cannot infer it, and put network ordering on the `.mount` unit. Pair it
with a same-named `.automount` to mount on first access and optionally unmount
after `TimeoutIdleSec=`. Do not place network ordering dependencies on the
`.automount` unit, because that can create ordering cycles. Automounts require
privileged kernel support and are not available to ordinary unprivileged user
managers.

## `systemd-run` transient units

Use `systemd-run` for one-off services, scopes, and temporary timers. Transient
units do not survive reboot; install normal unit files for durable behavior.

Start a named background service:

```bash
sudo systemd-run \
  --unit=example-job \
  --property=Type=exec \
  /usr/local/bin/example-job --once
```

Run as the current user and wait for the command's exit status:

```bash
systemd-run --user \
  --unit=example-job \
  --property=Type=exec \
  --wait --pipe \
  /usr/local/bin/example-job --once
```

Run an existing interactive process in a resource-controlled scope:

```bash
systemd-run --user --scope -p MemoryMax=2G command arg
```

Schedule a transient daily command:

```bash
systemd-run --user \
  --unit=example-report \
  --on-calendar='*-*-* 09:00:00' \
  /usr/local/bin/example-report
```

`-G` is the case-sensitive short form of `--collect`. It unloads the transient
unit after completion even when the command failed:

```bash
systemd-run --user -G --wait --pipe -p Type=exec command arg
```

Use `-G` when automatic cleanup is desired. Omit it when a failed transient
unit should remain inspectable with `systemctl status` until
`systemctl reset-failed`. Journal entries remain available after collection,
but the unit object may already be gone.

Stop and inspect a named transient service:

```bash
sudo systemctl stop example-job.service
systemctl status example-job.service
journalctl -u example-job.service
```

For user units, add `--user` to `systemctl` and use
`journalctl --user -u ...`. To recover a failed named transient unit, inspect
the journal and try `systemctl restart` while it remains loaded. If it was
collected or garbage-collected, rerun the original `systemd-run` command. For a
persistent unit, fix the cause, use `systemctl reset-failed`, then start it.

## Validate and roll out

Run the bundled validator on all related files together so cross-unit
dependencies resolve:

```bash
bash /mnt/skills/user/systemd/scripts/verify-unit.sh --system \
  ./backup.service ./backup.timer

bash /mnt/skills/user/systemd/scripts/verify-unit.sh --user \
  ./example.service
```

Then use the target manager:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now example.service
systemctl status example.service --no-pager
journalctl -b -u example.service
```

Do not claim validation from a non-systemd host. Report whether validation was
structural only or executed with the target host's `systemd-analyze verify`.

## Troubleshoot

Use this order:

1. `systemctl status UNIT --no-pager`
2. `journalctl -b -u UNIT` (add `--user` for user units)
3. `systemctl cat UNIT`
4. `systemctl show UNIT -p FragmentPath -p DropInPaths -p Result -p ExecMainStatus`
5. `systemd-analyze verify FILE...`

Common corrections:

| Symptom | Check |
|---|---|
| `Unit ... not found` | Correct manager, suffix, path, then `daemon-reload` |
| `bad unit file setting` | Section name, directive availability, quoting, line continuations |
| Start succeeds but executable is missing | Prefer `Type=exec`; inspect journal |
| User unit stops at logout | Decide whether lingering is appropriate |
| Timer never runs | Enable the `.timer`; inspect `list-timers`; validate calendar |
| Mount unit rejected | Derive filename from `Where=` with `systemd-escape` |
| Override appears ignored | Inspect `systemctl cat`; clear inherited list directives |
| `start request repeated too quickly` | Fix root cause, then `reset-failed`; do not only raise limits |

## Source baseline

Cross-check against the installed man pages. Primary upstream references
reviewed in July 2026:

- `https://www.freedesktop.org/software/systemd/man/latest/systemd.unit.html`
- `https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html`
- `https://www.freedesktop.org/software/systemd/man/latest/systemctl.html`
- `https://www.freedesktop.org/software/systemd/man/latest/systemd.timer.html`
- `https://www.freedesktop.org/software/systemd/man/latest/systemd.mount.html`
- `https://www.freedesktop.org/software/systemd/man/latest/systemd.automount.html`
- `https://www.freedesktop.org/software/systemd/man/latest/systemd-run.html`
- `https://www.freedesktop.org/software/systemd/man/latest/systemd-analyze.html`

## Installation

Claude Code:

```bash
cp -r skills/systemd ~/.claude/skills/
```

For claude.ai, add `SKILL.md`, `references/unit-examples.md`, and the validator
script to project knowledge, or paste the relevant instructions into the
conversation. If validation runs in the sandbox, allow access to the target
host's systemd commands.
