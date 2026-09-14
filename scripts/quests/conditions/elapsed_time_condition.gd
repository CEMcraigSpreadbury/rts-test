class_name ElapsedTimeCondition
extends QuestCondition
## Time since the step became active. As a condition it is "survive five
## minutes"; as a fail condition it is a deadline.

@export var seconds: float = 60.0

func progress(runner) -> Vector2i:
	var elapsed: float = runner.time - runner.started_at(self)
	return Vector2i(int(elapsed), maxi(int(seconds), 1))
