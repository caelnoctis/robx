# NoctisENIX

A Roblox script for **MAFIA [V2.3] - ACT II** (Topline Studios Inc), built for the **Xeno** executor. It uses no external libraries, no Drawing API and no outbound requests. Every executor-specific function is checked first and wrapped in `pcall`, so a feature that needs a function Xeno does not have simply turns itself off without breaking the others.

## How to use

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/caelnoctis/robx/claude/roblox-mafia-noctissenix-1t79fn/NoctisENIX.lua"))()
```

Menu: **RightShift** (can be changed in Settings). Running the script again unloads the old instance automatically.

**Keybinds** are saved automatically to `workspace/NoctisENIX/settings.json` (Xeno's workspace folder) and loaded again every time the script runs. Click a chip and press a key to bind it. Right-click a chip (or press Backspace while it says PRESS) to remove the bind. The **Clear all keybinds** button in Settings removes all of them except the menu key. Each keyboard key can only be used by one feature.

## Inspector (for calibration)

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/caelnoctis/robx/claude/roblox-mafia-noctissenix-1t79fn/NoctisENIX_Inspector.lua"))()
```

1. Run it **while you are already in a match**, then press **Snapshot**. The **GAME NETWORK** section calls the game's read-only getters (role, teamMembers, gamePhase and similar) to show what their replies look like. Action remotes such as `onStab` are never called by the Inspector. The **DECOMPILE** section reads the code of the client role modules (without running it) so the real arguments of `onStab` / `onHeal` are visible.
2. Press **Start live log**, then play one full round: night, someone gets stabbed, someone gets healed, meeting, voting. If you can, play once as Mafia and once as another role.
3. Press **Save**. The result is saved to Xeno's `workspace/NoctisENIX/` folder (and copied to the clipboard).
4. If the screen stays dark during an EMP even with Fullbright on: **Start live log**, wait for an EMP, then **Save**. The **LIGHTING** section and the `LIGHT` lines in the live log show everything the EMP changes (Lighting properties, effects in Lighting / Camera, the `EmpInk` / `EmpAfterimage` ScreenGuis, lights). This part only reads; it writes nothing to the game.
5. Send that `.txt` file. It contains the game's module structure, role configs, attributes, animations, remotes and an event log for the round, so role detection and the action features can be matched to the game's real names.

## Look (v2.6)

The menu uses the "Phantom" theme: red, black and white, inspired by the Persona 5 Royal menu style (fan-inspired, not official assets). The title is a ransom-note collage (every letter in its own tilted box), the active tab is a tilted white slab on top of a red slab, page titles sit on a red slab, action buttons are red and flip to white on hover, toggles turn into a diamond when ON, and toasts look like calling cards. Every shape is drawn from Frames, UIStrokes and UIGradients right in the script, with no images and no game logos, fonts or textures. Description text stays upright and uses a plain font so it is easy to read for long sessions.

## Features

| Tab | Contents |
| --- | --- |
| ESP | Team-colored highlight (red Evil, gold Veil, green Town, purple Neutral, grey = not certain yet), a line with `EVIL TEAM` / **in-game character name** / `[ROLE]` in the **game's own role color** (Roblox @username optional), DOWNED / DETAINED / SILENCED / IN LOCKER status, distance, HP. The text sits right above the head with no dark box (the box can be turned back on with "Text background"). By default only **certain** roles are shown; guesses can be turned on with "Show guesses too" |
| Votes (in the Visuals tab) | "Judge vision" for any role. **Vote tags**: `VOTES → name` or `VOTES → SKIP` above the voter's head and `N VOTES` above the person being voted. **Vote lasers**: a line through walls from the voter's hand to the person they vote, red when that person is you. Works even with ESP off |
| Roles | Your role, a list of **who votes whom** + tally (the last voting stays visible for 2 minutes), the list of roles found so far with the reason, kill feed and evidence log, role notifications, an alert when someone votes you, round reset |
| Deception | Fake crawl, fake stab (`KnifeSwing`), fake gunshot (`Glock`), ghost, **Escape meeting seat**, **Stand on the table** (all of them can have a keybind) |
| Teleport | Pick a target, to target / to the downed player / to the detained player, Teleport-Stab-Return (Mafia), Bring target, Teleport-Heal-Return (Doctor) |
| Player | Walk speed, jump power, infinite jump, noclip, fly, FOV |
| Players | Player list + roles, target, teleport and spectate buttons |
| World | Fullbright, no fog, instant interact, anti AFK |
| Dev Tools | Remote scan, player dump, remote logger |
| Settings | Menu key, keybinds (save / clear), **your game hotkeys** (T / G / R / Q / E / F or whatever you changed them to), cursor, game check, rejoin, unload |

## Important notes (v2.1)

* **Stab / shoot buttons (T / F) not showing up?** There are two causes visible in the game log:
  1. You are **Detained** (jailed by the Detainer). The game disables Mafia actions for that time.
  2. Older versions `require`d the game's controller modules. On Xeno that re-runs the controller code and can break the key bindings. Since v2.1, NoctisENIX and the Inspector **never** `require` client modules; the only thing required is config data (`shared.configurations`).
* Close the menu (RightShift) while aiming a stab or a shot. While the menu is open the mouse is released so the UI can be clicked, which means the game cannot aim.
* Strict role calls: player chat in this game goes through the system message path and used to be read as announcements. Player chat is now ignored, attack animations are locked to the real IDs (`KnifeSwing`, `Glock`), and only certain roles are shown by default.

## Notes v2.3 (calibrated from a lobby capture)

* **Ability not firing when you press its key?** Ability keys in this game can be changed by the player, and the choice is stored in the `Hotkeys` attribute (for example `{"ability2":"F","flashlight":"G"}`). The defaults are Main ability **T**, Second ability **G**, Third ability **R**, perk **Q**, interact **E**, flashlight **F**. Settings > **Game hotkeys** now shows the keys that are actually active on your account (`*` = you changed it).
* If a NoctisENIX keybind is set to the same key as a game ability, you get a warning, because one press triggers both.
* The game has its own **Free cursor** key (default **P**). If the cursor gets locked outside the menu, that key releases it.
* Role colors in the ESP come from the game's `roleColorsConfig`, so they match the game's UI exactly.

## How Vote ESP works (v2.4)

In this game only the **Judge** can see who votes whom ("No ballot is secret in your court"): the game attaches a `judgeBallotTag` ("VOTES TO SKIP" / "ACCUSES Nora") and a `judgeBallotLaser` for the Judge only. NoctisENIX gives the same view to any role. Vote data comes from the game's network and is only ever read (ordered from most to least trusted):

1. The `judgeBallotTag` tags on your screen, if you are the Judge yourself.
2. `RoleNetworks.judge.observedBallots`: the Judge's ballot getter, asked every 2.5 seconds **only during voting**. If the server only fills it for the Judge, the result is empty and the other sources are used.
3. `gameService.talliedVotes`: the vote tally.
4. `gameService.votePlayer`, if the server broadcasts it.
5. `pointingService.updateArmPointing`: the arm of every player pointing at the person they vote. This event is sent to every client. Its real shape (from an Act II capture) is `{ ["<UserId>"] = {...} }`, and `"r"` means the arm was lowered. The `{...}` contents are parsed loosely: player, character, body part, UserId, character name, position, direction, or the word "skip". Arms also go up and down during night and discussion (Witch capture), so pointing **only counts during the Voting phase** and is ignored outside it.
6. The `talliedVotes` / `playerVotes` attributes as a fallback.

The SKIP count is also read from the `3/8` counter on the voting screen (`PlayerGui.SkipIntro ... CounterInk.Label`), which every role can see. In the Roles tab it shows up as `SKIP 3/8`.

If a vote does not show up, run Inspector 1.3.0 with **Start live log** during one voting and send the result. This version writes the contents of `updateArmPointing` up to 4 levels deep and also decompiles the Judge module and `pointingController`.

## How role detection works

This game **does not keep other players' roles on the client**. An attribute dump from the real game confirms it: the only things there are `DisguiseName`, statuses such as `Downed`, and the `<Role>Boosters` attributes (boosters for the chance to get a role, **not** the role currently held, so they are deliberately ignored). Roles are therefore gathered from several sources, with the confidence levels `confirmed`, `likely` (`?`) and `suspect` (`??`):

* **Game network** (`ReplicatedStorage.ServiceNetworks` and `RoleNetworks`):
  * Your own role from `roleService.role`, plus `getRoleNetwork`.
  * Teammates from `teamService.teamMembers` and your role's own `teamMembers`.
  * Role reveals from `gameService.revealRoles`, death cutscenes, `chatService.onSystemMessage` and `announcementService.show`.
  * The phase from `gameService.gamePhase` and `setTopbarText`.
* **Action evidence**: stab or shot animations at night (Mafia), shots during the day (Vigilante), a victim getting silenced (Witch), doors locked or bananas (Saboteur), doors opened or cleanups (Janitor), a victim getting up from downed or cured of poison (Doctor). When there are several candidates, they are narrowed down event by event.
* **System announcements**, including the Harbinger guessing flow.

Roles and teams (read from the game's `teamsConfig` while in a match; the fallback is copied from an Inspector capture):

| Team | Roles |
| --- | --- |
| Evil (Mafia) | Mafia, Witch |
| Veil | Saboteur, Mirage, Poisoner, Harbinger |
| Town | Civilian, Detective, Doctor, Vigilante, Janitor, Detainer, Judge, Suppressor |
| Neutral | Jester, Bodyguard |

The Bodyguard is neutral, but sides with whoever they protect. If they show up in the Mafia's `teamMembers` list, the ESP shows `EVIL TEAM` + `[BODYGUARD]`. Phantom and Snow Spirit are seasonal roles; while `seasonalRolesConfig` has them off, they are not matched.

The exact argument shapes of some remotes (for example what `revealRoles` sends, or the `onStab` arguments) have not been seen directly yet, so the parsers accept several shapes. Inspector results (the **GAME NETWORK** section and the live log) are used to lock down the exact format.

## Repo layout

```
src/main.lua            UI, ESP, movement, wiring
src/modules/*.lua       ui (UI library), game_api (game internals), net (game network),
                        intel (role detection), actions (deception + teleport)
src/inspector.lua       Inspector
tools/build.py          builds src/ into NoctisENIX.lua and NoctisENIX_Inspector.lua
tests/                  Luau harness (luau-web) with a Roblox mock
```

After changing `src/`: run `python3 tools/build.py`, then run the tests in `tests/` (see `tests/README.md`).

## Safety and risk notes

* NoctisENIX makes no outbound network requests. The Inspector only writes local files to the executor's workspace folder.
* Features such as ghost and teleport can be detected by the game server. Running scripts in an executor breaks the Roblox Terms of Use and can get your account banned. Use an alt account.
