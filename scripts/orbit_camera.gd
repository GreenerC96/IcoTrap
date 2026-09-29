@tool
extends Node3D

const FOCUS_GROUP := &"orbit_focus"

@export var target_path: NodePath
@export var min_orbit_distance: float = 1.5
@export var max_orbit_distance: float = 12.0
@export var zoom_step: float = 0.35
@export var orbit_distance: float = 4.0:
	set(value):
		orbit_distance = clampf(value, min_orbit_distance, max_orbit_distance)
		_update_camera_transform()

@export var mouse_sensitivity: float = 0.005
@export_range(-89.0, 89.0, 0.1) var min_pitch_degrees: float = -80.0
@export_range(-89.0, 89.0, 0.1) var max_pitch_degrees: float = 80.0

var _camera: Camera3D
var _yaw: float = 0.0
var _pitch: float = 0.35
var _dragging: bool = false


func _enter_tree() -> void:
	_camera = get_node_or_null("Camera3D") as Camera3D
	_update_camera_transform()


func _ready() -> void:
	if _camera == null:
		_camera = $Camera3D
	if not Engine.is_editor_hint():
		_camera.current = true
	_update_camera_transform()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mouse_button.pressed
		elif mouse_button.pressed:
			if mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP:
				_apply_zoom(-1.0)
			elif mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_apply_zoom(1.0)

	if event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		if motion.relative == Vector2.ZERO:
			return

		_yaw += motion.relative.x * mouse_sensitivity
		_pitch += motion.relative.y * mouse_sensitivity
		_clamp_pitch()
		_update_camera_transform()


func _apply_zoom(direction: float) -> void:
	orbit_distance = clampf(
		orbit_distance + direction * zoom_step,
		min_orbit_distance,
		max_orbit_distance
	)


func _clamp_pitch() -> void:
	var min_pitch := deg_to_rad(min_pitch_degrees)
	var max_pitch := deg_to_rad(max_pitch_degrees)
	_pitch = clampf(_pitch, min_pitch, max_pitch)


func _update_camera_transform() -> void:
	if _camera == null:
		return

	_clamp_pitch()

	var focus := _get_focus_point()
	var offset := Vector3(
		cos(_pitch) * sin(_yaw),
		sin(_pitch),
		cos(_pitch) * cos(_yaw)
	) * orbit_distance

	_camera.global_position = focus + offset
	_orient_camera_toward(focus)


func _orient_camera_toward(target: Vector3) -> void:
	var camera_position := _camera.global_position
	var view := (target - camera_position).normalized()
	var right := Vector3.UP.cross(view).normalized()
	var up := view.cross(right).normalized()
	_camera.global_basis = Basis(right, up, -view)


func _get_focus_point() -> Vector3:
	if target_path != NodePath():
		var target := get_node_or_null(target_path) as Node3D
		if target:
			return target.global_position

	var tree := get_tree()
	if tree:
		var grouped := tree.get_nodes_in_group(FOCUS_GROUP)
		if grouped.size() > 0 and grouped[0] is Node3D:
			return (grouped[0] as Node3D).global_position

	return global_position
