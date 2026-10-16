extends "res://trailer/quick/itch_director.gd"
## The itch page banner's background: the itch trailer's battle from a low
## camera, so the treeline and sky make a band across the top for the title
## and the two lines clash below it. Render with
##   quick_boot.tscn -- --director=banner --stills=<dir>:5,6,7,8,9
## (window sized by override.cfg).

func _init() -> void:
	super._init()
	shots = [
		{"len": 2.0, "subject": "base", "night": 0.0, "from": [20.0, 34.0, 34.0, Vector3.ZERO], "to": [20.0, 34.0, 34.0, Vector3.ZERO]},
		{"len": 10.0, "subject": "fight", "night": 0.0, "locked": true,
				"from": [-28.0, 11.0, 9.5, Vector3(0, 0, 1)], "to": [-22.0, 11.0, 9.0, Vector3(0, 0, 1)]},
	]
