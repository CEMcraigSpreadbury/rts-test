# Crowns of Aldmere — 1.0 scope

Agreed 2026-10-15. This page says what "finished" means. Anything not on it
goes to **Parked**: kept in the repo or in git history, not worked on.

## What ships

- **Single player only.** The Multiplayer button stays in the menu, disabled
  (`MULTIPLAYER_ENABLED` in `scripts/main_menu.gd`). The lobby and netcode
  stay as they are, but nobody tests or extends them for 1.0.
- **Player race: Aldmere (Human)**, as now.
- **Settlement races: Beastmen, Dark Elves, Aldmere.** Each one finished:
  buildings, units, beasts, upgrades, icons, sounds.
- **Campaign:** the main reason to play. It should be well written, paced and
  tested, with the tutorial first.
- **Skirmish** against the AI on a handful of maps (3 is enough).
- **Modes:** Realm (default) and Annihilation, both in skirmish.

## Rules until 1.0

1. **Feature freeze.** A change gets in only if it fixes something a player
   ran into, or finishes something on this page.
2. **A new idea replaces something, it doesn't add to it.** Otherwise it goes
   under Parked.
3. **The look is settled:** Toy UI, diorama figures, the current terrain.
   No more restyles. Only finish screens that don't match the look yet.
4. **Performance work only when a real match stutters,** not ahead of time.

## Milestones

1. **Lock scope.** *(Done 2026-10-15.)* Turn the multiplayer button off. Swap the Star Wanderers
   settlements on Aldmere Vale and Four Kingdoms for the three 1.0 races.
   Decide what else under Parked is visible in-game and hide it.
2. **Vertical slice.** Bring m1, the tutorial, to shipping quality:
   onboarding, icons, audio, balance, no bugs. This sets the bar and shows
   how long the remaining work really takes.
3. **Campaign.** Bring m2 and m3 up to that bar. Then decide on the final
   number of missions (maps can be reused).
4. **Skirmish.** Polish the setup screen, run an AI difficulty pass, balance
   the three races on 3 maps.
5. **Playtest and polish.** Outside players every 1–2 weeks, scored against
   the 3/10 review; fix what they hit.
6. **Demo / 1.0 build.** Export, verify, Steam page, trailer.

## Parked (post-1.0)

- Multiplayer (lobby, ArmyNet snapshots, Steam networking)
- Star Wanderers (code and models stay dormant; not placed on maps)
- More races, more player races
- Native sim Phase B / MultiMesh rendering
- Toy terrain plan B
- Grand strategy, diplomacy, morale, squads, and anything else dropped before
