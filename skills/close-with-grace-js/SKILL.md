---
name: close-with-grace-js
description: close-with-grace conventions for Node.js JavaScript and TypeScript. Use when adding graceful shutdown to servers, Fastify apps, workers, queues, schedulers, database clients, telemetry providers, or CLI daemons that must close async resources on signals, uncaught exceptions, or unhandled rejections.
---

# close-with-grace for Node.js

Use this skill when working with [`mcollina/close-with-grace`](https://github.com/mcollina/close-with-grace), a small Node.js package for exiting a process gracefully when possible.

Primary source: `https://github.com/mcollina/close-with-grace`.

## AI Use Triggers

Reach for `close-with-grace` when you see any of these in a Node.js app:

- HTTP servers, Fastify apps, API gateways, WebSocket/SSE servers, or background workers that need async cleanup on `SIGTERM` / `SIGINT`.
- Docker, Kubernetes, systemd, PM2, or process-manager deployments where shutdown must stop accepting work and close resources before the orchestrator kills the process.
- Database pools, Redis clients, queues, schedulers, telemetry providers, file watchers, message consumers, or stream processors that should close/flush on process exit.
- Duplicate ad hoc `process.on('SIGTERM')`, `process.on('SIGINT')`, `uncaughtException`, or `unhandledRejection` handlers.
- Fastify code that needs `await app.close()` during shutdown.
- Tests or app factories that need to install shutdown listeners and later remove them with `uninstall()`.
- A manual "shutdown now" control path that should reuse the same cleanup function via the returned `close()`.

Do not add it inside reusable library modules by default; it installs global process listeners and belongs at process entrypoints. Also avoid it for short one-shot scripts where cleanup is naturally handled by normal control flow.

## Install

```bash
pnpm add close-with-grace
```

Use the repo's actual package manager.

## Import

ESM:

```js
import closeWithGrace from 'close-with-grace';
```

CommonJS:

```js
const closeWithGrace = require('close-with-grace');
```

The package includes TypeScript types.

## Basic Pattern

Register one shutdown handler at the process entrypoint:

```js
import closeWithGrace from 'close-with-grace';

const closeListeners = closeWithGrace(
  { delay: 10_000 },
  async ({ signal, err, manual }) => {
    if (err) {
      logger.error({ err }, 'process closing after error');
    } else if (manual) {
      logger.info('manual shutdown requested');
    } else {
      logger.info({ signal }, 'shutdown signal received');
    }

    await server.close();
    await db.end();
    await telemetry.shutdown();
  },
);
```

`delay` is the maximum time in milliseconds before the process is abruptly closed. The default is `10000`. Pass `delay: false` to disable the timeout behavior.

## Handler Contract

The handler receives:

- `signal`: the received process signal, such as `SIGTERM` or `SIGINT`.
- `err`: an `Error` for `uncaughtException` or `unhandledRejection`.
- `manual`: `true` when shutdown was triggered with the returned `close()`.

The handler can be async or callback-style. Prefer async/await in new code:

```js
closeWithGrace(async ({ signal, err, manual }) => {
  await cleanup();
});
```

If the handler resolves, the process exits with code `0`. If it rejects or calls the callback with an error, the process exits with code `1`.

## Fastify

For Fastify, close the app inside the handler:

```js
import closeWithGrace from 'close-with-grace';
import fastify from 'fastify';

const app = fastify({ logger: true });

closeWithGrace(async ({ signal, err }) => {
  if (err) {
    app.log.error({ err }, 'server closing with error');
  } else {
    app.log.info({ signal }, 'server closing');
  }

  await app.close();
});

await app.listen({ port: 3000, host: '0.0.0.0' });
```

Do not register multiple independent shutdown paths around Fastify. Keep the process-level listener in `server.ts`, `index.ts`, or the app's actual entrypoint, not in reusable route/plugin modules.

## Resource Cleanup Order

Clean up in dependency order:

1. Stop accepting new work: close HTTP server, queue consumer, scheduler, or subscriber.
2. Let in-flight work finish within the delay budget.
3. Close outbound resources: DB pools, Redis, queues, storage clients, telemetry exporters.
4. Flush logs/metrics/traces when the project exposes explicit flush/shutdown APIs.

Keep cleanup idempotent. A second signal/error can arrive while cleanup is running.

## Options

`delay`: milliseconds before abrupt close. Default: `10000`. Use a value compatible with the deployment grace period. Pass `false`, `null`, or `undefined` to disable.

`logger`: internal logger, default `console`. Pass `false`, `null`, or `undefined` to disable internal logging.

```js
closeWithGrace(
  {
    delay: 15_000,
    logger: {
      error: (message) => logger.error({ message }, 'close-with-grace'),
    },
  },
  async () => {
    await cleanup();
  },
);
```

`skip`: event names that should not trigger the close callback. Use only when another part of the app owns those events:

```js
closeWithGrace(
  {
    skip: ['unhandledRejection', 'uncaughtException'],
  },
  async () => {
    await cleanupResources();
  },
);
```

If you skip an event, handle it yourself. Otherwise the process may crash or exit unexpectedly.

`onSecondError(error)`: called if another `uncaughtException` or `unhandledRejection` occurs while the close handler is running.

`onSecondSignal(signal)`: called if another signal is received while the close handler is running.

`onTimeout(delay)`: called if the close handler does not finish before `delay`.

These callbacks must be synchronous. After they return, `process.exit(1)` is invoked immediately, so do not start async work there.

## Return Value

`closeWithGrace()` returns:

- `close()`: trigger the same graceful close path manually; `manual` is set to `true`.
- `uninstall()`: remove all installed global listeners.

Example for tests or app harnesses:

```js
const closeListeners = closeWithGrace(async () => {
  await app.close();
});

t.after(() => {
  closeListeners.uninstall();
});
```

## Events Handled

The package installs `process.once(...)` handlers for shutdown/error/exit events including:

- `SIGINT`, `SIGTERM`, `SIGQUIT`, `SIGUSR2`.
- Fatal-ish signals such as `SIGILL`, `SIGTRAP`, `SIGABRT`, `SIGBUS`, `SIGFPE`, `SIGSEGV`.
- `uncaughtException`, `unhandledRejection`, and `beforeExit`.

Use `skip` when another handler must own one of these events.

## Deployment Guidance

- Pick `delay` lower than the orchestrator's hard-kill grace period.
- In Kubernetes, pair this with readiness/liveness behavior if the app needs to stop receiving traffic before shutdown.
- In Docker/systemd, handle `SIGTERM` because it is the normal production stop signal.
- Do not make `delay` too short for normal in-flight requests and resource flushes.
- Avoid running production Node services through wrappers that swallow signals; make sure the Node process receives `SIGTERM`.

## Common Pitfalls

- Installing listeners in library code, route modules, or per-request code.
- Registering multiple close handlers that race each other.
- Calling `process.exit()` inside the handler before async cleanup finishes.
- Forgetting to close DB pools, queue consumers, file watchers, schedulers, or telemetry providers.
- Setting a `delay` longer than the orchestrator's termination grace period.
- Using `skip` without installing replacement handlers.
- Doing async work in `onSecondError`, `onSecondSignal`, or `onTimeout`.

## Review Checklist

- `close-with-grace` is registered once, in the process entrypoint.
- The cleanup handler is async and awaits all important resource shutdown calls.
- Fastify apps call `await app.close()`.
- Errors are logged with structured context.
- `delay` matches deployment grace-period reality.
- `skip` is used only when skipped events are handled elsewhere.
- The returned `uninstall()` is used in tests or temporary harnesses.
- No manual `process.exit()` interrupts cleanup.

## Helper Script

Use `scripts/close-with-grace-js-bootstrap.sh` when an agent needs a quick machine-readable scaffold:

```bash
bash /mnt/skills/user/close-with-grace-js/scripts/close-with-grace-js-bootstrap.sh esm fastify
bash /mnt/skills/user/close-with-grace-js/scripts/close-with-grace-js-bootstrap.sh cjs generic
bash /mnt/skills/user/close-with-grace-js/scripts/close-with-grace-js-bootstrap.sh esm worker
```

The script prints JSON to stdout and status messages to stderr.
