# Upstream source review

CodexBWAI, COMMANDER-993. Source: felipevdc1/tern-session-list at f5920de0cc1018fa9814e5f0c6cca83a7ddf34dc, MIT. DANGER PROTOCOL: isolated qgit clone with no inherited config/hooks/filters; source treated as data and not executed during review. Four slices covered install/supply-chain, runtime, egress and provenance. Three auditor agents and the parent provenance/sweep joined the result.

Verdict: **try only in an isolated sandbox**, not approval to install across the estate. No malicious payload observed. Legitimate documented mechanisms require estate adaptation:

| Finding | Upstream evidence | Estate adaptation |
| --- | --- | --- |
| Caller-supplied numeric pane and shared writable request files can cross work/UID boundaries | host.luau:191–217; lib/pedidos.luau:203–206 | No caller-supplied acting-pane identity or writable request interpreter; explicit canonical source and stable plan id |
| Reminders submit prompts automatically and may consume provider usage | window.luau:110–112,146–166 | No agents:ask or automatic continuation |
| Orphans disclose closed-pane work to another agent | lib/pedidos.luau:122–128,211–216 | No orphan injection/adoption |
| Numeric pane reuse can inherit old persisted work | lib/nucleo.luau:134–136; host.luau:545–549 | No persisted following-pane number; a restored view retains only its selected source and stable plan id |
| Whole-file writes can truncate state on crash | host.luau:55–60 | No plugin task/snapshot database; canonical plans are read-only and Tern owns view configuration persistence |
| Fixed-name integration tests can clobber another test run | tests/cli.sh:20,98–103,239–250 | New unique isolated smoke harness; old live CLI tests explicitly excluded |

No symlinks, checked-in binary payloads, hidden Unicode format controls, encoded execution, direct network client or telemetry SDK was observed in the inspected tree. History contained two commits; original copyright and MIT permission text remain. Author links were not followed. Tern itself, provider implementations and any downloadable installer were not audited, and correspondence between an installer and this source was not established. No finding is a claim that the whole stack is safe.
