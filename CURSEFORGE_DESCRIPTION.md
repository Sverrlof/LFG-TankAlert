Never miss a tank again. **LFG TankAlert** watches your posted Premade Group
listing in the background and reacts the instant someone applies: a screen
flash, a sound, and a one-click Invite/Decline popup. Alt-tab out or go AFK
instead of babysitting the Group Finder window.

## Features

- **Tank alerts** — screen flash (pick your own color), sound, chat message,
  and an Invite/Decline popup the moment a tank applies to your group
- **Ignore rule** — mute the alert for tanks below a minimum item level or
  Mythic+ score (either one triggers it), so undergeared applicants you'd
  decline anyway don't interrupt you
- **Optional Raider.IO integration** — if you also run that addon, the popup
  shows the applicant's current M+ score, previous-season score, and their
  best key overall and for the specific dungeon you're recruiting for
  (shown as dungeon + level + chest rating, e.g. `++18 Mechagon`)
- **Full settings window** (`/ta options`) — flash color/duration, a sound
  dropdown with a Preview button, repeat count/interval, and the ignore
  rule's thresholds, all with live updates

## How it works

A tank **applies** to the group you posted in Premade Groups. This addon hooks
into that applicant system directly, so it keeps working even with the
Group Finder window fully closed.

1. Post your group as usual.
2. Open `/ta options` once to set up your alert style and (optionally) an
   ignore threshold.
3. When a tank applies, you get the flash/sound/popup. Click **Invite**,
   **Decline**, or **Dismiss** right from the popup.

## Slash commands

`/tankalert` or `/ta`, followed by:

| Command | Effect |
|---|---|
| `options` | Open the settings window |
| `test` | Fire a test alert to preview your setup |
| `status` | Show your active listing / pending tank count |
| `debug` | Dump raw applicant + Raider.IO data (troubleshooting) |
| `sound raidwarning\|readycheck\|none` | Quick sound switch |
| `flash on\|off` | Toggle the screen flash |
| `popup on\|off` | Toggle the Invite/Decline popup |
| `chat on\|off` | Toggle chat announcements |

---

Feedback and bug reports welcome. `/ta debug` output is the fastest way to
get an issue fixed if something doesn't work on your setup.
