---
name: code-review
description: Use when reviewing code or PRs — catch production-breaking issues beyond table-stakes checks.
---

# Code Review (Production-Focused)

A code review checklist that catches what standard lists miss. Standard reviews
cover tests, naming, style, error handling, and complexity — those are table
stakes. This checklist focuses on **five production-breaking categories** that
most reviews skip.

Inspired by [Jake Lundberg's "The Code Review Checklist I Actually Use"](https://dev.to/pixel-wraith/the-code-review-checklist-i-actually-use-9ok).

## When to Use

- Any code review or PR review
- When asked to "review this code", "review PR #N", or "check before merging"
- As a mental checklist even for quick scans

## 1. Observability Changes

**"Will I know when this doesn't work?"**

When a PR adds a new code path, the first question isn't "does it work?" — it's
"will I know when it doesn't?"

Check for:

- **Silent `try/catch` blocks** — errors swallowed without logging, metrics, or alerts
- **New endpoints, jobs, or queue consumers** with no metric attached (request rate, error rate, latency)
- **New async/background work** that won't appear in distributed tracing (missing trace propagation, detached spans)
- **New failure modes** that won't trigger any alert

A code path without observability isn't bug-free — it's a bug you won't notice
for weeks. The cost is real; it's just deferred.

## 2. Backward Compatibility of Public Surfaces

**"Will rolling this out break any existing consumer?"**

Most teams check API compatibility for external APIs. Few check for internal ones.

Check on every PR:

- **Function signatures** in shared modules or libraries (added/removed params, type changes)
- **Database columns** — dropped, renamed, or type-changed
- **Environment variables** — new ones marked as required without defaults
- **JSON keys** in any payload another service consumes (removing/renaming is breaking)
- **Message queue payloads** — schema changes that consumers won't handle
- **Config file shape** — new required fields that old deployments won't have

Anything another system depends on is a public surface, even if you don't think
of it that way. These bugs don't show up in review — they show up when the
consumer service rolls.

## 3. Migration Rollout/Rollback Strategy

**"Can this be deployed safely and rolled back if needed?"**

If a PR touches a database migration, ask three questions before approving:

1. **Is it forward-only and backward compatible?**
   - Old app code must run against the new schema during rollout
   - Add columns as nullable, don't drop columns in the same PR that stops writing to them
   - Don't assume the app has already shipped — deploy order isn't guaranteed

2. **Is it idempotent?**
   - Can the migration run twice without breaking anything?

3. **Is it zero-downtime?**
   - No exclusive locks on large tables during peak hours
   - No blocking `ALTER TABLE` on the hot path
   - Large data migrations should be batched, not single-transaction

Treat any PR with a migration as **automatically higher attention**. Cost of
getting it wrong: hours of downtime. Cost of asking three more questions: five minutes.

## 4. Idempotency, Concurrency, and Timeouts

**"What happens when things fail, retry, or overlap?"**

This is the bucket that quietly swallows the most production bugs.

For any PR that introduces:
- A new POST/PUT/PATCH handler
- A new background job or queue consumer
- A new outbound call to a third-party service
- A new write path of any kind

Ask three questions:

1. **Idempotency:** What happens if this runs twice with the same input?
   - Payment processed twice? Order created twice? Duplicate notification?
   - Watch for: missing idempotency keys on payment/order creation

2. **Concurrency:** What happens if two of these run at the same time?
   - Race condition on shared state? Double-spend? Stale read-then-write?
   - Watch for: no locking or optimistic concurrency control on critical sections

3. **Timeouts:** What's the timeout, and what happens when it fires?
   - Background job with no timeout → hangs forever, blocks the queue
   - HTTP call with no timeout → thread/connection pool exhaustion
   - Watch for: missing or infinite timeouts on I/O operations

**Rule of thumb:** Code rarely fails on logic. It fails on what happens when
something *else* fails.

## 5. PR Description Quality

**"Can I understand the intent before reading the code?"**

This isn't a code check — it's the check that has to happen *before* the code check.

A good PR description answers:

1. **What problem does this solve?** (Context, not just what changed)
2. **What solution did the author choose?** (The approach)
3. **What alternatives were considered?** (Why this approach over others)
4. **How can a reviewer test this manually?** (Steps to verify)
5. **What ticket does it link to?** (Traceability)

If the description doesn't answer these, **don't review the code yet — ask for
context first.**

Without context, reviews produce nitpicks instead of catches. The rewrite cycle
on a misunderstood PR is much longer than the description cycle on an understood one.

## Conventional Comments

Every review comment should carry explicit intent. Use [Conventional Comments](https://conventionalcomments.com/):

| Label | Meaning |
|-------|---------|
| `issue (blocking)` | Must be resolved before merge |
| `issue (non-blocking)` | A problem, but author's call |
| `suggestion (non-blocking)` | Proposal for change, author's call |
| `question` | Clarification needed to finish review |
| `nitpick` | Trivial preference, not worth debating |
| `praise` | Something worth highlighting |

When every comment carries the same weight, none of them carry any. Explicit
labels train authors to recognize what matters. Reviews get faster.

## Quick-Reference Checklist

```
[ ] Observability: New code paths have logging, metrics, tracing, alerts?
[ ] Observability: No try/catch blocks swallowing errors silently?
[ ] Backward compat: No breaking changes to shared function signatures?
[ ] Backward compat: No dropped/renamed DB columns without migration path?
[ ] Backward compat: No new required env vars without defaults?
[ ] Backward compat: No removed/renamed JSON keys in consumed payloads?
[ ] Migrations: Forward-compatible (old code runs against new schema)?
[ ] Migrations: Idempotent (safe to re-run)?
[ ] Migrations: Zero-downtime (no exclusive locks on hot tables)?
[ ] Idempotency: Write endpoints safe to retry with same input?
[ ] Concurrency: No race conditions on shared state?
[ ] Timeouts: All I/O operations have explicit timeouts?
[ ] PR description: Answers what/why/alternatives/how-to-test/ticket?
[ ] Comments: Using Conventional Comments labels + decorations?
```

## Triage

You can't run a full checklist on every PR. Triage:

- **The 1000-line refactor with days of back-and-forth?** Usually fine.
- **The 50-line config change that touches the auth path?** That's the one that breaks production.

Small, unassuming PRs that touch critical paths (auth, payments, data migrations,
configuration) deserve the same attention as large, obvious ones.

## Common Pitfalls

| Pitfall | Fix |
|---------|-----|
| Stopping at table-stakes (tests, naming) | Always check sections 1–4, even on quick scans |
| Skipping the PR description | Establish intent first — without context, reviews produce nitpicks |
| Rubber-stamping small PRs | A 50-line auth change can be more dangerous than a 1000-line feature |
| Treating all comments equally | Use `(blocking)` / `(non-blocking)` labels to make intent explicit |
| Assuming deploy order | Migrations must work whether the app has rolled out or not |
| Forgetting internal API consumers | Internal outages are still outages |
| Missing failure-mode analysis | Logic is usually correct; retries, concurrency, and timeouts are where bugs live |

## Review Comment Examples

```
issue (blocking): This handler has no idempotency guard. If a client retries, the payment runs twice.

suggestion (non-blocking): Consider extracting this validation into a shared module — it's duplicated in the order handler.

question: What happens to in-flight requests during the deployment window?

nitpick: Trailing whitespace on line 42.

praise: Clean error propagation pattern here — exactly what we need.
```