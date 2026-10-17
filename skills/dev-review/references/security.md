# Security review details

Check changed trust boundaries and their connected callers/callees against the relevant items below. A security finding needs the same rigor as any other: name the concrete attack ("attacker does X, gets Y"), not a vague "could be unsafe".

**Untrusted input reaching a sink.** Trace every new input (request params, headers, file contents, webhook payloads, LLM output) to where it's used:
- SQL/queries built by string concatenation instead of parameters/builders
- Shell commands from `exec`/`spawn` with interpolated input (use arg arrays)
- Paths joined from user input without normalization → traversal (`../`)
- HTML rendering: `innerHTML`, `dangerouslySetInnerHTML`, unescaped template output
- Deserialization of untrusted data (`pickle`, `yaml.load`, Java native); `eval`/`Function(string)` on anything dynamic
- User-supplied URLs that the server fetches → SSRF (validate host allowlist, block internal ranges)
- Untrusted content interpreted as instructions can cause prompt injection. Separate instructions from data, but message roles alone do not prove safety. Trace whether model output can invoke tools, disclose secrets, or drive privileged actions; verify authorization and validation outside the model. Report a concrete reachable impact.


**AuthZ on every new surface.** Each new endpoint/handler/job answers two questions in code you can point to: *who may call this* (authn) and *may they touch THIS object* (object-level authz — the missing-IDOR-check is the most common diff-level hole; filter by owner/tenant in the query, not after fetch).

- **Authorization read from a client-editable claim** is a bypass: a role or permission field the user can write through the platform's own API (Supabase `user_metadata`), a role in the request body, a client-set header. Privileged checks read a server-controlled source — `app_metadata`, the server session, a row the user cannot write.
- **When the client queries the database directly**, access control lives in row-level security / security rules, and "enabled" is a claim to verify against the diff's migrations: RLS on with no policy denies everything, `USING (true)` allows everyone, and a public read policy on a storage bucket exposes every uploaded file. The policy must compare the authenticated identity (`auth.uid() = user_id`), never a role string the client controls.

**Secrets & sensitive data:**
- No credentials, API keys, or tokens in the diff (grep for `key=`, `secret`, `Bearer`, PEM headers, high-entropy literals) — env/secret-manager only
- Nothing sensitive in logs or error responses: no passwords/tokens/PII in log lines, no stack traces or internal paths sent to clients
- New PII fields: are they excluded from logging/serialization defaults?
- A credential behind a **client-exposed env prefix** (`NEXT_PUBLIC_`, `VITE_`, `PUBLIC_`, `EXPO_PUBLIC_`) is inlined into the shipped bundle by design, as is any key imported into client-reachable code. The finding is a *privileged* credential in that position (service/admin key, provider secret); publishable/anon keys are meant to be public and must not be flagged, or the check gets muted.
- Any credential that reached a commit is **compromised from that commit**, not from the exploit: the finding is incomplete without the rotation step at the provider, because deleting the literal does not un-leak it. Report type, location, and a redacted preview — never echo the raw value into the verdict.

**Crypto & randomness:** no hand-rolled crypto; passwords hashed with argon2/bcrypt/scrypt (never plain SHA/MD5); security tokens from a CSPRNG (`crypto.randomBytes`/`rand::rngs::OsRng`), never `Math.random()`; comparisons of secrets constant-time.

**New dependencies:** before accepting one, check it's actively maintained, the name isn't a typosquat of the package you meant, and `npm audit`/`cargo audit`/`pip-audit` is clean for it. Pin the version.

**Money/quota/state-machine paths:** check for TOCTOU races — balance read then written without a transaction/lock lets two concurrent requests double-spend.

**Escalate** beyond this pass when the diff touches auth flows, session handling, crypto, payments, sandboxing, or file upload handling: use an available dedicated security review when needed or required. If unavailable, complete the applicable checks here and report the limitation; never claim a review ran when it did not.
