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
  - Each race has its own module: `gnoll.py`, `hyena.py`, `dark_elf.py`,
    `beastmen.py`, `star_wanderers.py`. Bestiary beasts are in `beasts.py`
    (on their race's palette). Monsters are in `monsters.py` (palette
    `monsters`, with team rows). Siege engines are in `siege.py` (palette
    `siege`: Aldmere's rows plus `plate_dark` blackened iron and `arcane`
    rune glow; see `palette.SIEGE`), their Soldier crewman added in
    `units.py`.
    Horses are in `horse.py`, wild animals in `animals.py` (palette
    `animals`, its own image, no team rows).
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
    (0 melee, 1 bow/caster, 2 mounted/quadruped, 3 stomp for monsters,
    4 roll for siege engines) and
    `figure_top` (the health bar height).
  - **Stomp** (`figure_motion` 3, monsters): each cycle lifts, travels and
    lands with a squash, then pauses on the ground; strike and death as
    mounted. The unit still moves at a steady speed, so the figure is drawn
    off the unit along its velocity (behind during the pause, ahead as it
    lands) and never slides; the selection ring and health bar follow the
    unit. Tune `kStomp*` in `figure_batcher.cpp` (stomps a second, air
    share, height, squash). On each landing in view the batcher emits
    `stomped(position)` (the nearest one a frame); `Main._on_figure_stomped`
    calls the camera's `shake_at` (frustum check, keeps the strongest jolt,
    no stacking), tuned by `STOMP_SHAKE` (0.4), `STOMP_SHAKE_NEAR` /
    `STOMP_SHAKE_FAR` (18 / 45 m from the camera) in `main.gd`.
  - **Roll** (`figure_motion` 4, siege engines): no hop, sway or breath; a
    small quick rumble while moving (bob, nose rock, side sway); the
    sprite's attack lunge is ignored and the figure kicks back 0.3 m nose
    up on the shot's release frame, easing home over the rest of the clip;
    on death it tips over on its side (1.2 rad, lifted 0.55 m). Tune
    `kRoll*` in `figure_batcher.cpp`. A unit drawn as a figure hides its
    crew sprite (`Unit._attach_crew_drawing`): the crew is on the model.
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
- **Beastmen: every unit is its own creature.** Start from the unit's
  sprite for the animal, but push it: a different species and a different
  body per unit (lanky, squat, hunched, long-snouted, big-eared, antlered,
  tusked), with its own silhouette and stance, so each reads apart at game
  distance and never as a Gnoll (no Gnoll body proportions). Keep the
  shared eye style and chibi charm. Each animal gets a `parts.Body`
  subclass in `beastmen.py` (`BoarBody`, `StagBody`, `PandaBody`,
  `WolfBody`) and a species repaint (`beastmen.BOAR`, `STAG`, `PANDA`,
  `WOLF`) onto palette rows the Beastmen do not otherwise
  use (see the note on `palette.BEASTMEN`). Team colour may go on an extra
  sash, scarf or strap wherever the loincloth is hidden from the camera.
  Beastmen steel is neutral grey, never blue.

- **Star Wanderers: sky-blue celestials.** Every unit shares the race head
  (`star_wanderers.head`, `fins`, `star_face`): bald, a taller dome, two tall
  fins swept up from the crown with cyan tips, a cyan four-pointed star on
  the brow, white star freckles under the shared eyes. Materials: pearl
  porcelain plate (`steel`) over a midnight-indigo suit (`plate_dark`), bright
  gold (`brass`, `trim`), and glowing gear in three star colours: cyan
  (`crystal`), violet moon (`arcane`), sun gold (`fruit`, repurposed; see
  `palette.STAR_WANDERERS`). Shapes are crescents, stars, rings and things
  that float. Team colour is on cloth: scarf, loincloth, stole, hem. Each
  unit has its own `Body` subclass. Plan for the rest:
  - Spearman: lanky and long-limbed, narrow chest, a tall crescent-bladed
    spear and a small star buckler, a team cape.
  - Hunter: light, low and crouched forward, a visor of cyan crystal over
    the eyes, a crystal crossbow levelled, a team hood-scarf.
  - Knight: tall, armoured head to toe in porcelain, a crested helm that
    keeps the fins, a long violet crystal sword and a gold kite shield
    with a team face.
  - Paladin: the biggest, very broad and heavy-set, a huge gold star
    hammer, a team tabard, a small halo of floating stars.
  - Rider: on a comet fox (`star_wanderers.steed`), the rider light, the
    saddle cloth in team colour. The mount's head is drawn big, high and
    well forward so it reads from the front (the fix for the Dark Elf
    Rider's hidden horse). Its coat, mane and ruff repaint the `coat`,
    `coat_dark` and `mane` rows, which no other Star Wanderer uses.

- **Size: big things are MUCH bigger.** Monsters (`scenes/units/monsters`)
  and siege units (Ballista, Magic Cannon) must be much bigger than normal
  units: they tower over infantry. Beasts (`scenes/units/beasts`, the race
  Bestiary units) are large creatures too, clearly bigger than cavalry.
  Rough targets (the Soldier is about 0.9 m to the helmet, a Horseman about
  1.35 m to the helmet and 1.0 m long): beasts 1.6 to 2.0 m tall and long,
  monsters and siege engines 2.5 m and up (monsters about 3.5 to 4 m; see
  the Monsters scale target under Roster status).
- **Beasts** (`kit/beasts.py`) are race units: each carries the team's
  colour on its harness (saddle cloth, collar, banner), readable from the
  game camera, and is built on its race's palette. Shared eye style where
  they have faces; chunky, strong silhouettes. Bestiary pairs: Aldmere
  Griffin and Manticore, Gnolls Sand Worm and Skeleton Dragon, Dark Elves
  Kitsune and Wind Tiger, Star Wanderers Dragon and Lightning Dragon. The
  Beastmen have none.

## Size: what controls how big a figure is

- **The model, and only the model.** FigureBatcher draws the mesh at the
  unit's transform times the pose, in the kit's metres. Build a big figure
  at its real size in the kit: design it at about a horse's scale and grow
  it round the ground under its middle (`beasts._grow` with a `*_SCALE`,
  as `animals.BEAR_SCALE` does).
- **The scene's Sprite scale does not size the figure.** The pose only
  reads the sprite's scale and position *relative to their values at
  `_ready`* (squash, lunge, hop), so the 1.3 to 1.5 sprite scales and raised
  sprite offsets in the beast scenes have no effect on the figure. One
  consequence: Realm elites (`main.gd` multiplies `sprite.scale` by
  `RealmRoster.ELITE_SCALE` after `_ready`) draw their figure 1.15x too.
- **`figure_top`** only places the health bar and stun stars (default: the
  mesh's top). Set it to the head, not to a raised wing or banner tip.
- **Selection ring** (`Unit._figure_ring_for`): radius from the mesh's
  footprint, 0.45 x the larger of width and length + 0.13, clamped to
  0.405..3.0 m (`FIGURE_RING_MAX`; was 1.5, raised for monsters, which
  also lifts the Manticore off the old cap).
- **Clicking** (native `type_for`): the pick radius is 0.35 x the
  footprint, at least 0.3 m, at most 0.5 m or 0.3 x the footprint, whichever
  is bigger (never over 2.5 m), round the unit's centre line up to the
  mesh's height. Anything up to a 1.67 m footprint (every man and horse)
  keeps the old 0.5 m cap; the Black Dragon (4.7 m) gets about 1.4 m. A click on a
  wing tip still misses (the pick is a cylinder, not the mesh); the
  nearest-to-axis rule keeps small units in front of it clickable.
- **Bodies don't grow (deferred):** movement, separation and the navmesh
  all use `UNIT_BODY_RADIUS` 0.4 m for every unit, so big figures overlap
  their neighbours in a crowd. Gameplay range/aggro are separate scene
  values. Plan, not built: the sim already stores a radius per unit
  (`army_bridge.register_unit` passes `UNIT_BODY_RADIUS` to
  `sim.add_unit`), but separation uses a fixed `kSeparationDistance` 0.85 m
  and formation spacing, and the navmesh/nav grid has one clearance for
  everyone. Steps: (1) a `body_radius` scene export (0 = default),
  passed to `add_unit`; (2) separation by the pair's radii
  (`r_a + r_b + gap`) with a spatial-hash query radius of the largest body;
  (3) monsters keep the 0.4 m nav clearance (they squeeze through gaps; the
  figure clips scenery) unless a second, wider nav grid is worth it;
  (4) melee reach measured edge to edge (target radius added to
  `attack_range`) so attackers stand round a monster, not inside it;
  (5) formations: a monster stays loose (a formation of 1).
- **LOD and shadow:** LOD1 swaps in beyond 20 m from the camera, times
  the figure's height / 2 m when that is over 1 (the Black Dragon, 3.8 m,
  keeps its near mesh to 38 m). The shadow is still cast from the LOD1
  mesh. Culling tests a sphere round the figure's middle as big as the
  furthest corner of its bounds (at least 1 m; shadows that plus twice its
  height, at least 5 m), so a big figure no longer pops at the screen edge
  (native `Type::view_radius`, `shadow_radius`, `lod_scale`). Men and
  horses keep the old 1 m / 5 m / 20 m.
- **No flight:** nothing in the game flies. Griffins and dragons walk on
  the ground; a raised sprite offset (Lightning Dragon) is only for its
  sprite cell. A flying figure would need a lift in the pose (native).
- **Line-ups:** `build.py --lineup` gives each figure a slot at least its
  own width, puts the red row behind the deepest figure and frames the
  tallest. Line a big figure up with `Soldier Horseman` for scale.

## Roster status

Done and in game:

- **Aldmere:** Soldier, Villager (with build, wood and gold variants), Archer,
  Spearman, Shieldman, Halberdier, Crossbowman, Officer, Lord, Wizard,
  Arch Mage, Horseman, Cavalier.
- **Gnolls:** Warrior, Archer, Berserk, Leader, Shaman, Hyena.
- **Dark Elves:** Warrior, Archer, Assassin, Guard, Rider, Sorceress (spire
  crown, robe, venom-green orb staff), Spellstealer (crescent-horn circlet,
  tall collar, violet ringed orb, crescent-hook wand). The last two await
  the user's review.
- **Beastmen:** Warrior (brown bear: round ears, tan muzzle, steel bracers
  and one spiked steel pauldron, dark bandolier, team loincloth and a team
  sash round the belly, a huge bearded crescent axe; approved, then the
  steel made neutral grey and the sash added). Raider (boar: squat, wide
  and hunched, slate-grey bristle, a black crest from brow to hump,
  curling tusks, a brass snout ring, a team scarf streaming from the nape,
  a huge broad scimitar thrust forward). Druid (stag: tall, slender and
  long-legged, golden fawn, a long neck, big level ears, great pale
  antlers, a knee-length moss robe with a leaf mantle, a wide team sash
  and a deep team hem band, a vine-wound crook staff over a jade orb with
  team ribbons tied under it (so team colour reads from the game camera); the robe's palette row was
  narrowed and its leaf-green trim cut to a thin ring over the hem, so it
  no longer reads as stripes). Panda Warrior (a huge round heavyweight: a
  white ball on short black pillar legs set wide, painted as a real panda:
  black arms running into one black band over the shoulders and upper
  back, a white chest, throat and belly; black ears and teardrop eye
  patches, a broad woven-straw jingasa war hat with dark leather trim, the team's wide obi and
  loincloth, a gong shield in the team's colour with a brass rim and
  swirl, an upright guandao with a team tassel). Wolf Pathfinder (lean
  and rangy: long digitigrade legs, a strong forward lean with the head
  thrust out, a broad wedge skull, a heavy dark brow, a thick snout
  tapering from a wide base over a heavy cream jaw, tall pointed ears, cream cheek tufts, a long
  bushy tail with a cream tip, a leather jerkin, the team's dagged
  shoulder mantle with its hood thrown back, the team loincloth, a
  crossbow levelled and a bolt quiver at the hip; bow motion). Raider,
  Druid, Panda Warrior and Wolf Pathfinder await the user's review.
- **Star Wanderers:** Warrior (athletic and top-heavy: porcelain cuirass
  with a cyan star, gold-rimmed porcelain pauldrons, a chunky team scarf
  with tails streaming back, a team loincloth, a huge crescent blade in
  each low fist, a gold sun crescent with rays and a violet moon crescent
  with a star gem, convex edges down). Priestess (tall, slender and
  floating: a white robe hovering over a cyan crystal point, a wide team
  hem under a gold ring, a team stole down the front ending in gold stars,
  a porcelain mantle cut in gold star points, a gold star crown and a gold
  halo behind the head, a gold staff with a violet orb in a ring of star
  points; bow/caster motion). Hunter (light, low and crouched forward on
  wide bent legs, the body leaning in, a cyan crystal visor across the eyes
  (the eyes sit on the glass), the team's deep hood drawn up with the fins
  standing through it, a thick team scarf with a tail streaming back, small
  porcelain pauldrons, a team front flap, a crystal crossbow levelled: a
  violet moon crescent for a prod, a glowing cyan bolt and string, a cyan
  quiver; bow motion). Spearman (lanky: long thin legs with porcelain knee
  guards, a narrow midnight suit under a porcelain gorget, a long team
  tabard to the knees and a long team cape, a tall porcelain spear with a
  gold moon crescent under a violet crystal point, a small gold buckler
  under a big violet star). The Warrior's loincloth now stands off the
  suit's hem flare, which had poked through it as a dark spot. Knight
  (tall and straight-sided, porcelain head to toe: long armoured legs with
  knee cops, a crested helm open over the face with the fins standing
  through it and an arched team crest from brow to nape, a gold keel and
  cyan star on the cuirass, big porcelain pauldrons, a full team surcoat
  skirt under a gold belt, a long violet crystal sword raised out to the
  right with a gold crescent guard, a tall gold kite shield with a team
  face and a cyan star). Paladin (the biggest: a huge porcelain barrel on
  short thick legs set wide on big boots, the head sunk between huge gold
  pauldrons, the fins swept out sideways like horns, a long white beard, a
  broad team tabard down the front, a floating ring of gold and cyan stars
  over the head, a huge gold star hammer stood upright: violet five-point
  stars on its faces, a violet band and a cyan spike). Then a second pass on
  the Paladin: a gold star lantern with cyan glass hung from the left
  hand, and a new tabard (`paladin_tabard`) that falls in soft folds
  below the belt, is lined and edged all round in a rolled gold border
  that gives it thickness, with a gold star and a cyan heart on its
  skirt. Rider (light: a porcelain gorget, gold pauldrons, the team's
  scarf and front flap, an upright crescent spear with a swallow-tailed
  team pennant; on a comet fox: a pale silver-lavender fox-deer (royal blue until
  the blue team's saddle cloth vanished on it) with star specks,
  a big head held high and forward, tall ears lined in cyan, a cyan
  crystal horn over a gold star, a white ruff, cheeks and fetlocks,
  crystal hooves, a comet tail ending in a cyan flame under a floating
  star, a porcelain peytral with a cyan star, and the team's saddle cloth
  over each flank, dagged in three points with a gold edge and a gold
  star; mounted motion). The Star Wanderers are complete. All seven await
  the user's review.
- **Wild animals** (neutral, no gear, no team colour, mounted motion):
  Bear (a heavy dark-chocolate barrel on short thick pillar legs, a
  shoulder hump, a huge round head held low and forward, round ears, a tan
  muzzle, bone claws, drawn 1.12x). Boar (small and wedge-shaped: high
  shoulders, a low rump, a black bristle crest from crown to mid-back, a
  long snout with a pink disc, white tusks curling up, pointed ears, thin
  legs on black trotters). Deer (a slender russet roe buck on long legs,
  neck and head held high, wide level ears with dark rims, short
  three-tined antlers, cream muzzle, throat, belly and rump). All three
  await the user's review. Fox and Wolf are deferred.
- **Beasts:** Griffin (Aldmere: an eagle-headed lion 1.85 m tall, wings
  raised over its back in tawny coverts and brown flight feathers, white
  feathered head, neck and chest ruff, a big hooked golden beak, swept-back
  ear tufts, yellow eagle forelegs with dark talons, tawny lion haunches and
  a tufted tail; the team's saddle cloth with a brass edge and dags, a
  leather saddle, the team's breast collar with a brass boss; drawn 1.8x).
  Sand Worm (Gnolls: a fat sandy worm rearing from its own coil, ringed
  with dark creases, a round head bent forward with a heavy brow, the
  shared eyes and a pink-lipped maw ringed with bone teeth, bone spikes
  down its back, the team's collar with ochre beads, a tall gnoll war
  banner in the team's colour with a horned skull lashed to its back;
  drawn 2.0x). Manticore (Aldmere: a low, prowling russet-orange lion with a
  round, near-human chibi face in a huge spiky dark amber mane, ivory ram
  horns, fanged grin, half-spread charcoal bat wings with dusky violet
  membranes leaning back to face the game camera (the wine-red mane and
  membranes read as red team colour, so they were moved off red; the wings
  were tilted toward the sky and the span cut from 3.3 to 3.0 m), a black segmented scorpion tail arched over the back
  to a bulb and an ivory stinger; the team's saddle cloth with a brass edge
  and two team wraps round the tail; drawn 1.75x). Kitsune (Dark Elves: a
  slender silver-white fox on long legs in black-violet socks, tall ears
  lined in black-violet, white cheek tufts and ruff, violet markings, a
  silver circlet with a violet gem, a fan of seven fat silver tails with
  white tips each ending in a violet foxfire flame, three wisps floating
  over the head; the team's collar, a team chest bib with a silver bell
  and a team saddle cloth edged in silver; drawn 1.6x). The Griffin's wings
  were rebuilt in layers (tapered primaries fanned from the wrist,
  secondaries, two rows of round-tipped coverts) so they no longer read as
  planks. All four on mounted motion and seen in game once (selection
  rings fit; the stage landed on a cliff edge, see open points). All four
  await the user's review.
  Wind Tiger (Dark Elves: a heavy, low ivory-white tiger 1.8 m tall and
  2.7 m long with its tail, black stripes laid over the back and flanks,
  dark leg bands and a ringed tail, a big round head with white cheek
  ruffs, whisker pads and dark-backed cat ears; the wind in mint: gusts
  streaming back off the shoulders and haunches ending in curls, swirls
  round the paws and a vortex at the tail tip; the team's collar with a
  silver crescent and a long team scarf streaming back over each shoulder,
  a team saddle cloth edged in silver under a black-violet saddle with a
  violet gem; drawn 1.95x). Skeleton Dragon, the Bestiary drake (Gnolls;
  GLB `SkeletonDragonBeast`, kept apart from the bigger monster to come: a
  vertebra spine with dorsal spikes, an open rib cage round a green soul
  fire, bone legs with knobbed joints and dark claws, a long horned skull
  with green sparks in dark sockets and ochre war paint, torn grey hide
  wings raised high; the team's blanket with an ochre edge and dags under a
  hide saddle with a bone cantle, team rags tied to the horns, a bone and
  ochre bead necklace, a horned skull trophy at the flank; 1.93 m tall,
  drawn 1.75x). Both on mounted motion, seen in game once; await review.
  New palette rows: Dark Elves beard, beard_dark and tuft (coat, stripes,
  wind), Gnolls mane and crystal (wing hide, soul fire), Aldmere tuft
  (membranes).
  Dragon (Star Wanderers, `beasts.sun_dragon`: a heavy four-legged sun
  dragon in saffron-gold scales, an ivory belly, chest and neck scutes,
  a big round head with an ivory jaw, porcelain horns tipped in gold,
  amber cheek fins, a cyan star on the brow and a floating gold sun ring
  behind the horns; porcelain spikes down the neck, back and tail, the
  tail curling round on the ground to a gold eight-point sun; raised
  wings of midnight-indigo membrane on gold bones, specked with gold
  stars; the team's saddle cloth edged in gold under a porcelain saddle
  with a cyan star, the team's collar with a gold sun medallion; 1.9 m
  tall, drawn 1.8x). Lightning Dragon (Star Wanderers,
  `beasts.lightning_dragon`: a long eastern serpent in pale storm blue
  (kept greyer than the blue team), its tail lying on the ground and its
  body rising in an S, an ivory belly strip, navy fins alternating with
  cyan lightning-bolt fins down the back, a pearl tail plume round a cyan
  bolt, short legs with gold claws, the front pair clutching a cyan pearl
  crackling with bolts; a long head drawn 1.25x with a navy brow, branching
  gold antlers, pearl cheek manes and long whiskers curling back to cyan
  tips, a cyan brow star; three team bands between gold rings (neck,
  rising body, coil) and a team scarf knotted at the neck with two tails
  streaming back, a gold star on each; about 1.9 m tall, drawn 1.9x).
  Both on mounted motion, seen in game once; await review. New Star
  Wanderers rows: fur, fur_dark, fur_light, bone, beard, beard_dark.
  The beasts are complete. All eight await the user's review.
- **Monsters** (`kit/monsters.py`, palette `monsters`): trained at the
  neutral Shrine by any race, so owned: each wears its owner's team
  colour on a harness, on one shared palette with team rows (Gnoll rows
  repainted freely; see `palette.MONSTERS`). Scale target (revised after
  the user found 3.0x "a bit too big"): about 2x a beast, 3.5 to 4 m tall,
  grown by about 2.35 (`*_SCALE`) from a horse-scale design; set
  `figure_top` to the head; `figure_motion` 3 (stomp). Black Dragon (4.2 m
  wide with its wings, 4.7 m long, 3.8 m tall, drawn 2.35x): a hulking charcoal dragon
  reared on thick planted forelegs, chest high, neck curving up to a big
  horned head held forward on a long wedge snout; a molten ember chest
  plate, throat and belly scutes and an ember glow in its half-open maw,
  ivory fangs, heavy black brows in an angry frown (inner ends low), a crown of four ivory horns; huge raised
  bat wings in a dark oxblood membrane (kept deep so it never reads as the
  red team); a long tail low along the ground to a black spade; black
  spikes neck to tail; the team's saddle cloth edged in iron under a dark
  iron saddle, the team's collar with an iron ring, team rags knotted on
  the great horns. Stomp motion, `figure_top` 3.3. Awaits review of the
  new size, brows, stomp and shake.
  Hydra (3.9 m wide, 4.1 m tall, drawn 2.35x): a squat sea-teal body (kept
  bluer and deeper than the green team) low on four short pillar legs, a
  tan belly and chest, a fat tail curling low behind with dark ridge
  plates; five long necks fanning up and out from the shoulders like an
  open hand (0, +-31, +-62 degrees; the middle head highest, the outer pair
  lowest), tan throat scutes, each head drawn 1.22x (round skull, blunt
  snout, tan jaw, fangs, dark angry brows, the shared eyes) under a crown
  of three gold crest fins facing the front; the team's band round every
  neck between gold rims, the team's saddle cloth edged in gold. Stomp
  motion (a squat, heavy, low walker), `figure_top` 3.8.
  Skeleton Dragon, the monster (4.3 m wide, 4.7 m long, 4.1 m tall, drawn
  2.35x; GLB `SkeletonDragon`, the Bestiary drake is `SkeletonDragonBeast`
  at 1.9 m): reared like the Black Dragon on thick knobbed bone legs with
  black claws, a heavy vertebra spine with tall dorsal blades, a deep rib
  cage round a big jade soul fire with flames rising, a massive skull with
  angry bone brows, jade fire in dark sockets trailing back, a jade glow in
  open toothed jaws, a crown of great horns, lower horns, cheek spurs and a
  spiked frill; huge torn bat wings in dark slate hide; a vertebra tail to
  a bone blade. The team's caparison (tilted with the back, steel edge,
  ragged tatters), a ragged team war banner on a bone pole with a bone
  crossbar on the pelvis, the team's collar with an iron ring, team rags
  on the great horns. Stomp motion (a heavy reared walker, like the Black
  Dragon), `figure_top` 3.3. Both seen in game once (rings 1.96 and
  2.23 m; stomps fire); await review. New monsters rows: fur, fur_dark,
  fur_light (hydra), crystal (jade soul fire, off the green team's lime),
  mane (slate wing hide).
  Giant Bear (1.8 m wide, 3.4 m long, 4.1 m to the banner tip, drawn
  2.35x; GLB `GiantBear`): a colossal chestnut war-bear on all fours (the
  wild Bear is a small dark-chocolate one, the Beastman Warrior an upright
  bear with an axe), a huge roaring head drawn 1.12x held low and forward
  under a dark iron war cap with a spike, angry dark brows, a cream muzzle
  and lowered jaw with ivory fangs, rust claw-stripe war paint on the
  shoulders, two iron plates over each shoulder, an iron chain slung across
  the chest. The team's caparison (steel edge) carries a wooden war-howdah
  with iron bands and iron-capped corner posts, a round team shield on each
  side and a tall team war banner at its back; the team's breast collar.
  `figure_top` 2.7 (above the howdah walls). Yeti (3.7 m wide, 3.6 m tall,
  drawn 2.35x): a towering hunched white ape on short legs, huge shoulder
  mounds crusted with pale ice crystals, a blue-grey face, fists and feet
  (slate, kept greyer than the blue team), angry slate brows, a roaring
  underbite with ivory tusks, a crest of white shag points; the left fist
  knuckling the ground, the right dragging a mammoth-bone club with a
  frozen boulder head bristling with ice spikes; icicles off the arms and
  shoulders. The team's fur-wrap kilt under a dark belt with dagged flaps,
  a wide team sash across the chest, a team rag on the club. `figure_top`
  3.3. Both stomp motion; seen in game once (rings 1.68 and 1.78 m; stomps
  fire); await review. New monsters rows: beard, beard_dark, cream,
  warpaint (bear), hair, skin, hair_dark, arcane (yeti). Near/LOD1
  triangles: Giant Bear 4.1k/2.1k, Yeti 3.5k/1.7k; the Hydra (6.4k) and
  Skeleton Dragon (6.7k) were trimmed from 7.9k (fewer neck, spine and
  knob segments).
  Giant Bear brows fixed (2026-10-08): the tilted ellipsoid sat half
  inside the skull, so only its outer half showed and read as sad brows;
  brows are now a flattened bar (`monsters._brow`) from a low inner end on
  the muzzle bridge up to a high outer end. Use `_brow` for new faces.
  Orc Mutant (3.5 m wide, 4.1 m to the banner skull, drawn 2.35x): a
  hunched, lopsided olive-grey brute (kept dull so it is not the green
  team) on short thick legs; a huge swollen right shoulder and arm of raw
  mauve flesh stitched on (black stitch seam), bone spikes bursting out,
  sickly bile pustules, an iron wrist cuff; the big fist holds a door-sized
  iron cleaver across the front (chipped bright edge down, rust stains, a
  hole by the spine); the small left arm has a spiked iron pauldron and a
  manacle with a broken chain, an iron chain across the chest, a shackle on
  the left ankle. Underbite with tusks, pig nose, angry dark brows, one
  great bone horn out of the right of the skull and a broken stub on the
  left, a stitched scar, an ear ring. The team's loincloth and a tattered
  team banner on a pole strapped to the back with a horned skull on top.
  `figure_top` 3.1. Dark Lord (3.0 m wide, 4.0 m tall, drawn 2.35x): a
  towering sorcerer-king in black-violet plate edged in gold, layered
  spiked pauldrons, a horned helm (black horns, gold tips) with a gold
  spiked crown, a dark T-visor with glowing violet eyes under gold angry
  brows; a runed greatsword held point-down (bright edges, a violet rune
  channel, a gold spiked guard), violet sorcery in the raised left hand.
  The team's huge cape to the ground (lined a darker team shade), a team
  mantle over the shoulders, the team's tabard with a gold-and-violet
  sigil. Both stomp motion: a 4 m figure on the melee hop (3.3 hops a
  second, 7.5 cm) would jitter, while the stomp gives the weight and the
  camera shake. Seen in game once (rings 1.69 and 1.5 m; stomps fire);
  await review. New monsters rows: hood, hoof, ochre, fruit, string (orc),
  plate_dark (darker), gem (violet glow). Near/LOD1 triangles: Orc Mutant
  4.5k/2.3k, Dark Lord 3.9k/2.4k.
  Phoenix (3.9 m wide, 4.2 m to the wing tips, 3.9 m long, drawn 2.35x):
  a great fire bird standing tall on long charcoal legs bent back at the
  ankle, ivory talons; flame-orange plumage over an amber breast; huge
  raised wings of flame-tongue feathers (orange primaries and secondaries,
  amber coverts, white-hot lesser coverts at the root, deep ember brown
  undersides); a long trailing flame tail low along the ground (a broad
  orange streamer curling up at its end, two amber streamers fanned out, a
  white-hot core, ember wisps); a hooked bronze beak open in a screech,
  the shared eyes under dark angry brows, amber cheek tufts, a crest of
  flame tongues; white-hot embers off its back. Kept on orange, amber and
  white-hot (no red, no lemon yellow) so it never reads as a team. Team
  colour: the collar with an iron boss, a swallow-tailed pennant on an iron
  bar down the breast, jesses with ribbons on both shins. `figure_top`
  3.4. Stomp motion: a big ground bird moves in heavy two-footed hops, and
  the stomp's lift, land-with-squash and pause reads as exactly that (the
  melee hop would jitter a 4 m figure). Seen in game once (ring 2.03 m;
  stomps fire); await review. New monsters rows: robe (flame orange),
  robe_trim (amber), ermine (white-hot), robe_dark (ember brown), fletch
  (bronze beak). Near/LOD1 triangles 4.2k/2.3k.
  Fixes (2026-10-08): the Dark Lord's violet chest gem was buried in the
  torso and now sits proud of it; the Orc Mutant's mutated flesh (`ochre`)
  is darker and greyer so it reads less pink.

- **Siege** (`kit/siege.py`, palette `siege`, roll motion, built at their
  size and grown by `SIEGE_SCALE` 1.15). Ballista (3.6 m wide across the
  bow, 5.0 m long with its bolt and crewman, 3.1 m to the pennant tip,
  rail at about 2 m): a long wooden chassis on three small iron-tyred
  wheels a side (brass hubs, spoke ribs), the team's painted side boards
  and front with brass trim and corner caps, a turret drum, a long
  iron-banded stock tilted up, a bow frame with two rope torsion skeins and
  great blue-steel arms swept back to brass tips, the string drawn to the
  nock, an oversized bolt (pale shaft, big steel head, the team's
  fletching), a winch with cranks at the back and a tall swallow-tailed
  team pennant. Magic Cannon (2.5 m wide, 4.4 m long, 2.8 m to the
  crystal): two huge iron-tyred spoked wheels, the team's painted carriage
  cheeks edged in brass, a trail to the ground, a fat brass barrel raised
  10 degrees with its breech half in the team's paint, two glowing mint
  rune rings, rune marks and a glowing bore, and a big cyan crystal core
  in a brass cage on the breech with two floating shards. Each has the
  Soldier (the crew sprite is the swordsman) standing at its rear left.
  `figure_top` 2.3 / 2.6. Near/LOD1 triangles 8.2k/3.5k and 6.3k/2.7k.
  Seen in game once (rings 2.39 and 2.09 m, the ballista's widened by its
  bolt and crewman; crew sprites hidden; the ballista fired); await review.

Next, in this order:

1. Beastmen: review of Raider, Druid, Panda Warrior and Wolf Pathfinder.
2. Star Wanderers: review of all seven.
3. Beasts: review of all eight (complete).
4. Monsters (`scenes/units/monsters`): all eight done (Black Dragon,
   Hydra, Skeleton Dragon, Giant Bear, Yeti, Orc Mutant, Dark Lord,
   Phoenix; await review). Then per-unit body radius (plan under Size).
5. Siege: Ballista and Magic Cannon done (await review). The roster is
   complete apart from the deferred animals.
6. Wild animals Fox and Wolf (deferred).
7. Per-unit body radius (plan under Size): monsters and siege engines
   overlap their neighbours and each other.
8. Portraits: the selection panel, tray, regiment cards and banners still
   show sprites. `build.py --portraits` is written but has never been run.

Known open points:

- The longbow and the Dark Elf Rider's black lance read thin.
- The Dark Elf Rider's horse is mostly hidden behind the rider from the front.
- Wild boars read very small in game next to villagers; they may want
  scaling up after review.
- The fix that makes attackers face their target (`Unit._land_swing` snaps
  the yaw) has not yet been checked in a real melee.
- The Manticore's wingspan (3.0 m) still makes its selection ring hit the
  1.5 m cap.
- The beasts stage (scratchpad `stage/beasts_stage.gd`) now picks a flat
  block with no building within 14 m, fells any tree within 12 m and hides
  the ground scatter under the line, for the shot only.
- From the game camera the Lightning Dragon reads smaller and paler than
  the other beasts, and its team bands are thin; it may want a thicker
  body or wider bands after review.
- Monsters: the Black Dragon's pick is a 1.4 m cylinder round its middle,
  so a click on a wing tip misses. Its 0.4 m body lets units stand inside
  it. Its shadow is cast from LOD1. An edge-cull check (its middle 2 m
  past the screen's side) still drew one near figure, which can only be
  the dragon (the rest were past their LOD range), but the check that
  hid it to compare was not clean (fog of war re-shows units); look at
  the screen edge in game.
- Stomp: the selection ring and health bar move steadily with the unit
  while the figure pauses, so the ring drifts under a pausing dragon by up
  to about 0.3 m. Pulsing the sim's speed would fix it but was not done.
- Monsters: the Skeleton Dragon's war banner sits mostly behind its wings
  from the front and the game camera (team colour still reads on its
  horn rags, collar and caparison). The Hydra's outer heads reach 1.9 m
  from its centre, so its 0.4 m body and pick cylinder leave them
  unclickable.
- Siege: the crewman is part of the machine's mesh, so he tips over with
  it and adds to its footprint (the ballista's ring is 2.39 m, near the
  monsters'). The ballista's near mesh (8.2k triangles, mostly its six
  wheels) is the heaviest figure; trim the wheels if it matters. Two
  engines side by side overlap (0.4 m bodies). The recoil was only seen as
  a still in game; check it moving.
- Mages have no real staff raise. Their attack borrows the bow motion.

## Materials

- Every figure is drawn with `shaders/unit_figure.gdshader` (built per type by
  `scripts/figure_materials.gd`, set as the batcher's material override for
  near, LOD1 and shadow batches); the GLBs' own materials are never used.
- Finish comes from the shine vertex colour (`COLOR.g`, `kit/figure.py`
  `SHINE` table). Rows missing from that table (fur, skin, cloth, hide, coat,
  wood) are shine 0, which used to mean roughness 0.5 and a thin 0.25 clear
  coat, so fur-and-cloth figures (the Wolf Pathfinder) read matte.
- Now shine 0 is already glossy plastic (roughness 0.3, clear coat 0.5, soft
  rim); shine only tightens the glint toward 0.17 and adds a little metallic on
  steel and gold. Tune via the uniforms `plastic_roughness`,
  `metal_roughness`, `metal_metallic`, `rim_amount`, `clearcoat_amount`.
  Wetness and cloud shading still apply on top. Shader-only, no GLB rebuild.

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
