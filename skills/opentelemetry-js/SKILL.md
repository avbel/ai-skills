---
name: opentelemetry-js
description: OpenTelemetry JavaScript conventions for Node.js-only JavaScript and TypeScript services. Use when adding, reviewing, or debugging OTel traces, metrics, SDK setup, auto-instrumentation, exporters, resources, propagation, or sampling in Node.js apps.
---

# OpenTelemetry JavaScript for Node.js

Use this skill for Node.js services written in JavaScript or TypeScript. Do not use it for browser, frontend, React, or Web SDK instrumentation.

Primary source: OpenTelemetry JavaScript docs at `https://opentelemetry.io/docs/languages/js/`, especially Node.js getting started, instrumentation, libraries, exporters, resources, propagation, and sampling.

## First Checks

1. Identify module/runtime shape: CommonJS vs ESM, TypeScript runner (`tsx`, compiled JS, ts-node), package manager, Node version, and app entrypoint.
2. Check whether instrumentation must run before any app imports. It almost always should.
3. Prefer existing project logging/config/env conventions over inventing new wrappers.
4. Keep production exporter endpoints, headers, and sampling in environment variables unless the repo already centralizes them in config code.

## Dependencies

Core Node SDK setup:

```bash
pnpm add @opentelemetry/api @opentelemetry/sdk-node @opentelemetry/auto-instrumentations-node @opentelemetry/sdk-metrics @opentelemetry/sdk-trace-node
```

For OTLP export to a collector/backend:

```bash
pnpm add @opentelemetry/exporter-trace-otlp-proto @opentelemetry/exporter-metrics-otlp-proto
```

For explicit resource attributes in code:

```bash
pnpm add @opentelemetry/resources @opentelemetry/semantic-conventions
```

Use the repo's actual package manager. The commands above use `pnpm` because this skill repository prefers it.

## Bootstrap File

Create a dedicated bootstrap file such as `instrumentation.ts`, `instrumentation.mjs`, or `instrumentation.js`. It must start the SDK before application code imports HTTP clients, servers, database drivers, queues, or frameworks.

Local validation setup:

```ts
import { diag, DiagConsoleLogger, DiagLogLevel } from '@opentelemetry/api';
import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node';
import { resourceFromAttributes } from '@opentelemetry/resources';
import { NodeSDK } from '@opentelemetry/sdk-node';
import {
  ConsoleMetricExporter,
  PeriodicExportingMetricReader,
} from '@opentelemetry/sdk-metrics';
import { ConsoleSpanExporter } from '@opentelemetry/sdk-trace-node';
import {
  ATTR_SERVICE_NAME,
  ATTR_SERVICE_VERSION,
} from '@opentelemetry/semantic-conventions';

diag.setLogger(new DiagConsoleLogger(), DiagLogLevel.INFO);

const sdk = new NodeSDK({
  resource: resourceFromAttributes({
    [ATTR_SERVICE_NAME]: 'my-service',
    [ATTR_SERVICE_VERSION]: '0.1.0',
  }),
  traceExporter: new ConsoleSpanExporter(),
  metricReader: new PeriodicExportingMetricReader({
    exporter: new ConsoleMetricExporter(),
  }),
  instrumentations: [getNodeAutoInstrumentations()],
});

sdk.start();

const shutdown = async () => {
  await sdk.shutdown();
};

process.once('SIGTERM', () => {
  void shutdown().finally(() => process.exit(0));
});
process.once('SIGINT', () => {
  void shutdown().finally(() => process.exit(0));
});
```

## Start Commands

Use the startup form that matches the app:

```bash
node --import ./instrumentation.mjs ./dist/server.js
npx tsx --import ./instrumentation.ts ./src/server.ts
node --require ./instrumentation.js ./dist/server.js
```

For ESM apps, always use `--import` with an `.mjs` bootstrap that calls `register()` from `node:module`. Do not combine `--experimental-loader` with `--require` — loader hooks apply only to ESM, and `--require` only runs CommonJS, so the two cannot share a single bootstrap file:

```bash
node --import ./instrumentation.mjs ./dist/server.js
```

```js
// instrumentation.mjs
import { register } from 'node:module'
import { NodeSDK } from '@opentelemetry/sdk-node'
import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node'

register('@opentelemetry/instrumentation/hook.mjs', import.meta.url)

const sdk = new NodeSDK({ instrumentations: [getNodeAutoInstrumentations()] })
sdk.start()
```

Do not import the app from inside the instrumentation file unless the project already uses that pattern. It is easier to verify startup order when the runtime preloads instrumentation.

## Production Exporters

Prefer OTLP through the OpenTelemetry Collector or an OTLP-compatible backend. Keep endpoint, protocol, headers, and timeouts in env:

```bash
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
OTEL_TRACES_EXPORTER=otlp
OTEL_METRICS_EXPORTER=otlp
OTEL_SERVICE_NAME=my-service
OTEL_RESOURCE_ATTRIBUTES=service.version=0.1.0,deployment.environment=production
```

Use explicit exporters when code-level configuration is already the local pattern:

```ts
import { OTLPMetricExporter } from '@opentelemetry/exporter-metrics-otlp-proto';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-proto';
import { PeriodicExportingMetricReader } from '@opentelemetry/sdk-metrics';
import { NodeSDK } from '@opentelemetry/sdk-node';

const sdk = new NodeSDK({
  traceExporter: new OTLPTraceExporter(),
  metricReader: new PeriodicExportingMetricReader({
    exporter: new OTLPMetricExporter(),
  }),
});
```

Console exporters are for local verification only.

## Auto-Instrumentation

Use `getNodeAutoInstrumentations()` for broad Node coverage. Configure noisy or risky modules explicitly:

```ts
getNodeAutoInstrumentations({
  '@opentelemetry/instrumentation-fs': {
    enabled: false,
  },
});
```

Use individual instrumentation packages when dependency size or exact behavior matters:

```ts
import { ExpressInstrumentation } from '@opentelemetry/instrumentation-express';
import { HttpInstrumentation } from '@opentelemetry/instrumentation-http';

instrumentations: [
  new HttpInstrumentation(),
  new ExpressInstrumentation(),
];
```

For Express, register HTTP instrumentation too. Always check the package README for supported library versions when spans are missing.

## Manual Traces

Use manual spans for business operations that auto-instrumentation cannot see:

```ts
import { SpanStatusCode, trace } from '@opentelemetry/api';

const tracer = trace.getTracer('orders-service', '0.1.0');

export async function chargeOrder(orderId: string) {
  return tracer.startActiveSpan('charge_order', async (span) => {
    try {
      span.setAttribute('order.id', orderId);
      return await charge(orderId);
    } catch (error) {
      span.recordException(error as Error);
      span.setStatus({ code: SpanStatusCode.ERROR });
      throw error;
    } finally {
      span.end();
    }
  });
}
```

Always end spans in `finally`. Avoid high-cardinality attributes unless they are genuinely needed for debugging or correlation.

## Metrics

Create instruments from a named meter:

```ts
import { metrics } from '@opentelemetry/api';

const meter = metrics.getMeter('orders-service', '0.1.0');
const checkoutCounter = meter.createCounter('checkout.started', {
  description: 'Number of checkout flows started',
});
const checkoutLatency = meter.createHistogram('checkout.duration.ms', {
  description: 'Checkout duration in milliseconds',
  unit: 'ms',
});
```

Use counters for monotonic counts, histograms for durations/sizes, and observable gauges only for values read at collection time. Keep attribute sets bounded.

## Logs

OpenTelemetry JavaScript logs are still less mature than traces and metrics. Do not add an OTel log pipeline unless the user asks for it or the project already has one. For Node services using Pino or another logger, prefer adding trace/span IDs to structured logs and exporting logs through the existing logging pipeline.

## Resources

Every service must have a stable `service.name`. Add `service.version` when available. Prefer environment-driven resource attributes for deployment-specific values:

```bash
OTEL_SERVICE_NAME=payment-api
OTEL_RESOURCE_ATTRIBUTES=service.version=1.4.2,deployment.environment=staging
```

The Node SDK detects process and runtime resources by default and reads `OTEL_RESOURCE_ATTRIBUTES`. Add extra detectors only when the deployment environment needs them, such as container resource detection.

## Propagation

HTTP and common framework/client instrumentation usually propagates trace context automatically. Only use manual propagation for custom protocols, queues without supported instrumentation, or hand-rolled transports. In those cases, use the OpenTelemetry propagation API to inject and extract context rather than creating ad hoc trace headers.

## Sampling

Default JavaScript SDK behavior samples all traces. For production volume control, prefer environment configuration:

```bash
OTEL_TRACES_SAMPLER=traceidratio
OTEL_TRACES_SAMPLER_ARG=0.1
```

Use code-level samplers only when the repo already keeps telemetry policy in code.

## Troubleshooting

- Enable diagnostic logging with `diag.setLogger(new DiagConsoleLogger(), DiagLogLevel.DEBUG)`.
- First prove the SDK runs with console exporters, then switch to OTLP.
- If manual spans export but auto spans do not, check startup order and supported library versions.
- If no spans appear, look for app/framework imports that run before instrumentation preload.
- If metrics do not export, verify a `metricReader` is configured.
- If trace IDs do not connect across services, verify propagation headers reach the downstream process and no proxy strips them.
- Always call `sdk.shutdown()` on graceful process shutdown so batched telemetry flushes.

## Anti-Patterns

- Browser/Web SDK packages in Node.js services.
- Importing the app or instrumented libraries before `sdk.start()`.
- Hardcoding production exporter secrets, tenant headers, or endpoints in source.
- Leaving console exporters as the production path.
- Creating spans without `finally { span.end(); }`.
- High-cardinality metric attributes such as raw URL, user email, session token, or unbounded IDs.
- Adding OTel logs by default while the JS logs signal is still in development.

## Helper Script

Use `scripts/otel-node-bootstrap.sh` when an agent needs a quick machine-readable dependency and startup scaffold:

```bash
bash /mnt/skills/user/opentelemetry-js/scripts/otel-node-bootstrap.sh ts payment-api
bash /mnt/skills/user/opentelemetry-js/scripts/otel-node-bootstrap.sh mjs payment-api
bash /mnt/skills/user/opentelemetry-js/scripts/otel-node-bootstrap.sh cjs payment-api
```

The script prints JSON to stdout and status messages to stderr.
