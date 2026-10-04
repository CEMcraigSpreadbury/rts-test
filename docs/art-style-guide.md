# Art style guide

How Crowns of Aldmere should look, and the rules that keep new art consistent
with it. Read this before adding a building, tree, prop, ground effect or icon,
or before tuning lighting. Each rule names the file and value that implement it,
so you can find it in the code.

## The look in one line

Chunky low-poly buildings and trees with a thin ink silhouette, outlined
pixel-art units, and painterly ground in calm broad colour, all under clear
midday light.

The two target images are in `docs/art-reference/`:

| Image | What it is for |
|---|---|
| `reference-close.png` | The overall look: buildings, trees, outlines, rocks and flowers, close up. |
| `reference-grass.png` | The grass and ground in particular: colour blending, tufts, shadows. |

Both are painted close-ups. Players mostly see the game from further out, at
the gameplay starting zoom of 22 or wider, so always judge art at that distance
too. Ask how the reference would look from that far away, not how it looks
close up.

## Pillars

1. **Calm ground, busy objects.** Grass and dirt are mostly flat, softly
   blended colour. Detail and contrast belong to buildings, trees, units and
   shadows. If the ground starts to look like camouflage, noise or carpet,
   there is too much going on in it.
2. **One ink line, around the outside.** 3D objects get a thin dark outline
   around their silhouette as the camera sees it, and nowhere else.
3. **Units stay pixel art.** Units are outlined pixel sprites. There will be
   no 3D units.
4. **Bright midday.** The look is judged at midday (`--tod=0.3`): clean light,
   no haze, no bloom.

## Palette

Values are what a screenshot of the reference measures at midday, as sRGB
0-255. Use them to check a change rather than to pick colours by eye.

| Surface | Target | Notes |
|---|---|---|
| Sunlit grass | about (135-160, 185-200, 78-82) | Fresh yellow-green, never lime or neon. |
| Grass in shade | about (70, 112-126, 59-77) | Cool, slightly teal green. Never near-black olive. |
| Dirt | muted mid-brown | Three flat tones, not a gradient (see Ground). |
| Plaster walls | off-white, lit side about 220-240 | Never pure white, never yellow cream. |
| Roofs | the team colour, mid value | Value x0.72, saturation x0.88 (`team_color.gdshaderinc`). |
| Rocks | warm mid-grey, about 0.37-0.46 | `GroundScatter.ROCK_COLOURS`. |
| Ink line | (0.17, 0.10, 0.06) | A very dark warm brown, not black. |

Grass colour comes from the gradient on each map's terrain and foliage
materials: `(0.59, 0.75, 0.39) / (0.53, 0.71, 0.36) / (0.45, 0.65, 0.32)`. All
three maps use the same values; keep them in step.

## Outlines

Implemented in `shaders/post/outline.gdshader`, a full-screen pass added to the
camera by `OutlinePass`.

- **Silhouette only.** Each outlined object writes its own id
  (`shaders/util/outline_mark.gdshaderinc`). A line is drawn only where the
  object meets something else, so there are no lines on roof tiles, creases or
  inner edges. A building shares one id across all its meshes; trees, rocks and
  deposits take one from their position.
- **Thin, and thinner further away.** 1.6 px at 1080p, thinning to 1 px and
  fading to 35% strength past view depth 30.
- **Not where things touch the ground.** Against terrain or grass, the line
  appears only where the object rises more than 0.1-0.3 m above the ground
  beside it. Roof edges against the field behind are lined; the feet of walls,
  trunks and rocks are not.
- **What gets one:** buildings, trees, gold deposits and rocks. Grass, terrain,
  pebbles, flowers and units never do.
- **To outline a new object:** its material writes stencil 2 and an outline id
  into ROUGHNESS. For shader materials, copy the `stencil_mode write,
  compare_always, 2;` line and the `v_outline_roughness` varying from
  `team_color.gdshader`. For a `StandardMaterial3D`, call `OutlinePass.mark()`.
  Stencil 1 is already taken by the unit silhouette system, so don't use it.

## Ground

### Grass

Terrain colour is in `shaders/terrain/binbun_terrain.gdshader` and the 3D grass
blades are in `binbun_foliage.gdshader`. Both share
`shaders/terrain/grass_clumps.gdshaderinc`.

- **Broad, smooth colour blending.** `grass_patches()` blends between a deeper,
  cooler green and a warm sunlit green over areas about 30 m across. Never
  threshold or posterise it; hard edges read as camouflage.
- **No darker dabs or patches.** Painting darker clump shapes into the grass
  was tried several times, and every time it looked like blotches or stamped
  ovals. Grass may be lightened in places, never darkened in patches. The only
  dark areas on grass are real shadows.
- **Blades:** three times wider than the Binbun default, but low
  (`blade_scale_range` 1.2-2.4, `blade_height` 0.45), so units stand clear of
  the grass. Each blade takes the ground colour at its root and lightens and
  warms towards its tip (`tip_light`, up to x1.16).
- **Hard-cut alpha.** Blades use `alpha_mode = 1`. Dithered alpha crawls when
  the camera moves.
- **Stable randomness.** Anything random per blade, such as size, rotation,
  texture or offset, must be seeded from a whole-number cell index, never a
  world position. The grass grid follows the camera, so position-seeded values
  re-roll every frame and the grass jitters.
- **Grass off must look right too.** The web build and the Grass option show
  the bare terrain without blades. Check every grass change with
  `--grass` and with `--nograss`.

### Dirt

- Three flat painted tones rather than a gradient, with fine dark grit and
  sparse pebbles (`dirt_albedo()` in `binbun_terrain.gdshader`).
- A ragged edge where grass overlaps the dirt. It stays in the narrow band
  along the edge; out in open grass it stamps ovals.
- Under a cloud, dirt darkens to a neutral brown, not blue-grey.

### Scatter

`scripts/ground_scatter.gd` places scatter from each map's splatmap when the
map loads.

- **Rocks:** sparse (1 per 80 m²), outlined, warm grey.
- **Daisies:** white or yellow with yellow centres, small loose clusters
  (1 per 12 m²). They always face the camera, so they never read as slivers.
- **Pebbles:** on paths and on dirt under buildings only, with no outline.
- **No static 3D grass tufts.** They don't move with the wind and look out of
  place.
- Anything under a building or field is hidden by the ground stamp texture.

## Light and shadow

The environment is in `scenes/map_base.tscn`.

- **Clear air:** volumetric fog density 0, glow off, ACES tonemap at exposure
  0.8, saturation 1.03 and contrast 1.08.
- **Cloud shadows:** on the ground, clouds block the sun inside the ground's
  own lighting (`ground_light()` in
  `shaders/terrain/ground_light.gdshaderinc`) instead of darkening it a second
  time. A cloud and a tree shadow on the same spot look the same as either
  alone, and clouds stay hidden under fog of war. Other objects still darken
  through the cloud decal (`scripts/cloud_shadows.gd`).
- **Shade fill:** where the sun is blocked, the ground gets a soft cool fill
  (`GROUND_SHADOW_FILL`), so shade reads teal-green rather than black.
- **Ambient occlusion** (screen-space): radius 1.0, intensity 6, power 2,
  detail 0. It darkens where buildings, trunks and rocks meet the ground.
  - The terrain applies it to direct sunlight too (`AO_LIGHT_AFFECT`): full
    strength on bare dirt, a quarter under grass. Grass blades get none, or
    they fill with dark holes up close.
  - Buildings are drawn half as baked emission and half as ambient-lit colour,
    so ambient occlusion can darken their wall feet and corners
    (`LIT_SHARE` in `team_color.gdshaderinc`).
  - The split is balanced against the map's ambient colour (`AMBIENT_REF`).
    **If you change `ambient_light_color` or `ambient_light_energy` in
    `map_base.tscn`, change `AMBIENT_REF` to match**, or building colours will
    drift.
  - Players can turn ambient occlusion off (Options > Visuals). The game must
    look right without it as well.
- **Depth of field stays.** The tilt-shift blur is a deliberate choice.

## Buildings and trees

- Use the team colour shader (`team_color.gdshader`), which recolours only the
  team-blue parts of the texture. Lit plaster is softened toward off-white
  (`soften_highlights()`), and walls darken slightly toward their foot.
- Tree models and their shading are fixed. Trees get outlines and shadows; the
  models themselves are not restyled.
- New building models should match the existing chunky, low-poly, hand-painted
  look of the Town Centre.

## Units

- Outlined pixel sprites, using the "Outline" versions of the Minifolks
  sheets. Unoutlined sprites were tried and rejected.
- No blob shadows under units.
- A unit on the field shows as its sprite: in the portrait, the selection tray,
  regiment cards and banners. A unit offered as a command shows its icon: on
  training buttons, in queue slots and on Lord tabs.

## Icons and UI

- Every command button shows a glyph from game-icons.net, with a small hotkey
  letter in the corner. Glyph SVGs are in `assets/ui/glyphs/`, and
  `SOURCES.txt` lists each one's author and icon name.
- To add one: download the SVG, strip its background square, give it a width
  and height of 512, add a "keep" `.import` file, list it in `SOURCES.txt`,
  and add a new author to the credits if needed.
- Painted, ComfyUI-generated and model-rendered icons were all rejected for
  buttons.

## Checking a change

Use the screenshot tool (`scenes/tools/ui_shot.tscn`). Its flags are
documented at the top of `scripts/tools/ui_shot.gd`. For any art change, take
at least:

```
-- --realm --plate --art --tod=0.3 --zoom=22 --grass   # gameplay distance
-- --realm --plate --art --tod=0.3 --zoom=50 --grass   # zoomed out
-- --realm --plate --art --tod=0.3 --zoom=10 --grass   # close up
-- --realm --plate --art --tod=0.3 --nograss            # grass option off / web
```

Then check:

- the ground at 50 still reads as calm colour, not noise;
- nothing jitters or crawls while the camera pans (play it, don't just
  screenshot it);
- fog of war still hides everything unexplored;
- night (`--tod=0.85`) still reads;
- the web look, using desktop `--rendering-method gl_compatibility`. The web
  build has no outlines, ambient occlusion, cloud decal or grass, and has its
  own lighting in `scripts/compat_lighting.gd`.

## Tried and rejected

These have all been tried. Don't bring them back without a new reason.

- 3D units, unoutlined unit sprites, blob shadows under units.
- Painted, AI-generated or model-rendered button icons.
- Thick or black outlines, outlines on roof tiles and creases, outlines where
  objects meet the ground.
- Darker clump dabs or tuft patches in the grass, in any form.
- Many rocks, static 3D grass tufts.
- Blades with dark roots (they read as fur), dithered blade alpha,
  position-seeded blade randomness.
- Teal or green cloud-shadow colour on everything; cloud shadows stacking with
  sun shadows.
- A painted "contact shade" decal under buildings. Use real ambient occlusion
  instead.
- Hazy grading: volumetric fog, bloom, sky reflections on the ground (they
  wash the far grass out).
