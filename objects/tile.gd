class_name Tile
extends StaticBody3D

const TRIANGLE_SCENE := preload("res://objects/triangle.tscn")

const COLOR_HOVER := Color.WHITE
const COLOR_SEA := Color(0.45, 0.62, 0.92)
const COLOR_LAND := Color(0.35, 0.72, 0.38)

const COLLISION_THICKNESS := 0.04

enum Terrain { SEA, LAND }

var neighbours: Array[Tile] = []
var opposites: Array = []
var direction_targets: Array[Tile] = []
var wind_source_tiles: Array[Tile] = []
var terrain: Terrain = Terrain.SEA

var _mesh_instance: MeshInstance3D
var _material: StandardMaterial3D
var _base_color: Color = COLOR_SEA
var _hovered: bool = false

var _inset_corners: Array[Vector3] = []
var _pre_inset_corners: Array[Vector3] = []


func configure(inset_corners: Array, pre_inset_corners: Array) -> void:
	terrain = Terrain.SEA
	_base_color = COLOR_SEA
	_inset_corners = _array_to_vector3(inset_corners)
	_pre_inset_corners = _array_to_vector3(pre_inset_corners)

	_mesh_instance = MeshInstance3D.new()
	add_child(_mesh_instance)
	_mesh_instance.mesh = _build_surface_mesh(_inset_corners)

	_material = StandardMaterial3D.new()
	_material.albedo_color = _base_color
	_material.metallic = 0.1
	_material.roughness = 0.65
	_mesh_instance.material_override = _material

	var collision := CollisionShape3D.new()
	collision.shape = _build_collision_prism(_inset_corners)
	add_child(collision)

	if is_pentagon():
		opposites = []
	else:
		opposites = [null, null, null]

	refresh_visual()


func is_pentagon() -> bool:
	return _pre_inset_corners.size() == 5


func is_land() -> bool:
	return terrain == Terrain.LAND


func set_terrain(value: Terrain) -> void:
	terrain = value
	_base_color = COLOR_LAND if terrain == Terrain.LAND else COLOR_SEA
	refresh_visual()


func get_corner_count() -> int:
	return _pre_inset_corners.size()


func get_pre_inset_corners() -> Array[Vector3]:
	return _pre_inset_corners


func get_sort_index() -> int:
	if name.begins_with("Tile"):
		return name.substr(4).to_int()
	return 0


func get_inset_centroid() -> Vector3:
	if _inset_corners.is_empty():
		return Vector3.ZERO
	var sum := Vector3.ZERO
	for corner in _inset_corners:
		sum += corner
	return sum / float(_inset_corners.size())


func get_inset_corners() -> Array[Vector3]:
	return _inset_corners.duplicate()


func setup_directions(target_tiles: Array[Tile], source_tiles: Array[Tile]) -> void:
	direction_targets = target_tiles.duplicate()
	wind_source_tiles = source_tiles.duplicate()


func clear_direction() -> void:
	direction_targets.clear()
	wind_source_tiles.clear()


func refresh_visual() -> void:
	if _material == null:
		return
	if _hovered:
		_material.albedo_color = COLOR_HOVER
	else:
		_material.albedo_color = _base_color


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


func _on_mouse_entered() -> void:
	_hovered = true
	refresh_visual()


func _on_mouse_exited() -> void:
	_hovered = false
	refresh_visual()


func _outward_surface_normal(corners: Array[Vector3], centroid: Vector3) -> Vector3:
	if corners.size() < 3:
		return Vector3.UP
	var normal := (corners[2] - corners[0]).cross(corners[1] - corners[0])
	if normal.length_squared() < 0.000001:
		return Vector3.UP
	normal = normal.normalized()
	if normal.dot(centroid) < 0.0:
		normal = -normal
	return normal


func _build_surface_mesh(corners: Array[Vector3]) -> ArrayMesh:
	if corners.size() == 3:
		var triangle := TRIANGLE_SCENE.instantiate() as MeshInstance3D
		triangle.set_corners(corners[0], corners[1], corners[2])
		var mesh := triangle.mesh
		triangle.free()
		return mesh

	var centroid := Vector3.ZERO
	for corner in corners:
		centroid += corner
	centroid /= float(corners.size())

	var normal := _outward_surface_normal(corners, centroid)

	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in corners.size():
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[(i + 1) % corners.size()]
		surface_tool.set_normal(normal)
		surface_tool.add_vertex(centroid)
		surface_tool.set_normal(normal)
		surface_tool.add_vertex(a)
		surface_tool.set_normal(normal)
		surface_tool.add_vertex(b)
	return surface_tool.commit()


func _array_to_vector3(source: Array) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for item in source:
		result.append(item as Vector3)
	return result


func _build_collision_prism(corners: Array[Vector3]) -> ConvexPolygonShape3D:
	var centroid := Vector3.ZERO
	for corner in corners:
		centroid += corner
	centroid /= float(corners.size())
	var normal := _outward_surface_normal(corners, centroid)

	var half_offset := normal * (COLLISION_THICKNESS * 0.5)
	var points := PackedVector3Array()
	for corner in corners:
		points.append(corner + half_offset)
	for corner in corners:
		points.append(corner - half_offset)

	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	return shape
