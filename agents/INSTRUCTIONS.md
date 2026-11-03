# Estate agent integration — CodexBWAI, COMMANDER-993

The session panel is a read-only view of the PLAN or FORGE work explicitly assigned to this native Tern pane. It is not a work assignment, a dispatch channel or an approval. Keep all existing owners, gates and START HERE rules.

When the operator/orchestrator supplies the exact WORK-ID and canonical source, bind that source with `session-list bind --work-id <WORK-ID> --plan <absolute-plan>` or `--forge <CUSTOM-REF>...`. Never guess a source from session-start notes, find another pane's work, adopt an orphan or rewrite environment variables to appear inside Tern. After updating the canonical work record through its normal approved path, run `session-list refresh`. The command never updates PLAN/FORGE itself.

`session-list start` refreshes and prints this binding only, with source text framed as untrusted data. `session-list check --hook` refreshes silently and returns 0 on success, 1 on failure. It never returns the Stop continuation status 2 and does not read hook stdin. Do not copy upstream automatic-continuation hooks.

Fleet hook wiring remains governed by the estate hook registry. This repository supplies no auto-installer and does not edit any agent's configuration. Lifecycle integration needs its own reviewed registry change and release gate. Agents without hooks can run the same command after canonical checkpoint updates. Outside native Tern panes the command refuses cleanly.
