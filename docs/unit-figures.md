# Unit figures

Units are being moved from pixel sprites to rigid 3D chibi "diorama" figures:
little low-poly models that hop along, lean into swings and topple when they
die. There is no skeletal animation; all motion is procedural.

The target look is in `docs/art-reference/reference-diorama-3.png`.
`helmet-styles.png` in the same folder is the source for the helmet shapes.

## How it works

- **Blender kit:** `assets/art/Models/Units/kit/`.
  - `units.py` holds one recipe per unit and the `UNITS` table. A plain build
    only builds entries marked `ready`.
  - `parts.py` has the body, head and face. Every human shares one face.
  - `headgear.py`, `clothes.py`, `gear.py` and `poses.py` are the shared parts.
  - Each race has its own module: `gnoll.py`, `hyena.py`, `dark_elf.py`.
    Horses are in `horse.py`.
  - `palette.py` defines the colour rows. Each race has a palette image in
    `palettes/`, and the bottom rows are team rows.
- **Build:**

  ```
  "C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" --background --factory-startup --python build.py -- <Name ...> [--lineup DIR] [--out DIR] [--team-body tunic|tabard]
  ```

  With no names, every `ready` unit is built. `--lineup` renders a blue and red
  line-up from the front, the game camera's pitch and the side. `--out` writes
  a trial build somewhere else, so the game's GLBs are left alone.
- **In game:** `native/src/figure_batcher.*` draws the figures. Each unit type
  has a near model, a far (LOD1) model and a shadow MultiMesh.
  - The pose comes from the unit's hidden AnimatedSprite3D: which clip is
    playing and how far through it, plus its lunge and squash.
  - A unit type opts in through the `Figure` export group on its scene:
    `figure_model`, `figure_model_lod1`, `figure_palette`, `figure_motion`
    (0 melee, 1 bow/caster, 2 mounted/quadruped) and `figure_top` (the
    health bar height).
  - `cmd figures` in chat switches every unit back to its sprite for
    comparison. `ui_shot --sprites` does the same.
- **Native rebuild** (after a change to `figure_batcher`):

  ```
  cd native; python -m SCons platform=windows target=template_debug custom_api_file=api/extension_api.json -j12
  ```

  Then the same with `target=template_release`. Restart the editor afterwards.

## Style rules (agreed with the user)

- Chibi proportions: the head is about 40% of the height. Low-poly but
  crafted, not primitive shapes. No outlines and no bases. The kit has a
  `--base` option that is off.
- Every human has the Soldier's face and framing. Other races keep the same
  eye style.
- Team colour goes on the tabard (or a loincloth, sash or saddle cloth), the
  shield face and the hem. Helmets are plain steel.
- Each type has its own helmet or headgear shape, so types read apart at a
  distance:
  - Soldier: kettle hat
  - Spearman: morion
  - Shieldman: nasal helm
  - Horseman: sallet
  - Halberdier: barbute
  - Crossbowman: burgonet
  - Officer: armet with the visor up
  - Cavalier: great helm
- Weapons are chunky, oversized and high-contrast. They are the main way to
  tell types apart.
- Blade edges always face the ground (`parts.edge_down`).

## Roster status

Done and in game:

- **Aldmere:** Soldier, Villager (with build, wood and gold variants), Archer,
  Spearman, Shieldman, Halberdier, Crossbowman, Officer, Lord, Wizard,
  Arch Mage, Horseman, Cavalier.
- **Gnolls:** Warrior, Archer, Berserk, Leader, Shaman, Hyena.
- **Dark Elves:** Warrior, Archer, Assassin, Guard, Rider.

Next, in this order:

1. Dark Elf Sorceress and Spellstealer.
2. Beastmen: build one unit first and get it approved, then the rest.
3. Star Wanderers: build one unit first and get it approved, then the rest.
4. Animals, beasts and monsters (`scenes/units/animals`, `beasts`,
   `monsters`).
5. Siege: Ballista, Magic Cannon and siege crew.
6. Portraits: the selection panel, tray, regiment cards and banners still
   show sprites. `build.py --portraits` is written but has never been run.

Known open points:

- The longbow and the Dark Elf Rider's black lance read thin.
- The Dark Elf Rider's horse is mostly hidden behind the rider from the front.
- The fix that makes attackers face their target (`Unit._land_swing` snaps
  the yaw) has not yet been checked in a real melee.
- Mages have no real staff raise. Their attack borrows the bow motion.

## Working method

- One small step at a time (one or two figures), then stop for the user's
  review.
- Pause after the first unit of every new race.
- Use the `figure-builder` agent in `.claude/agents/`.
- Allow at most 2 or 3 line-up renders and 1 game launch per step, and give
  every Godot run `--quit-after`.
- Windows and Forward+ only; the web build is on hold.

## Also paused

The diorama scenery pass, which is the next step after the lighting work
(done) and the outline removal (done):

- bushes and boulder clusters at forest edges and riverbanks
- props around buildings
- a grass pass
