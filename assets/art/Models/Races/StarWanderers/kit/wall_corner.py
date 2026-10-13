# Builds WallCorner.glb: a round pearl post ribbed in lavender under a small
# gored team tent and a glowing star finial. Not in RaceModels.MODELS, so
# unused in-game for now. See starwanderers_common.py.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from starwanderers_common import *

new_scene(821)
drum(0.4, 0.0, 1.55, ribs=6, taper=0.92)
top, _ = canopy(0.5, 0.55, 1.52, gores=6, shape='tent', sag=0.1, hem=0.06)
star_finial(0, 0, top - 0.02, 0.8, 'Starfire')
export('WallCorner')
