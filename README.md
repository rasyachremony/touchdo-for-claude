<p align="center"><img src="assets/logo.png" width="128" alt="TouchDo logo"></p>

<h1 align="center">TouchDo for Claude</h1>

<p align="center">Your Claude limits, running Claude Code sessions and to-dos, right on the Touch Bar.<br>
<a href="README.id.md">Bahasa Indonesia</a></p>

![TouchDo on a real Touch Bar](assets/touchbar.png)

No more switching windows to see how much of your Claude plan is left. It's just there, next to your to-dos.

## What you get

- **Your limits**: 5-hour and weekly use, with reset times. Green, yellow from 50%, red from 80%.
- **Your sessions**: the Claude Code sessions working right now, and for how long. One that's waiting for your
  permission or answer turns **yellow** and moves to the front.
- **To-dos**: add, tick and set deadlines from the Touch Bar or the menu bar.
- **Paper plane**: sends a to-do to a new Claude Code session (experimental).
- **Mic**: hold to talk to Claude, double tap to keep it on.
- **☕**: keeps your Mac awake. Uses [Insomnia](https://github.com/krishhgg/Insomnia) if you have it.

Start typing and it gets out of the way, so you still get typing suggestions. A second after you stop, it's back.
The buttons are in Indonesian.

## Install

You need a MacBook Pro with a Touch Bar **and a real Esc key** (16-inch 2019, or 13-inch 2020 and later) and the Xcode
command line tools (`xcode-select --install`).

```bash
git clone https://github.com/rasyachremony/touchdo-for-claude.git
cd touchdo-for-claude
./build.sh
```

Then:

1. **System Settings → Privacy & Security → Accessibility**: turn on **TouchDo**. It needs this to know when you're typing.
2. **System Settings → Keyboard → Touch Bar Settings**: pick **App Controls** and turn on **Show Control Strip**.
3. For the mic, set Claude's dictation shortcut to **⌃⌥⌘D**.

That's it. It starts by itself every time you log in.

**Optional:** paste [statusline-usage.sh](statusline-usage.sh) into your
[Claude Code status line script](https://code.claude.com/docs/en/statusline) so the limits update after every reply.

## Things you should know

- **It uses a bit of your plan.** If the limits haven't updated in five minutes, TouchDo asks Claude Code with one tiny
  Haiku request (about 1,100 tokens). That can add up over a day, and it can start a new 5-hour window. The optional
  step above makes it run much less. To turn it off, set `autoRefresh` in `main.swift` to `.infinity` and run
  `./build.sh` again.
- **The paper plane starts a real session**, in whatever folder and permission mode Claude has selected, with any files
  still attached there. If it can't confirm the send, it beeps and leaves the text for you.
- **Your data stays on your Mac.** Apart from that tiny request, TouchDo sends nothing anywhere. It reads Claude Code's
  own files for your sessions and plan, and only reads what you type while you're typing a to-do.
- **The build is signed ad hoc**, so Accessibility is tied to the app's id. Another app signed with the same id would get
  it too. To avoid that, sign with your own certificate and drop the `-r=...` part of the `codesign` line in `build.sh`.
- **It uses private Apple APIs**, so a macOS update can break it. Tested on macOS 27.
- **Not made by Anthropic.** "Claude" is their trademark.

## Problems?

- **Nothing on the left:** check the Accessibility switch. If it's on, remove TouchDo with **−** and add it again.
- **Limits show "–":** sign in to Claude Code and wait five minutes.
- **Mic does nothing:** open Claude, wait a few seconds, and check the shortcut.

## Uninstall

```bash
./build.sh uninstall
```

Your to-dos stay. Remove TouchDo from the Accessibility list too.
