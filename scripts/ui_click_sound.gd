extends Node
## Plays the UI click on every button press, game-wide. Hooks each BaseButton
## as it enters the tree, so buttons built in code are covered too.

const CLICK: AudioStream = preload("res://assets/sfx/UI SFX/Click.mp3")

var _player: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = AudioStreamPlayer.new()
	_player.stream = CLICK
	_player.bus = &"SFX"
	_player.max_polyphony = 4
	add_child(_player)
	get_tree().node_added.connect(_on_node_added)
	_hook_tree(get_tree().root)


func _hook_tree(node: Node) -> void:
	_on_node_added(node)
	for child in node.get_children():
		_hook_tree(child)


func _on_node_added(node: Node) -> void:
	if node is BaseButton and not node.pressed.is_connected(_play):
		node.pressed.connect(_play)


func _play() -> void:
	_player.play()
