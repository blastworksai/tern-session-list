# Estate session view for Tern

A native checklist beside a Tern pane, reading that pane's explicitly assigned PLAN or FORGE tickets. This is the Blastworks estate fork of [Felipe Carneiro's session-list](https://github.com/felipevdc1/tern-session-list), MIT, based on `f5920de0cc1018fa9814e5f0c6cca83a7ddf34dc`. Estate adaptation: CodexBWAI, COMMANDER-993.

**Development preview. Not installed on estate seats. Independent review and live remote/Windows qualification remain release gates.**

## Behaviour

- One explicit WORK-ID and canonical source per pane. Different work requires a fresh pane.
- PLAN/FORGE remain authoritative. No checklist edits, ticket transitions, work adoption, dispatch, provider calls or automatic agent continuation.
- Every Unix seat has its own plugin, daemon and private data. No shared writable cross-user directory or central agent-prompt relay.
- The command reads the source and atomically publishes a snapshot. Source failures replace old success with a visible error. The panel shows when it last read the source; it does not imply continuous live synchronization.
- A fresh epoch per plugin load and pane spawn prevents recycled pane numbers from inheriting work. After plugin reload/restart, open a fresh pane and explicitly bind the same authorized work. Existing approvals remain in the canonical record.
- No orphaned work is offered or injected into another agent's context. Snapshot text is source data, never an instruction or assignment.

AGP and OMP are outside this integration. The helper runs on the estate's **Linux native Tern host**, regardless of the CLI family inside the pane. A Windows/macOS Tern frontend need not run Python, but its remote panel path still needs qualification. Shells multiplexed inside Herdr or plain SSH without their own native `TERN_PANE` are refused; never invent or forward a pane number to make them pass.

## Requirements

Existing Tern with Luau plugins, Python 3.10+ standard library, Linux (`fcntl`, `O_NOFOLLOW`, GNU `readlink`), and the deployed `/usr/local/lib/blastworks/forge` for FORGE views. No package installation, listening service, token or new dependency.

PLAN sources need exactly one `## Progress` section with Markdown checkboxes and one `## START HERE`. Fenced examples are ignored. Unsupported plans fail explicitly; they are not guessed or rewritten. Only checked items become done. FORGE views show each ticket's actual state: DEPLOYED/REJECTED are closed, IN PROGRESS is active, IDEA/CREATED/ELIGIBLE are pending, remaining review/hold/release states are blocked. COMMITTED never means deployed.

## Install a reviewed revision (deployment gate)

Do this only after independent review and owner deployment approval, under the target Unix seat. Do not run a service from a group-writable checkout. Copy the reviewed plugin to a private, seat-owned release folder, then install from that local directory:

```sh
/usr/local/lib/tern/current/tern plugin install /absolute/private/reviewed-release
```

Plugin ID: `estate-session-list` (coexists with upstream `session-list`). Before opening a fresh pane, verify its plugin-data directory and ancestors are private to this seat: root must have mode 0700, owned by the acting UID, no symlink components or group/world-writable non-sticky ancestors. The helper refuses unsafe storage; it does not chmod or repair another seat's files. `SESSION_LIST_DATA` and `SESSION_LIST_EPOCH` are injected by the plugin into new panes. Do not set them by hand in a live pane.

Invoke the command by the installed package's absolute path or a PATH symlink. In that pane:

```sh
session-list bind --work-id WORK-123 --plan /absolute/canonical/PLAN.md
# OR
session-list bind --work-id WORK-123 --forge COMMANDER-993
session-list refresh
session-list show
```

Update the canonical record through its normal approved path, then run `refresh`. `show`, `start` and `check` also re-read the source. `check --hook` is silent on success and **never exits 2**: incomplete work is not permission to restart an agent. A missing binding is an explicit error; it never searches for or takes another pane's assignment. The panel automatically opens once for each bound pane; closing it leaves it closed, with a palette command to show it again.

## Tests and observed limits

Run the focused boundary suite (no live Tern touched):

```sh
python3 -m unittest discover -s tests -p estate_test.py
```

Tests exercise the executable helper with real PLAN files: canonical refresh/rebinding refusal; unsafe store/symlink refusal; source-failure invalidation/epoch separation. `tests/estate_smoke.py` runs an isolated real Tern daemon, binds a disposable PLAN, edits and refreshes it, and reads a real FORGE ticket. It never touches the target seat's ordinary daemon/config, windows or hooks.

Upstream `tests/*_test.luau` remain tests of the retained upstream libraries. Upstream `tests/cli.sh`, `tests/cli.ps1`, and `tests/dev-copy.sh` target the old request protocol and **must not be used for this fork** (they use fixed test plugin names and mutate installations). The original Windows command entry points now refuse with an explicit explanation.

Qualification still owed: real Windows/macOS client rendering from remote Unix seats, native CLI lifecycle hooks and host restart/reconnect. A loaded plugin and passing helper tests do not prove these outcomes. See `docs/VALIDATION.md` and `docs/RUNBOOK.md`.

## Attribution

The native checklist renderer, theme assets and retained model/test libraries originate with Felipe Carneiro, `felipevdc1/tern-session-list`, MIT. Original copyright/permission text remains in LICENSE. Upstream credits oh-my-pi's todo for reminder, blocked-state and human-removal ideas; the estate runtime does not use its automatic reminder mechanism. New Python adapter and replacement host/window integration: CodexBWAI, MIT. No private estate memory, credentials or plan contents belong in this public repository.
