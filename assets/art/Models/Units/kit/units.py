"""Unit recipes: which parts make each figure, and its palette.

A recipe takes a LOD (0 near, 1 far) and whether the figure stands on its
tabletop base, and returns the merged bmesh. Parts that need another part's
surface (a strap on the tunic, a face on the head) are handed it.

Bases are off for now (the figure stands on the ground, feet at the origin);
build.py's --base brings them back.

Every Aldmere figure follows the Soldier's rules: plain steel headgear in a
shape of its own (kettle hat, morion, nasal helm, sallet) so the unit type
reads from the game camera, the team's colour on the body (the tunic, or a
tabard over it: parts.TEAM_BODY), the shield's face and the hem (and the
cloth a unit is known by: the Lord's cape, the officer's standard, a
knight's caparison).
"""
from mathutils import Matrix, Vector

import clothes
import dark_elf
import gear
import geo
import gnoll
import headgear
import horse
import hyena
import parts
import poses


def _head(b, lod, on_head, hair="hair"):
	"""The head, its face and hair, and what it wears, tipped back together."""
	head = parts.head(b, lod)
	pieces = [head, parts.face(b, lod, head)]
	if hair:
		pieces.append(parts.hair(b, lod, hair))
	pieces += on_head
	for piece in pieces:
		geo.transform(piece, b.head_matrix())
	return pieces


def _team_body(b, lod, back=True):
	"""The tabard (back=False: an apron) when the team's colour is on one."""
	return [clothes.tabard(b, lod, back=back)] if parts.TEAM_BODY == "tabard" else []


def _armoured(b, lod, torso, mail=True, pauldrons=("leather", "leather_dark"), strap=True):
	"""A soldier's body: boots, gambeson and skirt, belt, sword strap, mail
	collar, shoulder guards and arms."""
	pieces = [parts.boots(b, lod), parts.legs(b, lod), torso, parts.skirt(b, lod)] + _team_body(b, lod) 			+ [parts.belt(b, lod)]
	if strap:
		pieces.append(parts.baldric(b, lod, torso))
	pieces.append(parts.collar(b, lod) if mail else clothes.cloth_collar(b, lod))
	if pauldrons:
		pieces.append(parts.pauldrons(b, lod, *pauldrons))
	pieces.append(parts.arms(b, lod))
	return pieces


## Swords are drawn larger than life, scaled round the fist, so they read
## from the game camera.
SWORD_SCALE = 1.45


def _sword(b, lod):
	return gear.grow(parts.arming_sword(b, lod), b.r_fist, SWORD_SCALE)


def _assemble(b, pieces, lod, base):
	"""Merges `pieces`, on the base, or (without one) dropped onto the ground."""
	bm = geo.new_bm()
	for piece in pieces:
		geo.merge(bm, piece)
	if base:
		geo.merge(bm, parts.base(b, lod))
	else:
		geo.translate(bm, (0.0, 0.0, -b.base_height))
	return bm


# --- foot -------------------------------------------------------------------

def soldier(lod, base=False):
	"""The Aldmere swordsman: kettle helmet, gambeson, sword and round shield."""
	b = parts.Body()
	torso = parts.tunic(b, lod)
	head = parts.head(b, lod)
	on_head = [head, parts.face(b, lod, head), parts.hair(b, lod), parts.kettle_helmet(b, lod)]
	for piece in on_head:
		geo.transform(piece, b.head_matrix())
	pieces = on_head + [
		parts.boots(b, lod), parts.legs(b, lod), torso, parts.skirt(b, lod)] + _team_body(b, lod) + [parts.belt(b, lod),
		parts.baldric(b, lod, torso), parts.collar(b, lod), parts.pauldrons(b, lod), parts.arms(b, lod),
		_sword(b, lod), parts.round_shield(b, lod),
	]
	if lod == 0:
		pieces += [parts.scabbard(b, lod), parts.pouch(b, lod)]
	return _assemble(b, pieces, lod, base)


def spearman(lod, base=False):
	"""Levy spearman: a crested morion, a spear stood upright taller than him."""
	b = poses.polearm(parts.Body())
	torso = parts.tunic(b, lod)
	pieces = _head(b, lod, [headgear.morion(b, lod)]) + _armoured(b, lod, torso, strap=False)
	pieces.append(gear.spear(b, lod, length=1.46, radius=0.026, head=2.3))
	if lod == 0:
		pieces.append(parts.pouch(b, lod))
	return _assemble(b, pieces, lod, base)


def halberdier(lod, base=False):
	"""Halberdier: a tall bell-shaped barbute and a halberd, its axe turned out."""
	b = poses.polearm(parts.Body())
	torso = parts.tunic(b, lod)
	pieces = _head(b, lod, [headgear.barbute(b, lod)]) + _armoured(b, lod, torso, strap=False)
	pieces.append(gear.halberd(b, lod))
	if lod == 0:
		pieces.append(parts.pouch(b, lod))
	return _assemble(b, pieces, lod, base)


def shieldman(lod, base=False):
	"""Shieldman: a tall pointed nasal helm behind a tall heater shield."""
	b = poses.tower_shield(parts.Body())
	torso = parts.tunic(b, lod)
	pieces = _head(b, lod, [headgear.nasal_helm(b, lod)]) + _armoured(b, lod, torso)
	pieces += [_sword(b, lod), gear.tower_shield(b, lod, w=0.34, h=0.54)]
	if lod == 0:
		pieces.append(parts.scabbard(b, lod))
	return _assemble(b, pieces, lod, base)


def archer(lod, base=False):
	"""Archer: an undyed russet hood and capelet, a longbow, a quiver."""
	b = poses.bow(parts.Body())
	torso = parts.tunic(b, lod)
	pieces = _head(b, lod, [headgear.hood(b, lod, "hood", "leather_dark")]) + _armoured(b, lod, torso, mail=False, pauldrons=None)
	pieces += [gear.longbow(b, lod), gear.quiver(b, lod)]
	if lod == 0:
		pieces.append(parts.pouch(b, lod))
	return _assemble(b, pieces, lod, base)


def crossbowman(lod, base=False):
	"""Crossbowman: a combed, peaked burgonet, a crossbow levelled at the waist, a bolt case."""
	b = poses.crossbow(parts.Body())
	torso = parts.tunic(b, lod)
	pieces = _head(b, lod, [headgear.burgonet(b, lod)]) + _armoured(b, lod, torso, strap=False)
	pieces += [gear.crossbow(b, lod), gear.bolt_case(b, lod)]
	return _assemble(b, pieces, lod, base)


def officer(lod, base=False):
	"""Officer: a plumed armet with its beaked visor raised, a sword, and his
	regiment's standard on his back."""
	b = poses.sword_only(parts.Body())
	torso = parts.tunic(b, lod)
	plume = headgear.plume(b, lod, b.brow_z + 0.150)
	geo.translate(plume, (0.0, 0.05, 0.0))
	pieces = _head(b, lod, [headgear.armet(b, lod), plume]) + _armoured(b, lod, torso)
	pieces += [_sword(b, lod), gear.back_banner(b, lod)]
	if lod == 0:
		pieces.append(parts.scabbard(b, lod))
	return _assemble(b, pieces, lod, base)


def lord(lod, base=False):
	"""The Lord: a gold crown, a short dark beard, a long cape in the team's
	colour with an ermine collar, gold trim, a sword."""
	b = poses.sword_only(parts.Body())
	torso = parts.tunic(b, lod)
	on_head = [headgear.hair_cap(b, lod, "hair_dark"), headgear.crown(b, lod),
			headgear.beard(b, lod, long=False, row_name="hair_dark")]
	pieces = _head(b, lod, on_head, hair="hair_dark")
	pieces += _armoured(b, lod, torso, pauldrons=None)
	pieces += [clothes.cape(b, lod), clothes.surcoat_trim(b, lod), _sword(b, lod)]
	if lod == 0:
		pieces.append(parts.scabbard(b, lod))
	return _assemble(b, pieces, lod, base)


def wizard(lod, base=False):
	"""Wizard: a wide pointed hat in the team's colour, a long white beard,
	an undyed robe, a gnarled staff holding a crystal."""
	b = poses.staff(parts.Body())
	on_head = [headgear.wizard_hat(b, lod), headgear.beard(b, lod)]
	pieces = _head(b, lod, on_head, hair="beard")
	pieces += [clothes.robe(b, lod), clothes.wide_sleeves(b, lod), gear.wizard_staff(b, lod)]
	return _assemble(b, pieces, lod, base)


def arch_mage(lod, base=False):
	"""Arch Mage: a hood and capelet in the team's colour, a white robe
	banded in gold, a white beard, a gilded crescent staff."""
	b = poses.staff(parts.Body())
	on_head = [headgear.hood(b, lod), headgear.beard(b, lod)]
	pieces = _head(b, lod, on_head, hair="beard")
	pieces += [clothes.robe(b, lod, cloth="robe"), clothes.robe_trim(b, lod), clothes.wide_sleeves(b, lod, "robe"),
			gear.arch_staff(b, lod)]
	return _assemble(b, pieces, lod, base)


## Villagers' tools are drawn larger than life, scaled round the hand that
## holds them, so they read from the game camera.
TOOL_SCALE = 1.4
BASKET_SCALE = 1.3


def _villager(lod, base, held):
	b = (poses.basket if held == "basket" else poses.tool)(parts.Body())
	torso = parts.tunic(b, lod)
	pieces = _head(b, lod, [headgear.cloth_cap(b, lod)])
	pieces += [parts.boots(b, lod), parts.legs(b, lod), torso] + _team_body(b, lod, back=False)
	pieces += [parts.belt(b, lod), clothes.cloth_collar(b, lod),
			parts.arms(b, lod), parts.pouch(b, lod)]
	tool = getattr(gear, held)(b, lod)
	fist, factor = (b.l_fist, BASKET_SCALE) if held == "basket" else (b.r_fist, TOOL_SCALE)
	geo.transform(tool, Matrix.Translation(fist) @ Matrix.Scale(factor, 4) @ Matrix.Translation(-fist))
	pieces.append(tool)
	return _assemble(b, pieces, lod, base)


def villager(lod, base=False):
	"""Villager gathering food: an undyed cloth cap, a basket."""
	return _villager(lod, base, "basket")


def villager_build(lod, base=False):
	return _villager(lod, base, "hammer")


def villager_wood(lod, base=False):
	return _villager(lod, base, "axe")


def villager_gold(lod, base=False):
	return _villager(lod, base, "pick")


# --- gnolls -----------------------------------------------------------------

def _gnoll_head(b, lod, on_head=(), war_paint=False):
	"""The hyena head: muzzle, eyes, big ears, the mane ridge and spots,
	tipped back together (war_paint: the berserk's red mane and stripes)."""
	head = gnoll.head(b, lod)
	pieces = [head, gnoll.face(b, lod, head), gnoll.muzzle(b, lod), gnoll.ears(b, lod),
			gnoll.mane(b, lod, head, "warpaint" if war_paint else "fur_dark"), gnoll.head_spots(b, lod, head)]
	if war_paint:
		pieces.append(gnoll.war_paint(b, lod, head))
	pieces += list(on_head)
	for piece in pieces:
		geo.transform(piece, b.head_matrix())
	return pieces


def _gnoll_body(b, lod):
	"""Fur and a hide kilt, the team's loincloth, belt, necklace, arms, tail."""
	torso = gnoll.torso(b, lod)
	return [gnoll.legs(b, lod), torso, gnoll.body_spots(b, lod, torso), gnoll.strap(b, lod, torso),
			gnoll.loincloth(b, lod), gnoll.belt(b, lod),
			gnoll.necklace(b, lod), gnoll.arms(b, lod), gnoll.tail(b, lod)]


def gnoll_warrior(lod, base=False):
	"""Gnoll Warrior: a bone-studded club, a round hide shield, a horned
	hide pad on the club shoulder."""
	b = parts.Body()
	pieces = _gnoll_head(b, lod) + _gnoll_body(b, lod)
	pieces += [gnoll.shoulder_pad(b, lod), gnoll.bone_club(b, lod), gnoll.hide_shield(b, lod)]
	return _assemble(b, pieces, lod, base)


def gnoll_archer(lod, base=False):
	"""Gnoll Archer: a feathered hide headband, a bow held out, a quiver."""
	b = poses.bow(parts.Body())
	pieces = _gnoll_head(b, lod, [gnoll.feather_band(b, lod)]) + _gnoll_body(b, lod)
	pieces += [gnoll.crude_bow(b, lod), gear.quiver(b, lod)]
	return _assemble(b, pieces, lod, base)


def gnoll_berserk(lod, base=False):
	"""Gnoll Berserk: red war paint and mane, a great double-bitted axe,
	a pale pelt and horned skull on the left shoulder, no shield."""
	b = poses.sword_only(parts.Body())
	pieces = _gnoll_head(b, lod, war_paint=True) + _gnoll_body(b, lod)
	pieces += [gnoll.skull_pelt(b, lod), gnoll.great_axe(b, lod)]
	return _assemble(b, pieces, lod, base)


## The Leader stands this much taller than the rest of the pack.
LEADER_SCALE = 1.15


def gnoll_leader(lod, base=False):
	"""Gnoll Leader: bigger, russet-furred, a crown of bone tusks, horned
	pads on both shoulders, trophy skulls at the belt and two huge
	cleaver-swords raised."""
	b = parts.Body()
	b.l_elbow = Vector((-b.r_elbow.x, b.r_elbow.y, b.r_elbow.z))
	b.l_wrist = Vector((-b.r_wrist.x, b.r_wrist.y, b.r_wrist.z))
	b.l_fist = Vector((-b.r_fist.x, b.r_fist.y, b.r_fist.z))
	l_axis = Vector((-b.sword_axis.x, b.sword_axis.y, b.sword_axis.z))
	pieces = _gnoll_head(b, lod, [gnoll.tusk_crown(b, lod)]) + _gnoll_body(b, lod)
	for piece in pieces:
		gnoll.recolour(piece, "fur", "fur_red")
	pieces += [gnoll.shoulder_pad(b, lod), gnoll.shoulder_pad(b, lod, side=1.0), gnoll.belt_skulls(b, lod),
			gnoll.falchion(b, lod, b.r_fist, b.sword_axis, size=1.25),
			gnoll.falchion(b, lod, b.l_fist, l_axis, size=1.05)]
	bm = _assemble(b, pieces, lod, base)
	geo.scale(bm, LEADER_SCALE, LEADER_SCALE, LEADER_SCALE)
	return bm


def gnoll_shaman(lod, base=False):
	"""Gnoll Shaman: a dark indigo robe hemmed blood-red, the team's
	loincloth over it, and a staff crowned with a horned skull, red
	feathers and hanging charms."""
	b = poses.staff(parts.Body())
	pieces = _gnoll_head(b, lod)
	sleeves = clothes.wide_sleeves(b, lod, "robe_dark")
	gnoll.recolour(sleeves, "skin", "fur_dark")
	pieces += [clothes.robe(b, lod, cloth="robe_dark", hem="warpaint"), gnoll.loincloth(b, lod, out=0.018),
			gnoll.necklace(b, lod), sleeves, gnoll.tail(b, lod), gnoll.skull_staff(b, lod)]
	return _assemble(b, pieces, lod, base)


def hyena_beast(lod, base=False):
	"""Hyena: a chibi spotted hyena on four legs, the gnolls' head on a
	sloped back, a mane ridge and a short bushy tail, a collar of the
	team's colour."""
	b = parts.Body()
	return _assemble(b, [hyena.hyena(b, lod)], lod, base)


# --- dark elves -------------------------------------------------------------

def _dark_elf_head(b, lod, on_head):
	"""The human head and face in lilac-grey skin, white hair falling long
	down the back, long pointed ears, and what it wears, tipped back."""
	return _head(b, lod, [dark_elf.ears(b, lod), dark_elf.long_hair(b, lod)] + list(on_head))


def dark_elf_warrior(lod, base=False):
	"""Dark Elf Warrior: a black-violet half helm with a blade crest and
	silver horns, spiked pauldrons, the team's tabard, a huge curved sword
	with a violet rune and a tall pointed shield in the team's colour."""
	b = parts.Body()
	torso = parts.tunic(b, lod)
	pieces = _dark_elf_head(b, lod, [dark_elf.spiked_helm(b, lod)])
	pieces += [parts.boots(b, lod), parts.legs(b, lod), torso, parts.skirt(b, lod)] + _team_body(b, lod)
	pieces += [parts.belt(b, lod), dark_elf.gorget(b, lod), dark_elf.spiked_pauldrons(b, lod), parts.arms(b, lod),
			dark_elf.curved_blade(b, lod), dark_elf.spiked_shield(b, lod)]
	return _assemble(b, pieces, lod, base)


def dark_elf_archer(lod, base=False):
	"""Dark Elf Archer: a black-violet hood and capelet over a dark face
	mask, the team's tabard, a big black recurve bow with silver blade
	tips and a nocked venom-green arrow, a quiver of violet fletching."""
	b = poses.bow(parts.Body())
	torso = parts.tunic(b, lod)
	pieces = _head(b, lod, [dark_elf.ears(b, lod), dark_elf.face_mask(b, lod),
			headgear.hood(b, lod, "plate_dark", "lining")])
	pieces += [parts.boots(b, lod), parts.legs(b, lod), torso, parts.skirt(b, lod)] + _team_body(b, lod)
	pieces += [parts.belt(b, lod), parts.arms(b, lod), dark_elf.recurve_bow(b, lod),
			gnoll.recolour(gear.quiver(b, lod), "fletch", "arcane")]
	return _assemble(b, pieces, lod, base)


def dark_elf_assassin(lod, base=False):
	"""Dark Elf Assassin: bareheaded, white hair in a high silver-ringed
	topknot, a face mask and waist sash in the team's colour, a sash over
	the shoulder, two big curved fang daggers raised, venom-green grooved."""
	b = parts.Body()
	b.l_elbow = Vector((-b.r_elbow.x, b.r_elbow.y, b.r_elbow.z))
	b.l_wrist = Vector((-b.r_wrist.x, b.r_wrist.y, b.r_wrist.z))
	b.l_fist = Vector((-b.r_fist.x, b.r_fist.y, b.r_fist.z))
	l_axis = Vector((0.30, -0.55, 0.78)).normalized()
	torso = parts.tunic(b, lod)
	on_head = [headgear.hair_cap(b, 1), dark_elf.topknot(b, lod), dark_elf.ears(b, lod),
			dark_elf.face_mask(b, lod, "team_cloth")]
	pieces = _head(b, lod, on_head)
	pieces += [parts.boots(b, lod), parts.legs(b, lod), torso, parts.skirt(b, lod),
			gnoll.recolour(parts.baldric(b, lod, torso), "leather", "team_cloth"), dark_elf.waist_sash(b, lod),
			parts.arms(b, lod), dark_elf.fang_dagger(b, lod, b.r_fist, b.sword_axis, size=1.25),
			dark_elf.fang_dagger(b, lod, b.l_fist, l_axis, size=1.1)]
	return _assemble(b, pieces, lod, base)


def dark_elf_guard(lod, base=False):
	"""Dark Elf Guard: a hood and capelet in the team's colour, a gorget and
	spiked pauldrons, the team's tabard, a tall glaive with a huge swept
	silver blade and a spike-rimmed round shield."""
	b = poses.polearm(parts.Body())
	for joint in ("l_elbow", "l_wrist", "l_fist"):
		setattr(b, joint, getattr(parts.Body, joint).copy())
	torso = parts.tunic(b, lod)
	pieces = _dark_elf_head(b, lod, [headgear.hood(b, lod, "team_cloth", "lining")])
	pieces += [parts.boots(b, lod), parts.legs(b, lod), torso, parts.skirt(b, lod)] + _team_body(b, lod)
	pieces += [parts.belt(b, lod), dark_elf.gorget(b, lod), dark_elf.spiked_pauldrons(b, lod), parts.arms(b, lod),
			dark_elf.glaive(b, lod), dark_elf.spiked_round_shield(b, lod)]
	return _assemble(b, pieces, lod, base)


# --- mounted ----------------------------------------------------------------

## How far a rider's standing-space figure is raised to sit in the saddle.
RIDER_LIFT = Vector((0.0, 0.0, 0.050 + horse.SEAT + 0.005 - 0.175))


def _rider(b, lod, on_head, weapon, pauldrons):
	torso = parts.tunic(b, lod)
	pieces = _head(b, lod, on_head)
	pieces += [torso] + _team_body(b, lod) + [parts.belt(b, lod), parts.collar(b, lod), parts.pauldrons(b, lod, *pauldrons),
			parts.arms(b, lod), weapon]
	for piece in pieces:
		geo.translate(piece, RIDER_LIFT)
	for joint in ("l_fist", "l_wrist", "l_elbow", "r_fist", "r_wrist", "r_elbow"):
		setattr(b, joint, getattr(b, joint) + RIDER_LIFT)
	return pieces


def horseman(lod, base=False):
	"""Horseman: a rider in a sallet with an upright pennoned lance on a
	bay horse with a saddle cloth in the team's colour."""
	b = poses.rider_lance(parts.Body())
	pieces = _rider(b, lod, [headgear.sallet(b, lod)], gear.lance(b, lod), ("leather", "leather_dark"))
	pieces += [horse.horse(b, lod), horse.tack(b, lod), horse.reins(b, lod), horse.rider_legs(b, lod)]
	return _assemble(b, pieces, lod, base)


def cavalier(lod, base=False):
	"""Cavalier: a knight in a plumed great helm and a couched lance on a
	grey horse in a caparison of the team's colour and a steel chanfron."""
	b = poses.rider_couched(parts.Body())
	on_head = [headgear.great_helm(b, lod), headgear.plume(b, lod, b.brow_z + 0.140, lean=1.3, height=0.20)]
	weapon = gear.lance(b, lod, length=1.70, below=0.50, pennant=False, side_hint=(0.0, 0.0, 1.0))
	pieces = _rider(b, lod, on_head, weapon, ("steel", "trim"))
	pieces += [horse.horse(b, lod, coat="coat_grey", coat_dark="pebble"), horse.caparison(b, lod),
			horse.chanfron(b, lod), horse.reins(b, lod), horse.rider_legs(b, lod)]
	return _assemble(b, pieces, lod, base)


def dark_elf_rider(lod, base=False):
	"""Dark Elf Rider: a spiked half helm with a venom-green plume, a
	couched black lance with a silver head and the team's pennant, on a dark
	charcoal horse with a crest of silver-blue spines, a spiked black
	chanfron and the team's saddle cloth."""
	b = poses.rider_couched(parts.Body())
	plume = gnoll.recolour(headgear.plume(b, lod, b.brow_z + 0.170, lean=1.3, height=0.22), "team_cloth", "crystal")
	on_head = [dark_elf.ears(b, lod), dark_elf.long_hair(b, lod), dark_elf.spiked_helm(b, lod)]
	weapon = gnoll.recolour(gear.lance(b, lod, length=1.70, below=0.50, side_hint=(0.0, 0.0, 1.0)), "wood_light",
			"plate_dark")
	pieces = _rider(b, lod, on_head, weapon, ("plate_dark", "trim"))
	geo.translate(plume, RIDER_LIFT)
	g = b.base_height
	chanfron = gnoll.recolour(horse.chanfron(b, lod), "steel", "plate_dark")
	pieces += [plume, horse.horse(b, lod), horse.tack(b, lod), chanfron, dark_elf.mount_spines(lod, g),
			horse.reins(b, lod), horse.rider_legs(b, lod)]
	return _assemble(b, pieces, lod, base)


## `portrait`: the point the portrait camera looks at (the head, in the
## exported figure's space) and how far back it stands.
_FOOT = {"palette": "aldmere", "portrait": (0.0, 0.0, 0.62), "portrait_distance": 1.25}
_GNOLL = dict(_FOOT, palette="gnolls", portrait=(0.0, -0.03, 0.64))
_DARK_ELF = dict(_FOOT, palette="dark_elves")
_MOUNTED = {"palette": "aldmere", "portrait": (0.0, -0.05, 1.10), "portrait_distance": 1.6, "mounted": True}
## `ready`: built by default. The rest are recipes in progress (written,
## not yet reviewed or exported): build one by name to work on it.
UNITS = {
	"Soldier": dict(_FOOT, build=soldier, ready=True),
	"Villager": dict(_FOOT, build=villager, ready=True),
	"Villager_build": dict(_FOOT, build=villager_build, portrait=None, ready=True),
	"Villager_wood": dict(_FOOT, build=villager_wood, portrait=None, ready=True),
	"Villager_gold": dict(_FOOT, build=villager_gold, portrait=None, ready=True),
	"Archer": dict(_FOOT, build=archer, ready=True),
	"Spearman": dict(_FOOT, build=spearman, ready=True),
	"Halberdier": dict(_FOOT, build=halberdier, ready=True),
	"Shieldman": dict(_FOOT, build=shieldman, ready=True),
	"Crossbowman": dict(_FOOT, build=crossbowman, ready=True),
	"Officer": dict(_FOOT, build=officer, ready=True),
	"Lord": dict(_FOOT, build=lord, ready=True),
	"Wizard": dict(_FOOT, build=wizard, portrait=(0.0, 0.0, 0.66), portrait_distance=1.45, ready=True),
	"ArchMage": dict(_FOOT, build=arch_mage, ready=True),
	"GnollWarrior": dict(_GNOLL, build=gnoll_warrior, ready=True),
	"GnollArcher": dict(_GNOLL, build=gnoll_archer, ready=True),
	"GnollBerserk": dict(_GNOLL, build=gnoll_berserk, ready=True),
	"GnollLeader": dict(_GNOLL, build=gnoll_leader, portrait=(0.0, -0.03, 0.74), portrait_distance=1.4, ready=True),
	"GnollShaman": dict(_GNOLL, build=gnoll_shaman, ready=True),
	"Hyena": dict(_GNOLL, build=hyena_beast, portrait=(0.0, -0.33, 0.52), portrait_distance=1.3, mounted=True,
			ready=True),
	"DarkElfWarrior": dict(_DARK_ELF, build=dark_elf_warrior, ready=True),
	"DarkElfArcher": dict(_DARK_ELF, build=dark_elf_archer, ready=True),
	"DarkElfAssassin": dict(_DARK_ELF, build=dark_elf_assassin, ready=True),
	"DarkElfGuard": dict(_DARK_ELF, build=dark_elf_guard, ready=True),
	"DarkElfRider": dict(_MOUNTED, palette="dark_elves", build=dark_elf_rider, ready=True),
	"Horseman": dict(_MOUNTED, build=horseman, ready=True),
	"Cavalier": dict(_MOUNTED, build=cavalier, ready=True),
}
