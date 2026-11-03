# Validation — COMMANDER-993

CodexBWAI, 3 November 2026. Runtime: installed Tern 0.9.10 (`2ad447b`), Linux, Python standard library. All plugin execution used private disposable config/data and a private Xvfb display; no ordinary estate daemon, window, agent hook or service was changed.

- **3 helper contract tests passed.** Executable helper reads real PLAN files, reflects canonical edits without changing source, refuses rebinding, refuses shared/symlinked storage, invalidates old success after a source failure, and requires a new binding for a changed epoch.
- **127 retained/extended Luau library tests passed**, inside Tern's actual Luau VM. This includes the added read-only card contract. The smoke harness appends a test-only require to its private host copy; production host code does not load tests.
- **7 connected checks passed:** real plugin loads ready; PLAN renders pending in the native checklist; canonical edit/refresh renders done; repeated palette show keeps one panel; bad source replaces old success with a blocked error; two native panes retain independent bindings/epochs; deployed FORGE `get` supplies the matching custom ticket reference.
- Test processes were stopped and reaped. Tests use unique `/var/tmp` roots and clean only their own files/processes.

The first connected test failed because its text assertion expected only the row title; Tern concatenates the blocked reason into accessible row text. Direct inspection showed the correct blocked error. The assertion now checks the title prefix and blocked state, preserving the actual contract. The pending-card and duplicate-panel issues found during the interactive smoke were fixed before the passing connected run.

Not qualified by this evidence: remote Windows/macOS frontend presentation, lifecycle hooks for each native agent, daemon restart and remote disconnect/reconnect, production installation, cross-family code review. A helper/virtual-display pass does not waive those rollout gates. No provider model was invoked by the test; live FORGE access was read-only.

Reproduce from the reviewed branch:

```sh
python3 -m unittest discover -s tests -p estate_test.py
python3 tests/estate_smoke.py --forge COMMANDER-993 --evidence /absolute/private/evidence.json
```

The evidence contains checks, runtime source hashes and cleanup status. It does not store ticket instructions/comments, credentials or private plan contents. The `--forge` flag is optional; without it both panes use disposable PLANs.
