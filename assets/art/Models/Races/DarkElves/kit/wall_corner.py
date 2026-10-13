# Builds WallCorner.glb: a short octagonal obsidian pillar banded in silver
# under a small swooping team spire. (Not used in game yet: RaceModels only
# swaps segments and gates.) See darkelves_common.py.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from darkelves_common import *

new_scene(621)
octo(0.55, 0.5, 0.22, (0, 0, 0), 'PlumDark')
rt = tower(0.46, 0.2, 1.75, taper=0.9, bands=(0.1, 0.9))
slit(face(0, -apothem(0.44), 1.0, '-y'), w=0.1, h=0.3)
octo(rt + 0.04, rt + 0.1, 0.1, (0, 0, 1.73), 'Plum')
swoop_spire(0.52, 0.85, 1.81, flare=0.3, lift=0.16, finial_h=0.2)
export('WallCorner')
