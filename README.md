# LFG TankAlert

A World of Warcraft addon for M+/raid group leaders. It watches your active
**Premade Groups** listing in the background and reacts the instant someone
applies — no need to keep the Group Finder window open.

## Features

- **Tank alerts** — screen flash, sound, chat message, and an Invite/Decline
  popup the moment a tank applies.
- **Settings window** (`/ta options`) with two tabs to customize everything.
- **Ignore rule** — mute the alert entirely for tanks below a minimum item
  level or Mythic+ score (either one, your choice), so you're not
  interrupted for undergeared applicants you'd decline anyway.
- **Optional Raider.IO integration** — shows extra applicant stats in the
  popup if you also run that addon. See below.

## Install

1. Copy the `TankAlert` folder into your WoW AddOns directory:
   `World of Warcraft\_retail_\Interface\AddOns\TankAlert`
   (so you end up with `...\AddOns\TankAlert\TankAlert.toc`)
2. Restart WoW (or `/reload`) and make sure "LFG TankAlert" is checked in
   the AddOns list on the character-select screen (the folder is still
   named `TankAlert` — only the display name shown in-game changed).

If it shows up greyed out as "out of date": either turn on **Options ->
AddOns -> Load out of date AddOns**, or run `/dump select(4, GetBuildInfo())`
in-game and tell me the number so I can fix the `## Interface:` line exactly.

## Usage

1. Post your group as usual in Premade Groups (M+ or raid), then alt-tab out
   or go AFK — LFG TankAlert is watching.
2. Open **`/ta options`** to configure alerts and the ignore rule.
3. When a tank applies (and isn't ignored), you get the flash + sound +
   popup. Hit **Invite** right from the popup, or **Decline**, or **Dismiss**
   to just clear the popup without acting.

### Settings window (`/ta options` or `/ta config`)

**Alerts tab**
- Enable/disable the screen flash, and pick its color (click the swatch)
- Flash duration
- Alert sound: a dropdown with Raid Warning, Ready Check, 3 alarm clocks, or
  None — plus a **Preview** button to hear the selected one on demand
- How many times the sound repeats, and the interval between repeats
- Toggle chat announcements, the Invite/Decline popup, Raider.IO info, and
  whether alerts require you to currently be able to invite (raid
  leader/assist)
- **Test Alert** button — fires a fake alert so you can preview your setup

**Ignore Rules tab**
- Enable/disable switch
- Minimum item level and minimum Mythic+ score. Leave either at `0` to not
  check it.
- A tank applicant is ignored — no flash, sound, chat message, or popup —
  if their item level is below the minimum **OR** their M+ score is below
  the minimum (either failing is enough; you don't need to set both).
  Leaving both at `0` effectively turns the rule off even if "enabled" is
  checked.

### Slash commands (`/tankalert` or `/ta`)

| Command | Effect |
|---|---|
| `/ta options` | Open the settings window |
| `/ta test` | Fire a test alert |
| `/ta status` | Show whether you have an active listing and pending tank count |
| `/ta debug` | Dump raw applicant + Raider.IO data to chat (troubleshooting) |
| `/ta sound raidwarning\|readycheck\|none` | Quick sound switch (full list + preview in `/ta options`) |
| `/ta flash on\|off` | Toggle the screen flash |
| `/ta popup on\|off` | Toggle the Invite/Decline popup |
| `/ta chat on\|off` | Toggle chat announcements |

The ignore rule's two number fields live in `/ta options` only.

## Raider.IO integration

The popup can show four extra pieces of info per applicant: current M+
score, previous-season score, and their best key overall and for the
specific dungeon you're recruiting for — each shown as dungeon + level +
chest rating (e.g. `++18 Mechagon`), the usual community shorthand.
None of this comes from Blizzard — the LFG API only ever gives you an applicant's current-season
overall score (which the addon already showed before this feature).
Per-dungeon history and previous-season data for *other players* simply
isn't sent to your client under any circumstance; the only way to get it is
through the separate [Raider.IO addon](https://www.curseforge.com/wow/addons/raiderio),
which maintains its own locally-cached database. LFG TankAlert reads from that
addon's data if it's installed — it does not talk to any server itself
(WoW addons cannot make network requests at all).

What that means in practice:
- If you don't have Raider.IO installed, these lines never appear — no
  error, just nothing extra.
- If you do, coverage is only as good as Raider.IO's database: casual/lower
  M+ players are often not in it at all, and the data is a periodic snapshot
  (Raider.IO says they refresh it multiple times a day), not live.
- "Best key level for this dungeon" is matched by comparing Raider.IO's
  per-dungeon data against the activity ID(s) of your posted listing. This
  match is best-effort — if it doesn't line up on your client, run
  `/ta debug` while an applicant is pending; it now dumps the raw Raider.IO
  lookup too, which is exactly what I'd need to fix the matching.
- Toggle this off entirely in `/ta options` -> Alerts -> Notifications ->
  "Show Raider.IO score in popup".

## Notes & caveats

- This hooks into the **Premade Groups / Group Finder** applicant system
  (`C_LFGList`) — M+ has no automatic matchmaking queue, so "a tank queues"
  means "a tank applies to the group you posted."
- LFG TankAlert cannot actually invite or decline anyone without you clicking
  a button. `C_LFGList.InviteApplicant`/`DeclineApplicant` are protected
  functions — Blizzard blocks addons from calling them automatically (this
  is a deliberate anti-automation restriction, confirmed by testing: it
  throws `ADDON_ACTION_BLOCKED` if attempted from an event handler). The
  Invite/Decline popup buttons work because they're real clicks — that's the
  only way this addon can take that action for you. This is also why the
  ignore rule only *suppresses the alert*; it can't auto-decline anyone.
- Mythic+ score comes straight from the applicant's profile as Blizzard's
  group finder itself sees it. A brand-new alt or an off-spec with no
  calculated score this season may read as `0` — an ignore rule based on
  score alone won't incorrectly hide someone if you leave that field at `0`
  (unrestricted), but if you set a minimum, a legitimately-scoreless
  character will fail it.
- The ignore rule uses the best-geared tanking member's stats if the
  applicant applied as a premade duo/trio rather than solo.
- Settings are saved per-account (`TankAlertDB` in SavedVariables), so they
  persist across sessions and characters.

## Changelog

**1.5.0**
- Fixed: raid members without leader or assist rank were getting the full
  alert (flash/sound/popup) for applicants they had no ability to actually
  invite or decline. In a raid, only the leader and assistants can manage
  the group's Premade Groups listing — everyone else could still see the
  applicant data apparently, just not act on it.
- New toggle in Alerts -> Notifications: **"Only alert when I can invite
  (raid leader/assist)"**, on by default. Solo / not-yet-grouped is treated
  as "yes, you can invite" (you're the de facto leader of your own future
  group); a plain raid member with no assist is treated as "no." Also
  reflected in `/ta status`. Turn it off if you want alerts anyway, e.g. to
  flag a good applicant to whoever's actually leading.
- The addon now also reacts immediately to leader/assist changes mid-raid
  (listens for `GROUP_ROSTER_UPDATE`), not just to new applicant events.

**1.4.2**
- Renamed the display name to **LFG TankAlert** — the `## Title` shown in
  the AddOns list, the options window title, and all chat messages.
  The addon folder, `.toc` filename, SavedVariables (`TankAlertDB`), and
  slash commands (`/ta`, `/tankalert`) are unchanged, so existing settings
  carry over with no action needed.

**1.4.1**
- Removed Raid Boss Warning, Boss Emote Warning, Whisper Ping, and Dungeon
  Reward Chime from the sound dropdown. Also added a safety net: if a saved
  sound choice is ever pruned like this again, it falls back to Raid Warning
  automatically instead of leaving a stale, unlabeled selection.

**1.4.0**
- The Alerts tab's sound picker is now a proper dropdown (built as a custom
  flat widget, not Blizzard's `UIDropDownMenu`, for the same skinning-addon
  reasons as everything else in this window) instead of a row of buttons.
- Added a **Preview** button next to it that plays whatever's currently
  selected, on demand.
- Added 7 more sound options, all cross-checked against Blizzard's real
  `SOUNDKIT` table before shipping: Alarm Clock 1/2/3, Raid Boss Warning,
  Boss Emote Warning, Whisper Ping, and Dungeon Reward Chime.

**1.3.2**
- Fixed the "Best key" formatting: chest-rating `+`s were split with one on
  the left (a leftover "keystone level" prefix) and the rest on the right
  (e.g. `+18++`). Now they're all on the left of the number, e.g. `++18`.

**1.3.1**
- The Raider.IO "Best key" line now also shows the dungeon (shortname) and
  the chest rating (`+`/`++`/`+++`, the same shorthand as in-game — number
  of "+"s the key was upgraded by; none means it was turned in over time),
  e.g. `Best key: +18++ Mechagon`. "This dungeon" gets the same treatment.

**1.3.0**
- Replaced the Decline Rules / Invite Rules tabs (which could only ever
  *recommend* — see the protected-function note above — and covered all
  three roles) with a single, simpler **Ignore Rules** tab: mutes the tank
  alert entirely (no flash/sound/chat/popup) for tanks below a minimum item
  level **or** minimum M+ score. Simpler mental model, and it actually does
  what its name says instead of needing a caveat about clicking.
- The popup, chat message, and `/ta test` are unchanged otherwise; the
  Raider.IO info lines still show.

**1.2.0**
- Added optional **Raider.IO integration**: when you also have the Raider.IO
  addon installed, the popup now shows the applicant's current M+ score,
  previous-season score, best key level overall, and (when it can match the
  dungeon) their best key level for the specific dungeon you're recruiting
  for. Toggle it off in Alerts -> Notifications -> "Show Raider.IO score in
  popup". See **Raider.IO integration** below for exactly what this can and
  can't do — Blizzard itself never sends this data for other players, so
  this only works through Raider.IO's own locally-cached database.

**1.1.3**
- Rebuilt the settings window and popup from flat custom widgets instead of
  Blizzard's `UIPanelButtonTemplate`/`DialogBox` art. Those get repainted by
  UI-skinning addons (ElvUI etc.) independently of each other, which is what
  made the previous version look inconsistent (grey "disabled" tabs next to
  solid-red buttons, ornate stone borders clashing with a flat skin). The
  window is now a self-drawn dark flat panel with a thin gold accent, so it
  renders the same regardless of what skin addon is running.
- More breathing room around number fields (`Min ilvl` / `Min M+ score` etc.
  now have a clearer label gap and wider spacing between columns).
- The popup's Invite/Decline buttons are now color-coded (green/red).

**1.1.2**
- **Removed the automatic invite/decline API calls** — they threw
  `ADDON_ACTION_BLOCKED` every time, since WoW protects those functions from
  being called outside of a real player click. Auto-Decline/Auto-Invite are
  now "Decline Rules"/"Invite Rules": they flag matching applicants with a
  recommendation in the popup instead of silently failing to act.
- Extended the popup to a general applicant queue: any non-tank applicant
  that matches an enabled rule now also gets a quiet chat ping + shows up in
  the popup with an "meets your criteria" / "below your minimums" tag.
  Tanks still always get the full flash/sound/popup treatment regardless of
  whether a rule matched.
- Fixed the color picker's cancel button, which assumed
  `ColorPickerFrame:GetPreviousValues()` returns a table — it actually
  returns several separate values, so `cancelFunc` threw an error trying to
  index a number. It now just remembers the color you had before opening the
  picker instead of asking the API for it.
- Redesigned the settings window: section headers with dividers, a proper
  gold-underline "selected" state for tabs (previously used `:Disable()`,
  which read as broken next to a button skinning addon's styling), an inset
  content panel, and the window now resizes to fit each tab instead of
  leaving dead space.

**1.1.1**
- Fixed the actual root cause of "nothing happens when someone applies":
  `C_LFGList.GetApplicantInfo()` returns a single table/struct on current
  retail, not several separate values as documented on the wiki — the code
  was destructuring it the old way and silently getting `nil` for
  application status, so every applicant was skipped. Now reads the struct
  correctly (with a fallback for the old style), and member counting no
  longer depends on that field at all — it counts by probing
  `GetApplicantMemberInfo` directly instead.
- The event handler now catches errors and prints them in red to chat
  instead of failing silently, and login now prints a confirmation so you
  always know the addon is active.
- Added `/ta debug` to dump the raw applicant data straight to chat.

**1.1.0**
- Added `/ta options` settings window (Alerts / Auto-Decline / Auto-Invite tabs)
- Added flash color picker
- Added "None" sound option
- Added auto-decline and auto-invite by item level and Mythic+ score
- Fixed a field-order bug in the applicant lookup that could show the wrong
  class color name and, in rare timing cases, error out the applicant scan
  entirely (found while verifying the API for this update)

**1.0.0**
- Initial release: tank-applicant flash/sound/chat/popup alerts
