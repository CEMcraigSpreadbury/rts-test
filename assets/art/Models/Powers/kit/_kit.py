# The faction powers' set pieces (Models/Powers/*.glb) are built with the
# Aldmere building kit (TownBuildings/kit/common.py), at full size in metres.
# Each script does `from _kit import *`, builds, then export(name): written
# next to this folder unless a path follows `--`.
import sys, os
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', 'TownBuildings', 'kit'))
import common
from common import *

common.COLOURS.update({
	'SailBlack': (0.028, 0.026, 0.03), 'SailTorn': (0.06, 0.055, 0.06),
	'Hull': (0.12, 0.045, 0.018), 'HullDark': (0.035, 0.014, 0.006),
	'Blade': (0.62, 0.66, 0.72), 'Rune': (0.4, 0.8, 1.0), 'Ruby': (0.6, 0.01, 0.02),
	'Pod': (0.36, 0.38, 0.42), 'Glass': (1.0, 0.45, 0.08),
})
common.GLOSSY = common.GLOSSY + ('Blade', 'Pod', 'Ruby', 'Glass')


def out(name):
	if '--' in sys.argv and len(sys.argv) > sys.argv.index('--') + 1:
		return sys.argv[sys.argv.index('--') + 1]
	return os.path.join(os.path.dirname(HERE), name + '.glb')


common.out_path = out
