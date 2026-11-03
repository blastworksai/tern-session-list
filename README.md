# Interactive plan for Tern

English-first checkpoint visibility for the interactive `$glitch-plan` → execution workflow. The canonical plan contains explicit agreed checkpoints, their current state and a blocked reason. The panel is a read-only native Tern checklist.

This is the Blastworks fork of [Felipe Carneiro's session-list](https://github.com/felipevdc1/tern-session-list), MIT. Interactive adaptation: CodexBWAI, COMMANDER-993. **Preview: not deployed; cross-family review and real-client qualification remain gates.**

## Scope

Interactive sessions only. Fleet/BWPM/FORGE execution is outside the view. The writer/executor updates the one canonical plan; the plugin displays its explicit checkpoint block. It never interprets dated prose as task completion, writes the plan, sends an agent prompt, adopts another task or grants release/deployment authority.

The panel binds to an explicitly selected source and stable `plan_id`. It does **not** follow another terminal's number. Restoring a view preserves that same source/id; replacing a file with a different plan is refused. A failed read clears previous success and shows an error.

## Planning integration

The companion contract in [integrations/glitch-plan-session-view/SKILL.md](integrations/glitch-plan-session-view/SKILL.md) describes how `$glitch-plan` adds the block and how its interactive executor maintains it. Keep normal Build choices, detailed tasks, dated Progress and the sole START HERE. Existing plans gain the block deliberately when resumed/revised; there is no bulk migration or inferred state.

Example (the helper generates a fresh stable plan id):

```sh
session-list template --title "CSV import" --step "Implement the parser" --step "Prove the import" --step "Review and land the change"
```

The command prints a fenced JSON block between `<!-- TERN-SESSION:START -->` and `<!-- TERN-SESSION:END -->`; the agent places it in the canonical plan through its normal write path. States are `pending`, `active`, `blocked`, `done`. At most one is active. `current` names the active/blocked checkpoint, or is null; blocked checkpoints require a reason. Stable ids survive description/reordering changes. The view never edits these fields.

The companion is a source integration asset, **not an installed override of managed Glitch skills**. Live customization/upstream integration needs its own reviewed deployment.

## Local or SSH

Choose **Interactive plan: attach to this tab** in Tern's palette, select the agent's plan location and enter its absolute path:

- **Local:** the file is on the machine running this Tern session's daemon, even when a different desktop displays it. The agent can itself be SSH-launched if that host shares the canonical plan filesystem.
- **SSH:** the plan is on an explicitly reviewed ordinary SSH destination. The read-only reader is sent over SSH stdin to Python 3; no remote package installation or source write occurs. Existing host-key trust and authentication remain required. No key is copied, no host is trusted automatically and no forwarding is enabled. Forced agent-launch aliases (`seat-*`) are refused.

The remote source requires Python 3 and a POSIX shell. Native local reading is portable Python; the Windows command shim uses existing `py` or `python3`. No new package dependency or listening service is added. Authentication errors, unsupported shells, missing Python and invalid checkpoint blocks fail visibly. SSH access never falls back to another source or identity.

Direct source checks (no Tern environment required):

```sh
session-list source --plan /absolute/PLAN.md
session-list source --plan /absolute/PLAN.md --ssh reviewed-host
```

The reader returns only the validated checkpoint object, not whole plan prose, instructions or credentials. Requests have a finite deadline; each panel refreshes independently. There is no seat-wide lock or FORGE lookup. Usage/read errors return 1, never the Stop-hook continuation code 2. No hook is installed or required.

## Runtime and rollout

**Tern 0.9.10 or later is the minimum supported runtime for both the session daemon and viewing client.** Evidence uses 0.9.10. The existing estate daemons observed on 0.9.8 are not qualified; changing a symlink does not update a running daemon. Confirm the actual running binary/client versions and obtain the normal maintenance approval before an update. This fork does not update or restart Tern.

After exact-head cross-family review and owner-approved pilot, install the reviewed local package with Tern's ordinary plugin installer. Plugin ID remains `estate-session-list`; displayed name is **Interactive plan**. Install on the actual session host/client combination; do not run a deployed service/plugin from a group-writable development checkout. See [docs/RUNBOOK.md](docs/RUNBOOK.md).

## Verification

```sh
python3 -m unittest discover -s tests -p estate_test.py
python3 tests/estate_smoke.py --evidence /absolute/private/evidence.json
```

The connected test uses a disposable Tern daemon, private Xvfb window and real loopback SSH server with generated temporary keys and strict host-key checking. It touches no live estate configuration or provider. Source and restored identity, local/SSH state changes, visible failures and independent views are checked. See [docs/VALIDATION.md](docs/VALIDATION.md) for observed results and unqualified platforms; loopback SSH is not proof of a remote Windows/macOS deployment.

Upstream model/test libraries remain as licensed reference. Its old live `tests/cli.sh`, `tests/cli.ps1` and `tests/dev-copy.sh` target a retired request protocol and must not be run for this fork.

## Attribution

Original plugin/native-checklist approach: Felipe Carneiro (`felipevdc1/tern-session-list`), MIT, based on f5920de0cc1018fa9814e5f0c6cca83a7ddf34dc. Original LICENSE remains. English-first view, explicit checkpoint reader, local/SSH source path and workflow contract: CodexBWAI, MIT. This fork does not claim independent origin of the native checklist design. No private estate memory or credentials belong in this public repository.
