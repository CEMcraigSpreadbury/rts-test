@tool
extends EditorPlugin

const IconMakerDock = preload("res://addons/icon_maker/icon_maker_dock.gd")

var _dock: Control

func _enter_tree() -> void:
	_dock = IconMakerDock.new()
	_dock.name = "Icon Maker"
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)

func _exit_tree() -> void:
	remove_control_from_docks(_dock)
	_dock.queue_free()
