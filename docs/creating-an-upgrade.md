# Creating a new upgrade — exact steps

An upgrade is a `ProducibleItem` resource (`scripts/producible_item.gd`) with
**Kind** set to `Upgrade`, sitting in some building's **Producibles** list —
same list unit entries live in, distinguished by `Kind`. There is no separate
"upgrade scene"; everything is fields on this one resource type.

## 1. Add the `ProducibleItem`

Open the building that should sell it (e.g. `blacksmith_building.tscn` for a
combat upgrade, but any `ProductionBuilding` can offer one), select its root
node, expand **Producibles**, grow the array by one, and fill in:

- **Kind** → `Upgrade`
- **Item Name** — shown on its command-card tooltip
- **Build Time**
- **Costs** (`Array[ResourceCost]`) — unlike a `Unit` item, an `Upgrade`
  item's costs are read directly off itself, not off some other scene, since
  there's nothing else to read them from.

## 2. Pick what it does

An upgrade needs at least one of these two effects set (both can be set at
once, though in practice existing content picks one per item):

### A — Blacksmith-style weapon/armor bonus

- **Upgrade Category** → which `Unit.UnitCategory` it affects (`Infantry`/
  `Archer`/`Cavalry`; `NONE` means it affects nothing — don't leave it here
  by accident).
- **Upgrade Stat** → `Weapon` (adds to attack damage) or `Armor` (subtracts
  from incoming damage, floor of 1).
- **Upgrade Bonus** → the flat integer amount.

On completion (`main.gd:_on_building_item_completed`) this calls
`UnitUpgrades.add_bonus(owner_peer_id, category, stat, bonus)`. `UnitUpgrades`
is a host-only autoload keyed by `[peer_id][category][stat]` — the bonus
applies to **every unit of that category the buying player owns, including
ones produced later**, automatically picked up by
`Unit.take_damage()` (armor) and `Unit._effective_attack_damage()` (weapon).
No per-unit wiring needed; a unit only needs its own **Unit Category** field
(see `docs/creating-a-unit.md`) set to match for this to apply to it.

### B — Unlocks Monarch promotion

Check **Unlocks Monarch Promotion**. On completion this sets
`can_promote_monarch = true` on the building that sold it — checked by
whatever UI/command offers the promotion action for that owner's units. This
is a one-off boolean, not a per-category bonus; it doesn't need **Upgrade
Category**/**Upgrade Stat**/**Upgrade Bonus** set at all.

## 3. Tiering (optional)

To make an upgrade line with multiple sequential tiers (e.g. Weapon Tier 1 →
Tier 2 → Tier 3, each strictly requiring the last):

1. Create each tier as its own `ProducibleItem` in the same building's
   Producibles list, same **Upgrade Category**/**Upgrade Stat**, increasing
   **Upgrade Bonus** and **Costs** per tier.
2. On tier 2+, set **Requires Upgrade** to point at the tier-1 resource (tier
   3 points at tier 2, and so on). Leave it null on tier 1.

This is enforced twice, so the UI and the actual purchase can never disagree:
`ProductionBuilding.enqueue()` refuses buying a tier whose
**Requires Upgrade** hasn't been purchased yet (or that's already been
bought — every `Upgrade` item is a strict one-time purchase per building),
and `main.gd:_producible_is_visible()` hides every tier from the menu except
the next legitimately-buyable one, so a player never sees the whole line
at once.

## 4. A genuinely new upgrade *effect* (beyond A/B above)

If neither "flat weapon/armor bonus" nor "unlock Monarch promotion" fits what
you're adding, the extension point is `main.gd:_on_building_item_completed()`
(the `if item.kind == ProducibleItem.Kind.UPGRADE:` branch): add a new
optional field to `ProducibleItem` (mirroring `unlocks_monarch_promotion`'s
pattern — a plain `@export var` defaulting to whatever means "off"), then a
matching `if` in that function applying the effect. Keep the field boolean/
numeric and off-by-default so it never silently interacts with existing
items that don't set it.

## Verify

1. Run `main.tscn` directly, buy the upgrade, confirm the effect actually
   applies (damage/armor numbers change in combat, or the promotion action
   becomes available).
2. Confirm the item disappears from the menu immediately after purchase (or
   the next tier appears in its place, for a tiered line) — this should need
   no manual refresh.
3. Confirm a second, not-yet-purchased tier can't be bought out of order
   (button shouldn't even show, per step 3's visibility rule).
4. Host + Join: buy it as the client player, confirm the effect applies only
   to that player's units, not the host's, and that a newly-produced unit
   (after the upgrade, not just units that existed at purchase time) also
   gets the bonus.
