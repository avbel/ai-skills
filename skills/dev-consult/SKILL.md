---
name: dev-consult
description: Get a second opinion when stuck — a fresh context one tier above the session, briefed with evidence rather than conclusions, capped before the work is marked blocked. Use after two failed evidence-backed attempts at the same problem, when evidence contradicts itself, when a costly technical ruling must be made while the user is away, or when the user says "use advisor", "consult", or "get a second opinion".
---

# Consult — Second Opinion When Stuck

A supporting skill of the `dev-*` set, triggered from `dev-debug`, `dev-loop`, or any workflow that stalls. User rules on models and agents, and repository instructions, override this file.

## When

- Two evidence-backed attempts at the same problem failed — fix attempts, hypotheses, or review rounds, counted by the calling workflow; consulting does not start a new count.
- Evidence contradicts itself: a value the code cannot produce, a test that fails in only one environment with identical inputs.
- A technical ruling with a high cost if wrong must be made while the user is away.
- The user asks for it.

Never for preference, scope, or authority questions, or for anything a `dev-loop` stop condition covers: those stay with the user. A consultant's answer is never consent.

## Who

- A fresh subagent one tier above the session's model, read-only, with model and effort set explicitly (medium effort unless the user said otherwise). When the session already runs the strongest available model, use the same tier: the value is the fresh context.
- A built-in advisor tool that forwards the whole transcript fits only while the session context is small — a heuristic cutoff of roughly 50k tokens, not a measured one. Its cost grows with the transcript, and long development sessions often carry 200k or more, which makes it the most expensive call available; it also reads your conclusions along with your evidence.
- Inside a `dev-loop` worker, which may not spawn subagents, do not consult: return BLOCKED with the evidence, and the controller consults.

## Brief

Write it to a file when it runs past a few lines, and pass the path:

```
Problem: <symptom, exact error, the command that fails now>
Evidence: <file:line, log lines, inputs — as paths, not pasted dumps>
Ruled out: <each attempt and what it showed>
Question: <one question>
Return: the most likely cause or option, and one cheap experiment that would falsify it. Do not edit files.
```

List what was ruled out and why, but not the hypothesis you currently favor: a consultant handed a conclusion tends to confirm it.

## After

1. Run the falsifying experiment yourself before acting on the answer. Evidence you hold beats the consultant's claim; record the conflict when they disagree.
2. Resolved: continue in the calling workflow. In `dev-loop`, record `Consult: <question> — <answer> — <experiment result>` in the ledger.
3. Unresolved and the question is architecture-level (the fix needs a design change, not a code change): one second consult on the strongest available model at medium effort, with the first answer and the experiment result in the brief.
4. Still unresolved: stop consulting. At most two consults per problem. Interactive, report to the user with the evidence and both answers; unattended, mark the work BLOCKED with the question and a recommended answer.
