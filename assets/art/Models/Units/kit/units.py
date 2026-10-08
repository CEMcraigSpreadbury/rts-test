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

import animals
import beasts
import beastmen
import clothes
import dark_elf
import gear
import geo
import gnoll
import headgear
import horse
import hyena
import monsters
import parts
import poses
import siege
import star_wanderers


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


def dark_elf_sorceress(lod, base=False):
	"""Dark Elf Sorceress: a crown of five tall silver-edged black spires
	over long white hair, a black-violet robe with the team's colour at the
	hem and down its front, a pointed gorget, a tall black staff whose
	silver claws hold a big venom-green orb."""
	b = poses.staff(parts.Body())
	pieces = _dark_elf_head(b, lod, [headgear.hair_cap(b, 1), dark_elf.thorn_tiara(b, lod)])
	pieces += [clothes.robe(b, lod, cloth="cloth"), clothes.robe_trim(b, lod, "team_cloth"),
			clothes.wide_sleeves(b, lod, "cloth"), dark_elf.gorget(b, lod), dark_elf.venom_staff(b, lod)]
	return _assemble(b, pieces, lod, base)


def dark_elf_spellstealer(lod, base=False):
	"""Dark Elf Spellstealer: a silver circlet with great crescent horns, a
	tall flared black collar lined in violet, the team's tabard, a big
	violet orb of stolen magic cupped in silver claws and ringed in silver
	on the raised left palm, a silver crescent-hook wand in the right."""
	b = parts.Body()
	staff_pose = poses.staff(parts.Body())
	for joint in ("l_elbow", "l_wrist", "l_fist"):
		setattr(b, joint, getattr(staff_pose, joint).copy())
	torso = parts.tunic(b, lod)
	pieces = _dark_elf_head(b, lod, [headgear.hair_cap(b, 1), dark_elf.crescent_circlet(b, lod)])
	pieces += [parts.boots(b, lod), parts.legs(b, lod), torso, parts.skirt(b, lod)] + _team_body(b, lod)
	pieces += [parts.belt(b, lod), dark_elf.high_collar(b, lod), parts.arms(b, lod), dark_elf.siphon_orb(b, lod),
			dark_elf.hook_wand(b, lod)]
	return _assemble(b, pieces, lod, base)


# --- beastmen ---------------------------------------------------------------

def _beast_head(b, lod, on_head=()):
	"""The bear head: muzzle, eyes and round ears, tipped back together."""
	head = beastmen.head(b, lod)
	pieces = [head, beastmen.face(b, lod, head), beastmen.muzzle(b, lod), beastmen.ears(b, lod)] + list(on_head)
	for piece in pieces:
		geo.transform(piece, b.head_matrix())
	return pieces


def beastman_warrior(lod, base=False):
	"""Beastman Warrior: a brown bear with a tan muzzle, a dark
	leather bandolier, steel bracers and one big spiked steel pauldron, the
	team's loincloth, and a huge bearded crescent axe raised."""
	b = poses.sword_only(parts.Body())
	torso = beastmen.torso(b, lod)
	arms = gnoll.recolour(gnoll.arms(b, lod), "leather", "steel")
	pieces = _beast_head(b, lod)
	pieces += [gnoll.legs(b, lod), torso, beastmen.bandolier(b, lod, torso),
			gnoll.loincloth(b, lod), gnoll.recolour(gnoll.belt(b, lod), "bone", "steel"), beastmen.stub_tail(b, lod),
			arms, beastmen.shoulder(b, lod), beastmen.pauldron(b, lod), beastmen.bear_axe(b, lod),
			beastmen.sash(b, lod, grow=1.04)]
	return _assemble(b, pieces, lod, base)


def _tilt(b, pieces):
	for piece in pieces:
		geo.transform(piece, b.head_matrix())
	return pieces


def beastman_raider(lod, base=False):
	"""Beastman Raider: a squat, wide, hunched boar in slate-grey bristle,
	a black crest from brow to hump, curling tusks and a brass snout ring,
	the team's scarf streaming from the nape and its loincloth, and a huge
	broad scimitar thrust forward."""
	b = beastmen.BoarBody()
	torso = beastmen.boar_torso(b, lod)
	head = beastmen.boar_head(b, lod)
	pieces = _tilt(b, [head, beastmen.face(b, lod, head, eye_x=0.090, eye_dz=0.040, blush_x=0.140),
			beastmen.boar_snout(b, lod), beastmen.boar_ears(b, lod), beastmen.boar_head_crest(b, lod)])
	pieces += [beastmen.boar_legs(b, lod), torso, beastmen.boar_back_crest(b, lod, torso), gnoll.loincloth(b, lod),
			gnoll.belt(b, lod), beastmen.arms(b, lod, k=1.18)]
	for piece in pieces:
		beastmen.species(piece, beastmen.BOAR)
	pieces += [beastmen.neckerchief(b, lod), beastmen.scimitar(b, lod, size=1.12)]
	return _assemble(b, pieces, lod, base)


def beastman_druid(lod, base=False):
	"""Beastman Druid: a tall, slender, long-legged stag in golden fawn,
	big level ears and great pale antlers, a knee-length moss robe with a
	leaf mantle, the team's sash across it and at the leaf-cut hem, and a
	vine-wound crook staff curling over a glowing jade orb."""
	b = beastmen.StagBody()
	robe = beastmen.stag_robe(b, lod)
	head = beastmen.stag_head(b, lod)
	pieces = _tilt(b, [head, beastmen.face(b, lod, head, eye_x=0.068, eye_dz=0.022, blush_x=0.104),
			beastmen.stag_muzzle(b, lod), beastmen.stag_ears(b, lod), beastmen.fawn_spots(b, lod, head),
			beastmen.antlers(b, lod)])
	sleeves = gnoll.recolour(clothes.wide_sleeves(b, lod, "robe"), "skin", "fur_dark")
	pieces += [beastmen.stag_legs(b, lod), beastmen.stag_neck(b, lod), sleeves]
	for piece in pieces:
		beastmen.species(piece, beastmen.STAG)
	pieces += [robe, gnoll.belt(b, lod), beastmen.strap(b, lod, robe, width=0.064), beastmen.leaf_collar(b, lod),
			beastmen.druid_staff(b, lod)]
	return _assemble(b, pieces, lod, base)


def beastman_panda_warrior(lod, base=False):
	"""Beastman Panda Warrior: a huge round heavyweight panda, a white
	ball with black legs, arms, shoulder yoke, ears and eye patches, under a broad
	steel war hat; the team's wide obi and loincloth, a gong shield in the
	team's colour on the left arm and a long guandao stood upright, its
	tassel in the team's colour."""
	b = beastmen.PandaBody()
	torso = beastmen.panda_torso(b, lod)
	head = beastmen.panda_head(b, lod)
	pieces = _tilt(b, [head, beastmen.panda_face(b, lod, head), beastmen.panda_muzzle(b, lod),
			beastmen.panda_ears(b, lod), beastmen.jingasa(b, lod)])
	arms = gnoll.recolour(beastmen.arms(b, lod, k=1.26, bracer="fur"), "fur", "fur_dark")
	pieces += [beastmen.panda_legs(b, lod), torso, beastmen.panda_tail(b, lod), arms]
	for piece in pieces:
		beastmen.species(piece, beastmen.PANDA)
	w = b.waist_z
	pieces += [gnoll.loincloth(b, lod), beastmen.sash(b, lod, z0=w - 0.030, z1=w + 0.066, knot_side=-1.0),
			beastmen.guandao(b, lod), beastmen.gong_shield(b, lod)]
	return _assemble(b, pieces, lod, base)


def beastman_wolf_pathfinder(lod, base=False):
	"""Beastman Wolf Pathfinder: a lean, rangy grey wolf on long
	digitigrade legs, leaning forward, a long snout, tall ears and a cream
	ruff, a long bushy tail; a leather jerkin, the team's mantle with its
	hood thrown back and its loincloth, a crossbow levelled and a bolt
	quiver at the hip."""
	b = beastmen.WolfBody()
	torso = beastmen.wolf_torso(b, lod)
	head = beastmen.wolf_head(b, lod)
	pieces = _tilt(b, [head, beastmen.face(b, lod, head, eye_x=0.062, eye_dz=0.020, blush_x=0.098),
			beastmen.wolf_muzzle(b, lod), beastmen.wolf_brow(b, lod), beastmen.wolf_ears(b, lod),
			beastmen.cheek_ruff(b, lod)])
	pieces += [beastmen.wolf_legs(b, lod), beastmen.wolf_neck(b, lod), torso, beastmen.wolf_tail(b, lod),
			beastmen.arms(b, lod, k=0.86, bracer="leather")]
	for piece in pieces:
		beastmen.species(piece, beastmen.WOLF)
	pieces += [gnoll.loincloth(b, lod), gnoll.belt(b, lod), beastmen.ranger_mantle(b, lod), gear.crossbow(b, lod),
			beastmen.bolt_quiver(b, lod)]
	return _assemble(b, pieces, lod, base)


# --- star wanderers ---------------------------------------------------------

def _star_head(b, lod, on_head=(), fin_height=1.0, fin_spread=1.0):
	"""The bald sky-blue head, the shared eyes with a brow star and star
	freckles, the two tall fins, and what it wears, tipped back together."""
	head = star_wanderers.head(b, lod)
	pieces = [head, star_wanderers.star_face(b, lod, head), star_wanderers.fins(b, lod, fin_height, fin_spread)] + list(on_head)
	return _tilt(b, pieces)


def star_warrior(lod, base=False):
	"""Star Warrior: athletic and top-heavy, a pearl porcelain cuirass with
	a cyan star over a midnight suit, gold-rimmed porcelain pauldrons, the
	team's chunky scarf streaming back and its loincloth, a huge crescent
	blade in each fist held low: a gold sun crescent and a violet moon."""
	b = star_wanderers.WarriorBody()
	pieces = _star_head(b, lod)
	# The loincloth stands off the suit's flare at the hem, which otherwise
	# pokes through the middle of the flap as a dark spot.
	pieces += [star_wanderers.warrior_legs(b, lod), star_wanderers.warrior_torso(b, lod),
			gnoll.loincloth(b, lod, out=0.016),
			star_wanderers.warrior_belt(b, lod), star_wanderers.cowl_scarf(b, lod),
			gear.grow(parts.pauldrons(b, lod, "steel", "brass"), (0.0, 0.0, b.shoulder_z), 1.12),
			star_wanderers.arms(b, lod),
			star_wanderers.crescent_blade(b, lod, b.r_fist, -1.0, "arcane", "steel", size=0.86),
			star_wanderers.crescent_blade(b, lod, b.l_fist, 1.0, "fruit", "brass", sun=True, size=0.86)]
	return _assemble(b, pieces, lod, base)


def star_priestess(lod, base=False):
	"""Star Priestess: tall and slender, floating; a long white robe
	hovering over a crystal point, its wide hem and a stole in the team's
	colour, a porcelain mantle cut in gold star points, a gold star crown
	and a halo behind the head, a gold staff holding a violet orb in a
	ring of star points."""
	b = star_wanderers.PriestessBody()
	pieces = _star_head(b, lod, [star_wanderers.star_crown(b, lod)], fin_height=0.85)
	robe = star_wanderers.floating_robe(b, lod)
	pieces += [robe, star_wanderers.stole(b, lod, robe), clothes.wide_sleeves(b, lod, "robe"),
			star_wanderers.star_mantle(b, lod), star_wanderers.star_staff(b, lod)]
	return _assemble(b, pieces, lod, base)


def star_hunter(lod, base=False):
	"""Star Hunter: light, low and crouched forward on wide bent legs, a
	cyan crystal visor across the eyes, the team's deep hood-scarf drawn
	up (the fins standing through it) over a dagged capelet, the team's
	front flap, a crystal crossbow levelled: a violet moon crescent for a
	prod and a glowing cyan bolt."""
	b = star_wanderers.HunterBody()
	head = star_wanderers.head(b, lod)
	visor = star_wanderers.crystal_visor(b, lod, head)
	surface = geo.new_bm()
	geo.merge(surface, head)
	geo.merge(surface, visor)
	on_head = _tilt(b, [head, visor, star_wanderers.star_face(b, lod, surface), star_wanderers.fins(b, lod, 0.95),
			star_wanderers.hunter_hood(b, lod)])
	for piece in on_head:
		geo.translate(piece, b.head_shift())
	pieces = on_head + [star_wanderers.hunter_legs(b, lod), star_wanderers.hunter_torso(b, lod),
			star_wanderers._lean(b, star_wanderers.warrior_belt(b, lod)), gnoll.loincloth(b, lod, back=False, out=0.016),
			star_wanderers.hunter_scarf(b, lod),
			star_wanderers._lean(b, gear.grow(parts.pauldrons(b, lod, "steel", "brass"), (0.0, 0.0, b.shoulder_z), 0.80)),
			star_wanderers.arms(b, lod, k=0.92), star_wanderers.star_crossbow(b, lod),
			star_wanderers.star_quiver(b, lod)]
	return _assemble(b, pieces, lod, base)


def star_spearman(lod, base=False):
	"""Star Spearman: lanky and long-limbed, a narrow midnight suit under a
	porcelain gorget, the team's long tabard to the knees and its long cape,
	a tall spear with a gold moon crescent and a violet crystal point, a
	small gold buckler under a big violet star."""
	b = star_wanderers.SpearmanBody()
	pieces = _star_head(b, lod, fin_height=1.12)
	pieces += [star_wanderers.spearman_legs(b, lod), star_wanderers.spearman_torso(b, lod),
			star_wanderers.spearman_tabard(b, lod), star_wanderers.warrior_belt(b, lod),
			clothes.cape(b, lod, collar=None),
			gear.grow(parts.pauldrons(b, lod, "steel", "brass"), (0.0, 0.0, b.shoulder_z), 0.82),
			star_wanderers.arms(b, lod, k=0.84), star_wanderers.crescent_spear(b, lod),
			star_wanderers.star_buckler(b, lod)]
	return _assemble(b, pieces, lod, base)


def star_knight(lod, base=False):
	"""Star Knight: tall and straight-sided, porcelain head to toe; a
	crested helm with the team's arched crest (the fins standing through
	it), a gold keel down the cuirass, big porcelain pauldrons, the team's
	full surcoat skirt under a gold belt, a long violet crystal sword raised
	out to the right and a tall gold kite shield with a team face."""
	b = star_wanderers.KnightBody()
	pieces = _star_head(b, lod, [star_wanderers.crested_helm(b, lod)], fin_height=1.05)
	pieces += [star_wanderers.knight_legs(b, lod), star_wanderers.knight_torso(b, lod),
			star_wanderers.knight_skirt(b, lod),
			gear.grow(parts.pauldrons(b, lod, "steel", "brass"), (0.0, 0.0, b.shoulder_z), 1.22),
			star_wanderers.arms(b, lod, bracer="steel", k=1.05), star_wanderers.crystal_longsword(b, lod),
			star_wanderers.kite_shield(b, lod)]
	return _assemble(b, pieces, lod, base)


def star_paladin(lod, base=False):
	"""Star Paladin: the biggest, a huge porcelain barrel on short thick
	legs set wide, the head sunk between great gold pauldrons, the fins
	swept out like horns, a long white beard, the team's broad tabard edged
	in gold with a gold star on its skirt, a small halo of floating stars,
	a huge gold star hammer upright and a gold star lantern in the left hand."""
	b = star_wanderers.PaladinBody()
	pieces = _star_head(b, lod, [headgear.beard(b, lod, long=True, row_name="hair"),
			star_wanderers.star_circlet(b, lod)], fin_height=0.80, fin_spread=2.0)
	pieces += [star_wanderers.paladin_legs(b, lod), star_wanderers.paladin_torso(b, lod),
			star_wanderers.warrior_belt(b, lod), star_wanderers.paladin_tabard(b, lod),
			gear.grow(parts.pauldrons(b, lod, "brass", "steel"), (0.0, 0.0, b.shoulder_z), 1.50),
			star_wanderers.arms(b, lod, k=1.32), star_wanderers.star_hammer(b, lod), star_wanderers.star_lantern(b, lod)]
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


def star_rider(lod, base=False):
	"""Star Rider: a light rider (porcelain gorget, gold pauldrons, the
	team's scarf and front flap) with an upright crescent spear and the
	team's pennant, on a comet fox: a silver-lavender fox-deer with star specks,
	tall cyan-lined ears, a crystal horn, a white ruff, crystal hooves and a
	comet tail, a porcelain peytral and the team's dagged saddle cloth."""
	b = poses.rider_lance(parts.Body())
	pieces = _star_head(b, lod)
	pieces += [star_wanderers.spearman_torso(b, lod), gnoll.loincloth(b, lod, back=False, out=0.016),
			star_wanderers.warrior_belt(b, lod), star_wanderers.cowl_scarf(b, lod),
			gear.grow(parts.pauldrons(b, lod, "brass", "steel"), (0.0, 0.0, b.shoulder_z), 0.92),
			star_wanderers.arms(b, lod), star_wanderers.rider_spear(b, lod)]
	for piece in pieces:
		geo.translate(piece, RIDER_LIFT)
	for joint in ("l_fist", "l_wrist", "l_elbow", "r_fist", "r_wrist", "r_elbow"):
		setattr(b, joint, getattr(b, joint) + RIDER_LIFT)
	legs = horse.rider_legs(b, lod)
	star_wanderers._recolour(legs, "boot", "steel")
	pieces += [star_wanderers.steed(b, lod), star_wanderers.steed_barding(b, lod), star_wanderers.steed_cloth(b, lod),
			star_wanderers.steed_reins(b, lod), legs]
	return _assemble(b, pieces, lod, base)


# --- wild animals -------------------------------------------------------------

def bear_animal(lod, base=False):
	"""Bear: a wild dark-chocolate bear on all fours (see animals.py)."""
	b = parts.Body()
	return _assemble(b, [animals.bear(b, lod)], lod, base)


def boar_animal(lod, base=False):
	"""Boar: a small wedge-shaped wild boar, tusks and a black crest."""
	b = parts.Body()
	return _assemble(b, [animals.boar(b, lod)], lod, base)


def deer_animal(lod, base=False):
	"""Deer: a slender russet roe buck, short antlers, cream rump."""
	b = parts.Body()
	return _assemble(b, [animals.deer(b, lod)], lod, base)


# --- bestiary beasts ---------------------------------------------------------

def griffin(lod, base=False):
	"""Griffin (Aldmere): an eagle-headed lion with raised wings, the team's
	saddle cloth and breast collar (see beasts.py)."""
	b = parts.Body()
	return _assemble(b, [beasts.griffin(b, lod)], lod, base)


def sand_worm(lod, base=False):
	"""Sand Worm (Gnolls): a segmented worm rearing from its coil, a ringed
	maw, the team's collar and a gnoll war banner (see beasts.py)."""
	b = parts.Body()
	return _assemble(b, [beasts.sand_worm(b, lod)], lod, base)


def manticore(lod, base=False):
	"""Manticore (Aldmere): a maned lion with bat wings and a scorpion tail,
	the team's saddle cloth and tail wraps (see beasts.py)."""
	b = parts.Body()
	return _assemble(b, [beasts.manticore(b, lod)], lod, base)


def kitsune(lod, base=False):
	"""Kitsune (Dark Elves): a silver fox with a fan of foxfire tails, the
	team's collar, bib and saddle cloth (see beasts.py)."""
	b = parts.Body()
	return _assemble(b, [beasts.kitsune(b, lod)], lod, base)


def wind_tiger(lod, base=False):
	"""Wind Tiger (Dark Elves): a heavy striped white tiger in mint wind
	gusts, the team's collar, scarf and saddle cloth (see beasts.py)."""
	b = parts.Body()
	return _assemble(b, [beasts.wind_tiger(b, lod)], lod, base)


def skeleton_dragon(lod, base=False):
	"""Skeleton Dragon, the Bestiary drake (Gnolls): bone, torn hide wings,
	a green soul fire, the team's blanket and horn rags (see beasts.py).
	The monster of the same name will be its own, bigger figure."""
	b = parts.Body()
	return _assemble(b, [beasts.skeleton_dragon(b, lod)], lod, base)


def dragon(lod, base=False):
	"""Dragon (Star Wanderers): a heavy saffron-gold sun dragon with
	midnight star-specked wings, porcelain horns and spikes, a floating
	gold sun ring, the team's saddle cloth and collar (see beasts.py)."""
	b = parts.Body()
	return _assemble(b, [beasts.sun_dragon(b, lod)], lod, base)


def lightning_dragon(lod, base=False):
	"""Lightning Dragon (Star Wanderers): a long storm-blue eastern serpent
	rising in an S, cyan lightning-bolt fins, gold antlers, a crackling
	pearl, the team's neck and coil bands and scarf (see beasts.py)."""
	b = parts.Body()
	return _assemble(b, [beasts.lightning_dragon(b, lod)], lod, base)


# --- monsters ------------------------------------------------------------------

def black_dragon(lod, base=False):
	"""Black Dragon (monster, any race at the Shrine): a hulking charcoal
	dragon reared on its forelegs, ember belly, oxblood wings, the team's
	saddle cloth, collar and horn rags (see monsters.py)."""
	b = parts.Body()
	return _assemble(b, [monsters.black_dragon(b, lod)], lod, base)


def hydra(lod, base=False):
	"""Hydra (monster): a squat sea-teal body, five long necks fanning up to
	crested heads with angry brows, team bands on the necks and the team's
	saddle cloth (see monsters.py)."""
	b = parts.Body()
	return _assemble(b, [monsters.hydra(b, lod)], lod, base)


def skeleton_dragon_monster(lod, base=False):
	"""Skeleton Dragon (monster): a great reared bone dragon round a jade soul
	fire, torn wings, the team's caparison, war banner, collar and horn rags
	(see monsters.py). Bigger than the Bestiary drake, SkeletonDragonBeast."""
	b = parts.Body()
	return _assemble(b, [monsters.skeleton_dragon(b, lod)], lod, base)


def giant_bear(lod, base=False):
	"""Giant Bear (monster): a colossal chestnut war-bear on all fours, an
	iron war cap, plates and chain, the team's caparison, war-howdah with
	shields, banner and breast collar (see monsters.py)."""
	b = parts.Body()
	return _assemble(b, [monsters.giant_bear(b, lod)], lod, base)


def yeti(lod, base=False):
	"""Yeti (monster): a towering hunched white ape with a blue-grey face,
	ice crystals and icicles, a frozen boulder club, the team's kilt, sash
	and club rag (see monsters.py)."""
	b = parts.Body()
	return _assemble(b, [monsters.yeti(b, lod)], lod, base)


def orc_mutant(lod, base=False):
	"""Orc Mutant (monster): a lopsided olive brute with one huge stitched-on
	mauve arm and shoulder, bone spikes, a door-sized cleaver, chains, the
	team's loincloth and back banner (see monsters.py)."""
	b = parts.Body()
	return _assemble(b, [monsters.orc_mutant(b, lod)], lod, base)


def dark_lord(lod, base=False):
	"""Dark Lord (monster): a towering sorcerer-king in black-violet plate, a
	horned helm with a gold spiked crown and glowing eyes, a runed
	greatsword, violet sorcery in his hand, the team's cape, mantle and
	tabard (see monsters.py)."""
	b = parts.Body()
	return _assemble(b, [monsters.dark_lord(b, lod)], lod, base)


def phoenix(lod, base=False):
	"""Phoenix (monster): a great fire bird on long legs, huge raised flame
	wings, a long flame tail, the team's collar, pennant and jesses (see
	monsters.py)."""
	b = parts.Body()
	return _assemble(b, [monsters.phoenix(b, lod)], lod, base)


# --- siege ---------------------------------------------------------------------

def _crewman(lod, x, y, yaw=0.0):
	"""The machine's crew: the Aldmere Soldier (the crew sprite is the
	swordsman), standing on the ground beside it."""
	bm = soldier(lod)
	geo.rotate(bm, yaw, 'Z')
	return geo.translate(bm, (x, y, 0.0))


def ballista(lod, base=False):
	"""Ballista (Siege Workshop): a huge wheeled bolt-thrower with an
	oversized bolt loaded, the team's painted boards, fletching and pennant,
	a Soldier crewman at its winch (see siege.py)."""
	bm = siege.ballista(lod)
	geo.merge(bm, _crewman(lod, -0.80, 1.78, -20.0))
	return bm


def magic_cannon(lod, base=False):
	"""Magic Cannon (Siege Workshop): a brass arcane cannon with glowing rune
	rings and a crystal core on a two-wheeled carriage, the team's painted
	cheeks and breech, a Soldier crewman at its trail (see siege.py)."""
	bm = siege.magic_cannon(lod)
	geo.merge(bm, _crewman(lod, -0.85, 1.35, -15.0))
	return bm


## `portrait`: the point the portrait camera looks at (the head, in the
## exported figure's space) and how far back it stands.
_FOOT = {"palette": "aldmere", "portrait": (0.0, 0.0, 0.62), "portrait_distance": 1.25}
_GNOLL = dict(_FOOT, palette="gnolls", portrait=(0.0, -0.03, 0.64))
_DARK_ELF = dict(_FOOT, palette="dark_elves")
_BEASTMEN = dict(_FOOT, palette="beastmen", portrait=(0.0, -0.03, 0.64))
_STAR = dict(_FOOT, palette="star_wanderers")
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
	"DarkElfSorceress": dict(_DARK_ELF, build=dark_elf_sorceress, ready=True),
	"DarkElfSpellstealer": dict(_DARK_ELF, build=dark_elf_spellstealer, ready=True),
	"BeastmanWarrior": dict(_BEASTMEN, build=beastman_warrior, ready=True),
	"BeastmanRaider": dict(_BEASTMEN, build=beastman_raider, portrait=(0.0, -0.08, 0.54), ready=True),
	"BeastmanDruid": dict(_BEASTMEN, build=beastman_druid, portrait=(0.0, -0.02, 0.76), portrait_distance=1.45,
			ready=True),
	"BeastmanPandaWarrior": dict(_BEASTMEN, build=beastman_panda_warrior, portrait=(0.0, -0.02, 0.62),
			portrait_distance=1.45, ready=True),
	"BeastmanWolfPathfinder": dict(_BEASTMEN, build=beastman_wolf_pathfinder, portrait=(0.0, -0.10, 0.66),
			ready=True),
	"StarWarrior": dict(_STAR, build=star_warrior, ready=True),
	"StarPriestess": dict(_STAR, build=star_priestess, portrait=(0.0, 0.0, 0.74), portrait_distance=1.45, ready=True),
	"StarHunter": dict(_STAR, build=star_hunter, portrait=(0.0, -0.06, 0.58), ready=True),
	"StarSpearman": dict(_STAR, build=star_spearman, portrait=(0.0, 0.0, 0.72), portrait_distance=1.4, ready=True),
	"StarKnight": dict(_STAR, build=star_knight, portrait=(0.0, 0.0, 0.74), portrait_distance=1.4, ready=True),
	"StarPaladin": dict(_STAR, build=star_paladin, portrait=(0.0, 0.0, 0.66), portrait_distance=1.5, ready=True),
	"DarkElfRider": dict(_MOUNTED, palette="dark_elves", build=dark_elf_rider, ready=True),
	"StarRider": dict(_MOUNTED, palette="star_wanderers", build=star_rider, ready=True),
	"BearAnimal": dict(_MOUNTED, palette="animals", build=bear_animal, portrait=(0.0, -0.40, 0.52),
			portrait_distance=1.4, ready=True),
	"BoarAnimal": dict(_MOUNTED, palette="animals", build=boar_animal, portrait=(0.0, -0.30, 0.32),
			portrait_distance=1.1, ready=True),
	"DeerAnimal": dict(_MOUNTED, palette="animals", build=deer_animal, portrait=(0.0, -0.33, 0.76),
			portrait_distance=1.2, ready=True),
	"Griffin": dict(_MOUNTED, palette="aldmere", build=griffin, portrait=(0.0, -0.66, 1.38),
			portrait_distance=2.4, ready=True),
	"SandWorm": dict(_MOUNTED, palette="gnolls", build=sand_worm, portrait=(0.0, -0.34, 1.40),
			portrait_distance=2.4, ready=True),
	"Manticore": dict(_MOUNTED, palette="aldmere", build=manticore, portrait=(0.0, -0.78, 1.06),
			portrait_distance=2.4, ready=True),
	"Kitsune": dict(_MOUNTED, palette="dark_elves", build=kitsune, portrait=(0.0, -0.55, 1.32),
			portrait_distance=2.2, ready=True),
	"WindTiger": dict(_MOUNTED, palette="dark_elves", build=wind_tiger, portrait=(0.0, -0.84, 1.18),
			portrait_distance=2.4, ready=True),
	"SkeletonDragonBeast": dict(_MOUNTED, palette="gnolls", build=skeleton_dragon, portrait=(0.0, -0.74, 1.62),
			portrait_distance=2.4, ready=True),
	"Dragon": dict(_MOUNTED, palette="star_wanderers", build=dragon, portrait=(0.0, -0.80, 1.52),
			portrait_distance=2.4, ready=True),
	"LightningDragon": dict(_MOUNTED, palette="star_wanderers", build=lightning_dragon, portrait=(0.0, -0.25, 1.55),
			portrait_distance=2.4, ready=True),
	"BlackDragon": dict(_MOUNTED, palette="monsters", build=black_dragon, portrait=(0.0, -1.32, 2.90),
			portrait_distance=4.7, ready=True),
	"Hydra": dict(_MOUNTED, palette="monsters", build=hydra, portrait=(0.0, -1.20, 2.90),
			portrait_distance=4.7, ready=True),
	"SkeletonDragon": dict(_MOUNTED, palette="monsters", build=skeleton_dragon_monster, portrait=(0.0, -1.40, 2.90),
			portrait_distance=4.7, ready=True),
	"GiantBear": dict(_MOUNTED, palette="monsters", build=giant_bear, portrait=(0.0, -1.50, 1.55),
			portrait_distance=4.7, ready=True),
	"Yeti": dict(_MOUNTED, palette="monsters", build=yeti, portrait=(0.0, -0.59, 2.89),
			portrait_distance=4.7, ready=True),
	"OrcMutant": dict(_MOUNTED, palette="monsters", build=orc_mutant, portrait=(-0.16, -0.59, 2.75),
			portrait_distance=4.7, ready=True),
	"DarkLord": dict(_MOUNTED, palette="monsters", build=dark_lord, portrait=(0.0, -0.09, 2.98),
			portrait_distance=4.7, ready=True),
	"Phoenix": dict(_MOUNTED, palette="monsters", build=phoenix, portrait=(0.0, -0.40, 3.05),
			portrait_distance=4.7, ready=True),
	"Ballista": dict(_MOUNTED, palette="siege", build=ballista, portrait=(0.0, -0.40, 1.90),
			portrait_distance=4.2, ready=True),
	"MagicCannon": dict(_MOUNTED, palette="siege", build=magic_cannon, portrait=(0.0, -0.40, 2.10),
			portrait_distance=4.2, ready=True),
	"Horseman": dict(_MOUNTED, build=horseman, ready=True),
	"Cavalier": dict(_MOUNTED, build=cavalier, ready=True),
}
