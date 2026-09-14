class_name QuestStep
extends Node
## One objective in a scenario's quest. Placed as a child of the Scenario's
## Quests node; the node's own name is how other steps refer to it.
##
## A step becomes active once every step in `requires` is complete, so the
## quest is a list of steps with prerequisites rather than a rigid sequence —
## linear, parallel ("do A and B, then C") and branching all come out of that.
## Several steps can be active at once.

enum Completion {
	## Every condition must be met.
	ALL,
	## Any one of them is enough.
	ANY,
}

enum State { LOCKED, ACTIVE, COMPLETE, FAILED }

## The line the tracker shows. Keep it an instruction: "Train 5 soldiers".
@export var title: String = "Objective"
## Bonus objectives are marked as such and never hold anything up: nothing can
## require one, and failing one doesn't fail the quest.
@export var optional: bool = false
## Hidden steps run normally but stay out of the tracker — useful for the
## plumbing steps that spawn a wave or fire a line of dialogue.
@export var hidden: bool = false
## Steps that must be complete before this one starts. Paths are relative to
## this node's parent, so a plain node name is enough.
@export var requires: Array[NodePath] = []
@export var completion: Completion = Completion.ALL
@export var conditions: Array[QuestCondition] = []
## Any one of these ends the step as failed. A deadline is just an
## ElapsedTimeCondition in here.
@export var fail_conditions: Array[QuestCondition] = []
## Run when the step becomes active, is completed, and fails. Losing the
## mission is itself an action (EndMissionAction), so a step only ends the
## mission when its author says so.
@export var on_start: Array[QuestAction] = []
@export var on_complete: Array[QuestAction] = []
@export var on_fail: Array[QuestAction] = []
