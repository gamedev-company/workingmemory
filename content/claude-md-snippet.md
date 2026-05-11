<!-- working-memory-kit:begin version=0.1.0 -->
## Documentation Discipline

**Non-negotiable.** The `working-memory/` vault is the agent's external cognitive prosthetic across sessions — the durable substrate of decisions, design, and architectural memory. Authoritative conventions: [`working-memory/System.md`](working-memory/System.md).

Tiers: `core/` (elevator-pitch facts) · `ref/` (subsystem briefings) · `schema/` (data shapes) · `senses/` (the agent's own observations + feature ideas + friction notes) · `design/` (proposals) · `plan/` (execution playbooks) · `complications/` (Q&A docs that complicate ideas before code) · `journals/` (per-day, per-turn record) · `short-term.md` (rolling session-boot brief, capped ~300 lines).

### Session lifecycle

- **At session start**: read `working-memory/short-term.md` first. Then `Index.md` if you need orientation.
- **Per turn**: append a What/Why summary (and any `★ Insight` blocks) to today's `working-memory/journals/YYYY-MM-DD.md`. Per-turn cadence — that's where the churn happens.
- **Before code on a non-trivial idea**: open or extend `working-memory/complications/<topic>.md`. Each open question gets a yes-and proposed answer; resolved questions move to `## Resolved` in-place.
- **Before touching a subsystem**: check `working-memory/ref/`. Before architecting: check `design/` and `core/`.
- **When friction or feature ideas surface**: write to `working-memory/senses/`.
- **At session end / context budget threshold**: refresh `working-memory/short-term.md` so the next session bootstraps efficiently. Anything durable beyond that has already moved to a long-term tier.

### When insights emerge

If a design observation, architectural decision, or non-obvious realization surfaces during conversation — whether from the user or from analysis — it should be captured. Default capture point: today's journal entry. Promote to a long-term tier (design / ref / sense / core) when it's durable enough to stand alone. Design thinking that only lives in chat is lost thinking.
<!-- working-memory-kit:end -->
