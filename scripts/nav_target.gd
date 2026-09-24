class_name NavTarget
extends RefCounted
## Where a unit is headed and how close counts as there — what is left of the
## NavigationAgent3D every soldier used to carry. The sim does the routing
## (ArmyBridge.solo_move, order_blocks).

var target_position: Vector3 = Vector3.ZERO
var target_desired_distance: float = 1.0
