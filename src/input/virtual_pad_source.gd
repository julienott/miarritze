class_name VirtualPadSource
extends InputSource
## Source tactile : lit la manette virtuelle / les gestes (TouchControls).

var controls: TouchControls


func _init(p_controls: TouchControls) -> void:
	controls = p_controls


func sample() -> int:
	return controls.read_mask() if is_instance_valid(controls) else 0


func label() -> String:
	return "Tactile"
