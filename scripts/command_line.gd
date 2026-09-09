class_name CommandLine
extends Resource
## One line a unit can shout back when an order is issued, paired with the
## voice clip recorded for it. Text and audio live together deliberately: an
## earlier version kept the lines in a const and the clips in a parallel
## Array[AudioStream], which meant reordering or inserting a line silently
## desynced every clip after it — the popup showed the right words with the
## wrong voice under them, and nothing errored. See main.gd's
## _spawn_command_popup / COMMAND_POPUP_COLORS.

## Shown in the popup at the cursor. A line with no text is skipped, so a
## half-filled array in the inspector is harmless.
@export var text: String = ""
## Played when this exact line is picked. Optional — a line with no clip yet
## just pops silently, so recordings can be dropped in one at a time.
@export var voice: AudioStream = null
