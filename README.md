# TouchDo for Claude

Your Claude limits, running Claude Code sessions and a to-do list, live on the MacBook Pro Touch Bar.

**[Bahasa Indonesia](README.id.md)**

```
 ✳ Max   5h   ███░░░░░░░  30% ↻04:10      ● Fix the login bug  24m
   5x    Week ██░░░░░░░░  17% ↻Sat 13:00  ● Write the tests     3m      ‹ ☑² ☕ 🎙  ☀ 🔊
```

> Unofficial. Not made by, affiliated with or endorsed by Anthropic. "Claude" is their trademark. The logo on the bar
> is the icon of the Claude app installed on your Mac; none of it ships with this project.

## What it does

- **Claude limits at the far left.** 5-hour and weekly use as bars, with reset times. Green, yellow from 50%, red from 80%.
- **Your plan** (Pro, Max 5x…) and the **Claude Code sessions working right now**, with how long they have been at it.
- **Out of the way while you type.** Any key (except ⌘ and ⌃ shortcuts) brings back the app's own Touch Bar and typing suggestions; a second after
  you stop, the limits return.
- **To-dos with deadlines.** Add, edit, tick and delete them on the Touch Bar or from the menu bar. The colour shows how
  close the deadline is, the red badge how many are open.
- **Send a to-do to Claude Code** with the paper plane *(experimental, see below)*.
- **Hold the mic to talk to Claude**, or double tap to keep dictating until the next tap.
- **☕ Keep awake**, by itself or through [Insomnia](https://github.com/krishhgg/Insomnia) 0.2.0 or later, which also works with the lid closed.

The buttons and menus are in Indonesian.

## Requirements

- A MacBook Pro with a Touch Bar **and a physical Esc key** (16-inch 2019, 13-inch 2020 or later), macOS 13 or later. Only
  tested on macOS 27.0.1. On models whose Esc is on the Touch Bar (2016–2019), the limits bar covers Esc, so they are not
  supported.
- Xcode command line tools: `xcode-select --install`
- [Claude Code](https://claude.com/claude-code) for the limits and sessions, and the Claude desktop app for voice and the
  paper plane. The to-dos and ☕ need neither.

## Install

1. Get the code and build it. This installs `~/Applications/TouchDo.app` and starts it at every login.

   ```bash
   git clone https://github.com/rasyachremony/touchdo-for-claude.git
   cd touchdo-for-claude
   ./build.sh
   ```

2. Give it Accessibility: **System Settings → Privacy & Security → Accessibility**, then turn on **TouchDo**.
   If it isn't listed, press **+** and choose `TouchDo.app` from the Applications folder in your home folder. Until then
   the limits stay hidden, because TouchDo can't tell whether you are typing.

3. In **System Settings → Keyboard → Touch Bar Settings**, set "Touch Bar shows" to **App Controls** and turn on
   **Show Control Strip**.

4. Voice only: in the Claude app's settings, set the Quick Entry dictation shortcut to **⌃⌥⌘D**, or change
   `pressClaudeShortcut` in `main.swift` to yours and run `./build.sh` again.

5. Optional: bars that follow every Claude Code reply. Paste [statusline-usage.sh](statusline-usage.sh) into your
   [status line script](https://code.claude.com/docs/en/statusline).

## How to use it

| Do this | To |
|---|---|
| Tap the ☑ ☕ 🎙 button in the Control Strip | open TouchDo |
| Tap **+**, type, press Return, pick a date | add a to-do (Esc cancels) |
| Tap a to-do | run it in Claude Code, tick, edit, date or delete it |
| Hold 🎙 / double tap 🎙 | talk while held / keep dictating until the next tap |
| Tap ☕, pick a time | keep the Mac awake |
| Click the checklist in the menu bar | see limits, add or edit to-dos with the mouse |

While you type a to-do, the usual editing keys work: ⌘A, ⌘C, ⌘X, ⌘V, ⌘Z, ⌥⌫, ⌘⌫, ⇧ with the arrows, ⌃A, ⌃E, ⌃K.

### The paper plane (experimental)

It opens a new Claude Code session with the to-do filled in, then presses Return once, and only if that exact text is in
the new-session box with Claude in front. **The session starts with the folder and permission mode selected in Claude**,
and with any files you left attached there. If the last word contains an `@` or starts with `/`, the text is filled
in but not sent. If something doesn't match or the send can't be confirmed, TouchDo beeps; check Claude before sending it
yourself.

## What it reads and what it costs

Nothing is sent anywhere by TouchDo itself. It reads:

- `~/.claude/sessions/*.json` for the running sessions, and `~/.claude.json`, of which only the plan fields are decoded.
- Key presses: while idle only *that* a key was pressed (and whether ⌘ or ⌃ was held), to step aside. The keys themselves are read only while you type
  a to-do, and not in password fields.
- Claude's window, through Accessibility, only after you tap the paper plane.
- If Insomnia is running: its version, and `session.json` and `config.json` in `~/Library/Application Support/Insomnia`.
- The clipboard, only when you press ⌘V while typing a to-do.

When you are signed in with a Claude plan and the limits are five minutes old, it runs one tiny `claude -p` request (Haiku,
no tools, not saved), and again every five minutes until something else updates them. **That uses about 1,100 input tokens
of your plan each time**, so up to 288 times (about 320,000 tokens) a day on a Mac that stays awake, and it can start a new
5-hour window while you are not using Claude. Only install step 5 lets your own sessions update the limits, so without it
this also runs while you use Claude Code. To switch it off, set `autoRefresh` in `main.swift` to `.infinity` and run
`./build.sh` again; the bars then need step 5.

Your to-dos stay in `~/Library/Application Support/io.github.rasyachremony.TouchDo/todos.json`.

## Good to know

- It uses Apple's private Touch Bar API, so a macOS update can break it. If the API is gone, TouchDo quits quietly.
- The session, plan and limit files are Claude Code's own, not a documented API. If they change, those parts go empty.
- The build is signed ad hoc, and the Accessibility permission is tied to the bundle id so it survives rebuilds. Another
  program on your Mac signed with the same id would get that permission too. If that matters to you, edit the `codesign`
  line in `build.sh`: replace `--sign -` with `--sign "Your Certificate"` and delete the whole `-r=...` argument, which would
  keep the permission tied to the id alone. Rebuild, then remove TouchDo from the Accessibility list and add it again.

## Troubleshooting

| Problem | Fix |
|---|---|
| No bars at the far left | Check step 2. If TouchDo is already on there, remove it with **−** and add it again. |
| Bars show "–" | Sign in to Claude Code (an API key has no plan limits). TouchDo looks for `claude` in `~/.local/bin`, `~/.claude/local`, `/opt/homebrew/bin` and `/usr/local/bin`; if `which claude` says it is elsewhere, run `mkdir -p ~/.local/bin && ln -s "$(which claude)" ~/.local/bin/claude`, or do step 5. Then wait up to five minutes. |
| Mic does nothing | Open Claude, wait five seconds, and check the shortcut in step 4. |
| Mic works the wrong way round | The shortcut is a toggle. Stop dictation with TouchDo's mic, not in Claude, and stop it before rebuilding or uninstalling. |
| The button is missing from the Control Strip | `launchctl kickstart -k gui/$(id -u)/io.github.rasyachremony.TouchDo` |

## Uninstall

```bash
./build.sh uninstall
```

Your to-dos are kept. Also remove TouchDo from the Accessibility list, and the `statusline-usage.sh` lines from your status
line script if you added them.

## Development

`main.swift` is the app; `Draft`, `ClaudeChat`, `Sessions` and `Plan` are the parts with a self-check:

```bash
./test.sh
```
