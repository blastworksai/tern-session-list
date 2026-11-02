# session-list (Tern plugin)

A list beside each Tern tab of the parts of the work you agreed with your agent, kept by the agent itself and visible to you while it works.
It works with any agent that can run a shell command (Claude Code, Codex, or anything else): the agent notes the parts with `session-list add`, marks the one it is on, ticks each as it finishes, and the panel beside the tab shows the list as it stands.
One list per tab; when a tab closes with parts still open, the next tab is offered that list.
It is not a task manager: it holds only what is still open from the conversation in that tab.

Built after Kristof Kennes asked for a Tern, provider-agnostic version of the Claude Code session list.
Three ideas are taken from oh-my-pi's `todo`: a reminder when the agent stops with parts still open, a "blocked, with a reason" state, and respecting items the person removed by hand.

## Install

```
tern plugin install github.com/felipevdc1/tern-session-list
```

`tern plugin install` clones the repository and copies the package into the plugins folder that `tern plugin dir` prints (on macOS, `~/Library/Application Support/Tern/plugins`).
Then put the `session-list` command on your `PATH`.
The package's folder name inside the plugins folder was not checked for an installed copy: run `ls "$(tern plugin dir)"` to see it.
If it is `session-list`, one line does it:

```
ln -s "$(tern plugin dir)/session-list/bin/session-list" ~/.local/bin/session-list
```

(`~/.local/bin` must be on your `PATH`; use any folder that is.)
On Windows, add the package's `bin` folder to your `PATH`: `bin/session-list.cmd` runs `bin/session-list.ps1` with `pwsh`, or Windows PowerShell when `pwsh` is missing.
Check it with `tern plugin list` (the plugin shows as `session-list 0.1.0`) and `session-list help`.

## Tell your agent

[`agents/INSTRUCTIONS.md`](agents/INSTRUCTIONS.md) has the rule to paste into `AGENTS.md` or `CLAUDE.md` (English and Portuguese), the hooks for Claude Code and Codex, and what to do for agents without hooks.
The rule, in one paragraph:

```
Session list: when you and the person agree on a piece of work in parts, note the parts right away with `session-list add "part 1" "part 2"`, not at the end. Mark the part you are working on with `session-list doing <id>`, and tick each part with `session-list done <id>` as soon as it is done; if a part waits on someone, `session-list block <id> <reason>`. The person can also ask "add this to the session list". This list is NOT the person's task list: never copy their tasks here, and never move items to another task list unless they ask.
```

The hooks add two things: the rule and the list (and any list a closed tab left) are put in front of the agent when a session starts, and the agent is reminded of open parts when it is about to stop.
The SessionStart hook already teaches the rule; the paragraph in `AGENTS.md` is for agents without hooks.

## The panel

When a tab's list gets its first item, a panel opens to the right of that tab, once per list.
If you close it, it stays closed until you run "Session list: show for this tab" from the palette or a new list starts in that tab.
It is drawn with Tern's own todo card, so it follows your Tern theme.

Keys, with the panel focused:

- `↑`/`↓` or `j`/`k`: select an item.
- `space` or `enter`: tick or untick it.
- `d`: mark it as the one in progress (one at a time per list).
- `x` or `backspace`: remove it.
  An item you remove by hand is remembered: the agent cannot add the same text back unless you ask it to (`--again`).

Lists a closed tab left with open items appear on top, with **Continue here** (adopt it into this tab) and **Discard**.
When an item becomes done, the panel shows a short rainbow glow, the same effect Tern uses for a working pane (one turn in 2.4 s; off when your system asks for reduced motion).

Palette commands:

- **Session list: show for this tab** opens the panel beside the focused tab.
- **Session list: language** switches between English and Português (Brasil).

## The command

```
session-list add "<text>"...      add items, one per argument
    --subject <s>                 also name the list
    --again                       re-add a text the person removed by hand
session-list doing <id>           mark the item you are working on (one at a time)
session-list done <id>...         tick items as done
session-list undo <id>...         untick done items
session-list remove <id>...       remove items
session-list name <subject>       name the list
session-list block <id> <reason>  mark an item as waiting on someone
session-list unblock <id>         back to open
session-list show                 show this tab's list and lists closed tabs left
session-list adopt <listId>       take over a list a closed tab left
session-list discard <listId>     discard a list a closed tab left
session-list start                session-start hook: the rule, the list and orphan questions
session-list check                stop hook: reminds of open items
    --hook                        read the hook's JSON on stdin, exit 2 to remind
session-list help                 this screen
```

Every answer is the list as it now stands.
It only works inside a Tern pane (it needs `TERN_PANE`).
Set `SESSION_LIST_NO_ORPHANS` in a pane no person watches to leave the closed-tab lists out of its answers.

Exit codes:

- `0`: done, the list on stdout.
- `1`: an error, on stderr; also when it runs outside a Tern pane, and when the plugin does not answer within 5 s.
- `2`: only `check --hook`, when there is a reminder (on stderr, which Claude Code and Codex feed back to the agent).

An example session (output from the plugin's own parser and list code):

```
$ session-list add --subject "CSV import" "Write the parser" "Add tests" "Update the docs"
This tab's session list: CSV import
☐ i1 Write the parser
☐ i2 Add tests
☐ i3 Update the docs

$ session-list doing i1
This tab's session list: CSV import
▶ i1 Write the parser (in progress)
☐ i2 Add tests
☐ i3 Update the docs

$ session-list done i1
This tab's session list: CSV import
☐ i2 Add tests
☐ i3 Update the docs
☑ i1 Write the parser (done)

$ session-list block i3 "waiting for Ana's review"
This tab's session list: CSV import
☐ i2 Add tests
⊘ i3 Update the docs (blocked: waiting for Ana's review)
☑ i1 Write the parser (done)

$ session-list check
You stopped with 1 open item on this tab's session list: i2 Add tests. Continue with them, or tick what is finished (`session-list done <id>`), or mark what waits on someone (`session-list block <id> <reason>`).
```

## Settings

Settings live in the plugin's `kv.json`, in its data folder (on macOS `~/Library/Application Support/Tern/plugin-data/session-list/kv.json`).
A key that is missing takes its default.

| Key | Default | What it does |
|---|---|---|
| `idioma` | `"en"` | Language of the panel and the answers: `"en"` or `"pt-BR"`. Also set by the palette command. |
| `abrir_sozinho` | `true` | `false` stops the panel from opening by itself; "show for this tab" still opens it. |
| `max_lembretes` | `1` | How many stop reminders a list gets before it changes again. |

## How it works

- **One writer.** Only the plugin's host half (inside Tern's daemon) reads and writes the lists, one JSON file per list in `listas/` under the data folder.
- **Request files.** The command never touches a list: it writes a request into `pedidos/` (as a `.tmp` file, then renamed), and the host answers into `respostas/`.
  A request counts only when its last line is `end=1`, so a half-written one is left for the next pass.
  The host deletes the request before applying it, so a request is never applied twice; a crash in between loses that one request, and the command says the plugin did not answer.
- **Where the command finds the data folder.** `SESSION_LIST_DATA` (set by the plugin in every new Tern pane), else `$TERN_CONFIG_DIR/plugin-data/session-list`, else the OS default.
- **Orphans.** When a tab closes, its list becomes an orphan if it still has parts not done, and is deleted if everything was done.
  Closed tabs are found by checking, every second, which panes still exist.
  An orphan is offered to the next tab: in the panel (Continue here / Discard) and, through the start hook, to the agent, which is told to ask you and never to adopt or discard on its own.
  Adopting moves the list into this tab, or appends its open parts (with new ids) when this tab already has a list; a discarded list is moved to `descartadas/`, not deleted (move it back into `listas/` by hand to undo).
- **Reminders.** `check` reminds of open and in-progress parts (blocked ones do not count).
  It reminds at most `max_lembretes` times until the list changes, never when the agent's last reply ends with a question, and never on a turn the stop hook already continued (`stop_hook_active`), so it cannot loop.
  For Tern agent blocks the plugin sends the reminder itself when the agent finishes and is idle.
- **Torn writes.** Lists are written whole and synchronously; a crash in the middle of a write would leave an unreadable file, which is then shown as unreadable and never touched again.

## Verified / Not verified

Verified, on Tern 0.9.8 on macOS: the command and every verb against the real Tern daemon with a test copy of the plugin (orphans, adopt, discard, the reminder cap, `stop_hook_active`); the panel's look, keys and glow; and a real Claude Code run whose Stop hook held it once with the reminder and did not loop.

Not verified:

- **Windows.** The PowerShell command and the `.cmd` shim are written and pass the same test as the sh command under `pwsh` on macOS, but were never run on Windows.
  Whether Tern sets `TERN_PANE` on Windows, and the default data folder there (`%APPDATA%\Tern\plugin-data\session-list`), are unverified.
- **Linux.** The default data folder there is a guess; `SESSION_LIST_DATA` set by the plugin does not depend on it.
- **Tern agent blocks.** The reminder for agent blocks loads without error but was not run with a real agent block.
- **Codex.** The Codex hooks follow Codex's documentation and were not run.
- **`tern restart`.** Not measured; lists and panels are expected to come back because the programs keep running.
- **Quit or reboot.** If Tern recreates panes with reused ids before the plugin loads, a new tab could inherit a dead tab's list.

## Removing it

```
tern plugin remove session-list
rm ~/.local/bin/session-list
```

Your lists stay in the data folder until you delete it (on macOS `~/Library/Application Support/Tern/plugin-data/session-list/`).

## Credits

Made by Felipe Carneiro: GitHub [felipevdc1](https://github.com/felipevdc1) · Instagram [@o.felipecarneiro](https://instagram.com/o.felipecarneiro).

MIT license.
