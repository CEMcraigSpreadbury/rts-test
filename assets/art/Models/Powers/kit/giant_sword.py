# Builds GiantSword.glb: the Sword of Aldmere, a 14 m broadsword stood on its
# point (the origin): a wide steel blade with glowing runes down its fuller, a
# gold crossguard, a red-bound grip and a ruby pommel.
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _kit import *

new_scene(441)
BLADE = 1.6
# The point, then the blade above it.
bpy.ops.mesh.primitive_cone_add(vertices=4, radius1=BLADE * 0.71, radius2=0.0, depth=2.2)
tip = bpy.context.active_object
tip.scale = (1.0, 0.2, 1.0)
tip.rotation_euler = (math.radians(180), 0, math.radians(45))
tip.location = (0, 0, 1.1)
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
common._finish(tip, 'Blade', 0.03, 2, angle=30)
box((BLADE, 0.28, 8.2), (0, 0, 2.2 + 4.1), 'Blade', bevel=0.08)
box((0.34, 0.32, 7.4), (0, 0, 2.5 + 3.7), 'Iron', bevel=0.05)
for i in range(7):
	box((0.36, 0.36, 0.56), (0, 0, 3.0 + i * 1.0), 'Rune', rot=(0, 45 if i % 2 else 0, 0), bevel=0.04)
# The gold collar, the crossguard and its round ends.
box((BLADE + 0.4, 0.44, 0.6), (0, 0, 10.65), 'Gold', bevel=0.12)
box((6.0, 0.7, 0.7), (0, 0, 11.1), 'Gold', bevel=0.22)
for side in (-1, 1):
	sphere(0.55, (side * 3.1, 0, 11.35), 'Gold')
	sphere(0.24, (side * 3.1, -0.5, 11.35), 'Ruby')
sphere(0.42, (0, -0.4, 11.1), 'Ruby')
# The grip, bound in red, and the pommel.
cylinder(0.34, 2.6, (0, 0, 12.75), 'Red', verts=12, bevel=0.05)
for i in range(5):
	cylinder(0.38, 0.14, (0, 0, 11.8 + i * 0.48), 'Gold', verts=12, bevel=0.03)
sphere(0.75, (0, 0, 14.4), 'Gold')
sphere(0.36, (0, -0.62, 14.4), 'Ruby')
export('GiantSword')
