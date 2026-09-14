class_name RulerPicker
extends OptionButton
## The Ruler dropdown on a player row (lobby and single player setup). Speaks
## in ruler indices, Ruler.RANDOM included, rather than item positions.

signal ruler_picked(ruler_index: int)

## Item ids are ruler_index + 1: OptionButton treats an id of -1 as "use the
## position", so Ruler.RANDOM can't be an id itself.
func _init(selected_ruler_index: int) -> void:
	add_item(Ruler.display_name_for(Ruler.RANDOM), Ruler.RANDOM + 1)
	var rulers := Ruler.list_all()
	for i in rulers.size():
		add_item(rulers[i].ruler_name, i + 1)
	select(get_item_index(selected_ruler_index + 1))
	item_selected.connect(func(i: int): ruler_picked.emit(get_item_id(i) - 1))

## The Ruler index currently chosen, Ruler.RANDOM included — for callers that
## read the picker when they need it rather than following ruler_picked.
func selected_ruler() -> int:
	return get_item_id(selected) - 1 if selected >= 0 else Ruler.RANDOM
