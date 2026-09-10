# Creating a new unit — exact steps

Like buildings, there's only one script: `Unit` (`scripts/unit.gd`, on
`scenes/units/unit.tscn`). A new unit type is a scene that **instances**
`unit.tscn` and overrides its exported fields — see
`scenes/units/soldier_unit.tscn` for the smallest complete example (it
overrides display_name/costs/team_tint/sprite/combat stats and nothing else).

## 1. Create the scene

In the FileSystem dock: right-click `scenes/units/unit.tscn` → **New Inherited
Scene**, save it under `scenes/units/` with a descriptive name (e.g.
`archer_unit.tscn`). Select its root node — every field below is set there.

Do **not** duplicate the `.tscn` file instead of using "New Inherited Scene"
— inheriting means this unit automatically picks up any future change to the
base `unit.tscn` (new nodes, new `SceneReplicationConfig` entries, etc.)
without needing to be touched again.

## 2. Identity and sprite sheet

- **Display Name** — shown in the info panel and unit-portrait tooltips.
- **Sprite Sheet** group: point **Sprite Sheet** at the new texture, set
  **Sprite Cell Size** to match its grid, and set each row/frame-count pair
  (**Idle**, **Walk**, **Attack**, **Death**, **Gather**) to match the sheet's
  layout. **Gather** row is only ever played if **Can Gather** is also true —
  harmless to leave at the default otherwise.

## 3. Cost and population

**Cost** group: **Costs** (`Array[ResourceCost]`) and **Population Cost**.
This is the *only* place a unit's price/pop cost is set — a `ProducibleItem`
offering this unit on some building's Producibles list reads these back
directly (`ProducibleItem.get_costs()`), so balancing never needs touching
two places.

## 4. Combat stats (skip for a pure gatherer like a Villager)

**Combat** group:
- **Can Fight** (false makes it never auto-engage or take a Command.Attack)
- **Max Health**, **Attack Damage**, **Attack Range**, **Attack Cooldown**,
  **Aggro Range**
- **Damage Type** — this unit's own rock-paper-scissors type (`NONE` if it
  has no bonus-damage matchup)
- **Weak To** — a `DamageType` this unit takes 1.5x damage from; `NONE` for
  immune to the whole system
- **Unit Category** (`NONE`/`Infantry`/`Archer`/`Cavalry`) — which Blacksmith
  upgrade line (see `docs/creating-an-upgrade.md`) affects this unit. Use
  `NONE` for a non-combat unit like a Villager so no Blacksmith tier ever
  touches it.
- **Projectile Scene**/**Projectile Speed** — leave **Projectile Scene** null
  for a melee unit (instant on-cooldown damage). Set it for a ranged unit: a
  visual projectile scene is spawned locally by `main.gd` per peer, but the
  *real* damage is authoritative on the host and only lands when the
  projectile's travel time elapses (see `Unit._tick_pending_projectiles`) —
  so a target can duck out of range or die before a shot in flight connects.

## 5. Gathering/building (skip for a pure combat unit)

**Gathering** group: **Can Gather**, **Gather Level**, **Carry Capacity**,
**Can Build** (whether it can be sent to help construct — most non-Villager
units leave this off).

## 6. Order sounds (optional but recommended)

**Order Sounds** group: one `AudioStream` array per order type (Move/Attack/
Patrol/Build/Stop/Gather), played once when the *player* actually issues that
order (not for automatic behavior like auto-retaliation). Also set **On
Select Sound Effects** at the top level, played once per new selection.

## 7. Team tint

Set **Team Tint** to the placeholder color used before a real per-peer tint
is applied at spawn (`main.gd` overrides this with the owning player's actual
team color when the unit is produced) — mostly matters for a hand-placed unit
(e.g. an Objective guard) that's never spawned through that path.

## 8. Monarch promotion (optional)

**Monarch** group: leave **Monarch Abilities** empty to make this unit type
never promotable. To allow promotion, add one or more `Ability` resources
(passive aura or active ability — see any existing entry on
`soldier_unit.tscn` for the shape) and set **Monarch Promotion Costs**.
Promotion itself is still gated by some building on the owner's roster having
completed an `Upgrade`-kind `ProducibleItem` with **Unlocks Monarch
Promotion** checked (see `docs/creating-an-upgrade.md`) — the ability list
here only decides *what a promoted unit of this type can do*, not *whether*
promotion is available yet.

**Abilities** group (just above Monarch): abilities this unit type always has,
no promotion needed — every Shrine monster has one. For a clickable area
attack, add an `Ability` with **Kind: Activated Area** and fill in the
**Activated** group (range, cooldown, optional costs) and the **Area Effect**
group (radius, instant damage, damage over time, slow, stun, and the colour
used for the targeting decal and impact). Any `*_unit.tscn` in
`scenes/units/monsters/` has a working example. Abilities get hotkeys R/T/Y/U
in list order, and a unit's own abilities come before its Monarch ones.
Clicking a target out of range makes the unit walk until it's in range, then
cast.

How an area ability looks:
- **Cast Row / Cast Frame Count / Cast FPS** (Sprite Sheet group, on the
  unit): the clip played when it casts. On the MiniBigMonsters sheets that's
  row 4, the long special attack (row 3 on the Phoenix). With 0 frames the
  ordinary attack swing plays instead.
- **Cast** group (on the Ability): **Cast Windup** is how far into that clip
  the ability actually goes off, so match it to the frame where the monster
  breathes, throws or slams. **Cast Effect** is an optional flash at the mouth,
  and **Launch Offset** says where the mouth is (forward, up).
- **Projectile** group: **None** lands on the target straight away, **Flying**
  sends the projectile through the air, and **Ground Wave** erupts it along the
  ground from caster to target. Damage lands when the projectile arrives.
- **Impact** group: a burst at the target, plus **Impact Scatter Count**
  smaller ones spread across the radius.

Each effect is a `SpriteEffect` (`scripts/sprite_effect.gd`): a sheet, frame
size, row, first frame, frame count, fps, scale and tint. Turn on **Orient To
Direction** for breath and bolts that should point where they're going. The
effect sheets live in `assets/art/MiniBigMonsters/`.

`cmd spawn <name> [count]` in chat spawns this unit at the cursor for testing.
`<name>` is the scene file name without `_unit.tscn`, for example
`cmd spawn giant_bear 2`.

## 9. Offer it on a building

A unit sitting only in `scenes/units/` is never produced by anyone — add a
`ProducibleItem` with **Kind: Unit** and **Unit Scene** pointed at your new
scene to whichever building's **Producibles** list should train it (see
`docs/creating-a-building.md`, Variation A).

## Verify

1. Run `main.tscn` directly, queue the unit from its building, confirm it
   spawns with the right sprite/animations and stats (info panel should show
   the new Display Name and correct HP).
2. Host + Join with two windows — produce it as the client player, confirm it
   appears correctly on both screens with the right team tint, and that
   combat/death/gathering all replicate (health bar and death animation both
   update on the peer that didn't kill it).
3. If ranged: confirm the projectile visually travels on both peers and only
   the host's authoritative timer actually applies damage (check by having a
   target flee mid-flight — a real hit shouldn't land after it's out of
   range).
4. If Monarch-capable: confirm promotion is unavailable until the relevant
   Upgrade is bought, then available after.
