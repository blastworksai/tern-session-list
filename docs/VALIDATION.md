# Interactive redesign validation — COMMANDER-993

CodexBWAI, 3 November 2026. This supersedes ff70e18's PLAN/FORGE implementation evidence. Source runtime: Tern 0.9.10 (`2ad447b`), Linux, existing Python/OpenSSH/Xvfb. No package, provider or live estate configuration was installed or changed.

**Helper contracts: 3 passed.** Actual executable source reader preserves the canonical file, accepts an explicit block inside normal dated Progress/START HERE prose with no Tern environment, rejects invalid checkpoint state and malformed arguments with exit 1, and preserves an SSH path with spaces through the quoted remote command/reader payload. Forced `seat-*` launch destinations are refused.

**Connected native-runtime checks: 10 passed.** A private Tern daemon/plugin and private Xvfb window exercised initial native local pending and done rows, automatic source refresh, duplicate-panel prevention, a different plan id replacing the selected path, saved/restored identity, error invalidation, a real key-authenticated loopback SSH source, its subsequent state change and independent simultaneous local/SSH views.

**Visual limit:** the initial local pending/done rows were observed in Tern's real accessibility tree. Tern's closed-beta sign-in overlay then hid the client UI. The remaining connected checks observe actual host callback state using test-only instrumentation appended to the private host copy. Those are source/identity/runtime-state proofs, **not** remote or restored visual passes. No sign-in gate was bypassed. An authenticated real Windows/macOS client pilot remains required.

The first long visual attempt timed out under that overlay. The revised harness records the limit and checks native host state after the gate rather than repeatedly retrying an unavailable view. The first attachment test also waited for the native window to publish its fixture pane before invoking the plugin action; readiness is checked, not assumed. The second SSH tab receives the same publication/readiness check before attachment; a measured absent panel exposed that test ordering race.

**SSH fixture:** a real unprivileged loopback sshd and real OpenSSH client use temporary generated keys, strict key authentication, strict host-key checking, no password/forwarding and a safe private cache root. The earlier `/var/tmp` key fixture was correctly refused by sshd StrictModes; moving only this owned fixture under the account's private cache resolved it. No live `authorized_keys`, SSH config, host trust, service or credential was changed. All fixture keys, files and owned processes are removed/reaped.

The Luau run passed 129 tests: 127 retained upstream library checks plus two active-view contracts. The new contracts prove that a current blocked checkpoint remains explicitly labelled and that a failed source cannot draw prior success. The current-label test first failed, then passed after the renderer used the explicit current id. Retained library coverage is not counted as proof of the new local/SSH workflow. Current source hashes and process cleanup status are in the connected evidence.

Not yet qualified: actual managed `$glitch-plan`/executor adoption, authenticated Windows/macOS visuals, real multi-machine/remote-shell combinations, full daemon restart/reconnect on those clients, exact-head cross-family pass or live rollout. The actual estate daemons observed on 0.9.8 have not been updated or qualified.

```sh
python3 -m unittest discover -s tests -p estate_test.py
python3 tests/estate_smoke.py --evidence /absolute/private/evidence.json
```

The harness uses owned disposable configuration and display/SSH processes; it never targets the ordinary estate daemon. The evidence records runtime/source hashes and explicit visual limitations, not credentials or private plan prose.
