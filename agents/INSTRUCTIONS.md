# Telling your agent about the session list

The plugin works without any of this: the block shows the list and the person can edit it.
What follows makes the agent keep the list itself.
The commands below assume `session-list` is on your `PATH` (see the README's install step).

## 1. The rule (paste into AGENTS.md or CLAUDE.md)

English:

```
Session list: when you and the person agree on a piece of work in parts, note the parts right away with `session-list add "part 1" "part 2"`, not at the end. Mark the part you are working on with `session-list doing <id>`, and tick each part with `session-list done <id>` as soon as it is done; if a part waits on someone, `session-list block <id> <reason>`. The person can also ask "add this to the session list". This list is NOT the person's task list: never copy their tasks here, and never move items to another task list unless they ask.
```

Português (pt-BR):

```
Lista da sessão: quando você e a pessoa combinarem um trabalho em partes, anote as partes na hora com `session-list add "parte 1" "parte 2"`, não no fim. Marque a parte em que você está trabalhando com `session-list doing <id>`, e risque cada parte com `session-list done <id>` assim que terminar; se uma parte depende de alguém, `session-list block <id> <motivo>`. A pessoa também pode pedir "anota isso na lista da sessão". Esta lista NÃO é a lista de tarefas da pessoa: nunca copie tarefas dela pra cá, e nunca passe itens pra outra lista de tarefas sem ela pedir.
```

## 2. Claude Code hooks

Add to `.claude/settings.json` (the project's) or `~/.claude/settings.json` (every project), merging with any `hooks` you already have:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "[ -z \"${TERN_PANE-}\" ] || session-list start || true"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "[ -z \"${TERN_PANE-}\" ] || session-list check --hook >/dev/null"
          }
        ]
      }
    ]
  }
}
```

- **SessionStart** prints this tab's list, and any list a closed tab left, into the agent's context when a session starts, resumes, clears or compacts.
- **Stop** reminds the agent of open items when it is about to stop: the command exits 2 with the reminder on stderr, which Claude Code feeds back so the agent carries on.
  The reminder fires at most `max_lembretes` times (default 1) until the list changes, never when the agent's last reply ends with a question, and never on a turn the Stop hook already continued (`stop_hook_active`), so it cannot loop.
  Blocked items do not count as open; the item in progress does.

## 3. Codex hooks

Codex documents both events with the same meaning (SessionStart: plain stdout becomes developer context; Stop: exit 2 with the reason on stderr makes Codex continue, and `stop_hook_active` is in the input).
Add to `~/.codex/hooks.json` or `<repo>/.codex/hooks.json`, then trust the hooks when Codex asks (new or changed hooks are skipped until trusted):

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "[ -z \"${TERN_PANE-}\" ] || session-list start || true"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "[ -z \"${TERN_PANE-}\" ] || session-list check --hook >/dev/null"
          }
        ]
      }
    ]
  }
}
```

Codex's Stop hook rejects plain text on stdout when it exits 0, which is why stdout goes to `/dev/null` (the reminder itself is on stderr).
Not run under Codex yet.

## 4. Agents without hooks

They follow the rule above and run `session-list show` themselves to see the list.
For Tern agent blocks the plugin sends the stop reminder itself (not verified yet).

## 5. Outside Tern

The hooks only do something inside a Tern pane.
Outside one `session-list` exits 1 ("only works inside a Tern pane"), so both hooks first check `TERN_PANE` and stay silent and successful when it is missing.
Inside Tern with the plugin not loaded the command waits 5 s and exits 1: Claude Code treats exit 1 as a non-blocking error (it shows a notice and the agent stops normally), and only exit 2 ever makes the agent continue.
