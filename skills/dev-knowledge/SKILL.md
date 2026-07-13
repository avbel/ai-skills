---
name: dev-knowledge
description: Compound engineering — capture solved problems, root causes, and project decisions as small linked markdown notes in docs/knowledge/, and consult them before starting new work. Use after solving a non-trivial bug or problem, after a decision worth remembering, when the user says "remember this" / "write this down", or at the start of a task to check for prior lessons.
---

# Project Knowledge Base — Compound Engineering

Each solved problem should make the next one cheaper. Capture lessons as small, linked markdown notes inside the repo, and **read them before repeating work**. Part of the `dev-*` development-cycle skill set (see `dev-cycle`).

## Layout

```
docs/knowledge/
  INDEX.md                     # the only file read by default — one line per note
  flaky-s3-timeouts.md
  why-we-chose-pg-mem.md
  auth-token-refresh-race.md
```

- One note = one lesson. Kebab-case filename that states the topic, not a date or ticket number.
- `INDEX.md` groups notes under a few `##` headings (e.g. Database, External APIs, Build/CI, Decisions) with one line each: `- [auth-token-refresh-race](auth-token-refresh-race.md) — refresh must be mutex-guarded; two tabs = logout loop`.
- If the project already keeps notes elsewhere (`docs/adr/`, a wiki export), extend that location instead of creating a parallel one.

## Note Format (10–30 lines, hard cap ~50)

```markdown
# Auth token refresh race

**Context:** what part of the system, when this happened
**Symptom:** what we observed (error text verbatim — it's what gets grepped for)
**Root cause:** the actual mechanism, 2–4 sentences
**What didn't work:** approaches tried and abandoned, one line each with the reason — dead ends are the most expensive knowledge to re-derive
**Fix / decision:** what we did and why
**Watch out:** how this bites next time, if applicable

Related: [why-we-chose-pg-mem](why-we-chose-pg-mem.md), [docs/solutions/session-storage.md](../solutions/session-storage.md)
```

- **Links are the value** — always add `Related:` links to sibling notes and solution docs (`dev-problem-solving` output), and add a back-link in the notes you reference. An unlinked note won't be rediscovered.
- Include verbatim error messages and exact library versions — future greps land on them.
- Notes are for **non-obvious** lessons: surprising root causes, vendor quirks, "we tried X and it failed because Y". Not for things the code or README already says.
- **Decision notes pass a three-condition filter:** record a decision only when it's (a) hard to reverse, (b) its rationale is surprising, and (c) there was a real trade-off. Routine choices with an obvious winner don't get notes — a knowledge base padded with non-decisions stops being read.

## When to Write (triggered by other skills)

- After `dev-debug` Phase 3, when the hunt took real effort → symptom/root-cause note
- After `dev-problem-solving` → decision note linking to the solution doc
- After `dev-feature`, only if something genuinely surprised you
- When the user says "remember this"
- **Immediately when the user corrects you** on something a note or convention should have prevented — capture the rule in the same turn, while the cost is fresh. Mark it as either a hard constraint (**MUST NOT** — violating it breaks things) or a convention (*usually do X* — deviation needs a reason); the distinction tells future agents how much freedom they have.

Writing a note is a 2-minute task: draft it, show the user the file, done. Don't ask permission for each note in a project that already has `docs/knowledge/` — its presence is the standing instruction.

**Close the loop on first use:** when creating `docs/knowledge/` in a project for the first time, also propose a one-line addition to the project's `CLAUDE.md`/`AGENTS.md`: *"Before starting a task, check `docs/knowledge/INDEX.md` for prior lessons."* Written notes that no future agent reads are wasted — this line is what makes the knowledge compound.

## When to Read (this is where the payoff is)

At the **start** of any `dev-feature`, `dev-problem-solving`, or `dev-debug` task in a repo that has `docs/knowledge/`:

1. Read `INDEX.md` only (cheap — one small file).
2. Open a full note only when its index line matches the current task's area.
3. When debugging, additionally grep the notes for the error message: `grep -ril "<error text>" docs/knowledge/`.

Never bulk-read the whole knowledge directory — the index exists so you don't have to.

## Maintenance (piggyback, don't schedule)

When touching a note's area and the note is wrong or stale: update it or delete it in the same commit. A knowledge base that lies is worse than none. If `INDEX.md` outgrows ~60 entries, split by heading into per-topic index files linked from the main one.
