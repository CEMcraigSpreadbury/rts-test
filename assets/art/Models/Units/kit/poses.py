"""Arm poses: where a figure's shoulders, elbows, wrists and fists are, and
which way what it holds points. Each sets them on a parts.Body (in its
standing space: the base's top at base_height, facing -Y, its right at -X).

The Soldier's pose (sword up in the right fist, shield on the left forearm)
is Body's own default.
"""
from mathutils import Vector


def _right_at_side(b):
	b.r_elbow = Vector((-0.207, 0.012, 0.360))
	b.r_wrist = Vector((-0.214, -0.012, 0.272))
	b.r_fist = Vector((-0.214, -0.020, 0.246))


def _left_at_side(b):
	b.l_elbow = Vector((0.207, 0.012, 0.360))
	b.l_wrist = Vector((0.214, -0.012, 0.272))
	b.l_fist = Vector((0.214, -0.020, 0.246))


def sword_only(b):
	"""Sword up in the right fist, the left hand at the side."""
	_left_at_side(b)
	return b


def polearm(b):
	"""A spear or halberd stood upright in the right fist, its butt by the
	right foot; the left hand at the side."""
	b.r_elbow = Vector((-0.205, 0.020, 0.370))
	b.r_wrist = Vector((-0.222, -0.060, 0.360))
	b.r_fist = Vector((-0.224, -0.090, 0.360))
	b.pole_axis = Vector((0.0, -0.10, 1.0)).normalized()
	_left_at_side(b)
	return b


def tower_shield(b):
	"""Sword up in the right fist, a tall shield held across the left side."""
	b.l_elbow = Vector((0.200, -0.020, 0.360))
	b.l_wrist = Vector((0.170, -0.110, 0.340))
	b.l_fist = Vector((0.160, -0.140, 0.340))
	b.shield_centre = Vector((0.105, -0.205, 0.318))
	b.shield_normal = Vector((0.30, -0.95, 0.05)).normalized()
	return b


def bow(b):
	"""A bow held upright out in front in the left fist, the right hand at
	the chest by the string."""
	b.l_elbow = Vector((0.190, -0.080, 0.420))
	b.l_wrist = Vector((0.180, -0.170, 0.420))
	b.l_fist = Vector((0.178, -0.200, 0.420))
	b.r_elbow = Vector((-0.200, 0.030, 0.370))
	b.r_wrist = Vector((-0.150, -0.060, 0.390))
	b.r_fist = Vector((-0.120, -0.085, 0.400))
	return b


def crossbow(b):
	"""A crossbow levelled at the waist: the right hand on the grip, the left
	under the fore-stock."""
	b.r_elbow = Vector((-0.190, -0.020, 0.360))
	b.r_wrist = Vector((-0.100, -0.090, 0.345))
	b.r_fist = Vector((-0.070, -0.110, 0.345))
	b.l_elbow = Vector((0.170, -0.090, 0.380))
	b.l_wrist = Vector((0.070, -0.180, 0.360))
	b.l_fist = Vector((0.045, -0.200, 0.360))
	b.stock_rear = Vector((-0.080, -0.050, 0.348))
	b.stock_front = Vector((0.020, -0.380, 0.372))
	return b


def staff(b):
	"""A staff stood upright in the right fist, the left hand raised in front
	as if about to cast."""
	b.r_elbow = Vector((-0.210, 0.010, 0.370))
	b.r_wrist = Vector((-0.225, -0.070, 0.380))
	b.r_fist = Vector((-0.228, -0.100, 0.380))
	b.pole_axis = Vector((0.0, -0.05, 1.0)).normalized()
	b.l_elbow = Vector((0.205, -0.040, 0.370))
	b.l_wrist = Vector((0.170, -0.130, 0.400))
	b.l_fist = Vector((0.150, -0.155, 0.410))
	return b


def tool(b):
	"""A tool held up in the right fist like the Soldier's sword; the left
	hand at the side."""
	_left_at_side(b)
	return b


def basket(b):
	"""Empty right hand at the side, a basket on the bent left arm."""
	_right_at_side(b)
	b.l_elbow = Vector((0.208, 0.012, 0.360))
	b.l_wrist = Vector((0.220, -0.062, 0.330))
	b.l_fist = Vector((0.220, -0.092, 0.326))
	return b


def rider_lance(b):
	"""Mounted, in the rider's own standing space: an upright lance in the
	right fist, the reins in the left."""
	b.r_elbow = Vector((-0.205, 0.000, 0.370))
	b.r_wrist = Vector((-0.215, -0.080, 0.360))
	b.r_fist = Vector((-0.217, -0.110, 0.360))
	b.pole_axis = Vector((0.0, -0.06, 1.0)).normalized()
	_reins(b)
	return b


def rider_couched(b):
	"""Mounted: a lance couched under the right arm, levelled forward."""
	b.r_elbow = Vector((-0.200, 0.040, 0.390))
	b.r_wrist = Vector((-0.180, -0.040, 0.395))
	b.r_fist = Vector((-0.172, -0.068, 0.400))
	b.pole_axis = Vector((0.05, -1.0, 0.20)).normalized()
	_reins(b)
	return b


def _reins(b):
	b.l_elbow = Vector((0.190, -0.040, 0.370))
	b.l_wrist = Vector((0.120, -0.130, 0.370))
	b.l_fist = Vector((0.090, -0.160, 0.370))
