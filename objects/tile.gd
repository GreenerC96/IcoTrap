class_name Tile
extends StaticBody3D

const TRIANGLE_SCENE := preload("res://objects/triangle.tscn")

const COLOR_HOVER := Color.WHITE

const COLLISION_THICKNESS := 0.04
const ARROW_LIFT_RADIUS_FACTOR := 2.5
const ARROW_LIFT_MIN := 0.004

var neighbours: Array[Tile] = []
var opposites: Array = []
var direction_targets: Array[Tile] = []
var wind_source_tiles: Array[Tile] = []

var _mesh_instance: MeshInstance3D
var _material: StandardMaterial3D
var _base_color: Color = Color(0.45, 0.62, 0.92)
var _hovered: bool = false

var _inset_corners: Array[Vector3] = []
var _pre_inset_corners: Array[Vector3] = []
var _direction_line: MeshInstance3D
var _wind_source_line: MeshInstance3D


func configure(
	inset_corners: Array,
	pre_inset_corners: Array,
	base_color: Color
) -> void:
	_base_color = base_color
	_inset_corners = _array_to_vector3(inset_corners)
	_pre_inset_corners = _array_to_vector3(pre_inset_corners)

	_mesh_instance = MeshInstance3D.new()
	add_child(_mesh_instance)
	_mesh_instance.mesh = _build_surface_mesh(_inset_corners)

	_material = StandardMaterial3D.new()
	_material.albedo_color = base_color
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


func setup_directions(
	target_tiles: Array[Tile],
	source_tiles: Array[Tile],
	_arrow_length: float,
	arrow_radius: float
) -> void:
	direction_targets = target_tiles.duplicate()
	wind_source_tiles = source_tiles.duplicate()
	_rebuild_direction_lines(arrow_radius)


func clear_direction() -> void:
	direction_targets.clear()
	wind_source_tiles.clear()
	if _direction_line != null and is_instance_valid(_direction_line):
		_direction_line.queue_free()
		_direction_line = null
	if _wind_source_line != null and is_instance_valid(_wind_source_line):
		_wind_source_line.queue_free()
		_wind_source_line = null


func set_base_color(color: Color) -> void:
	_base_color = color
	refresh_visual()


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


func _rebuild_direction_lines(arrow_radius: float) -> void:
	if _direction_line != null and is_instance_valid(_direction_line):
		_direction_line.queue_free()
		_direction_line = null
	if _wind_source_line != null and is_instance_valid(_wind_source_line):
		_wind_source_line.queue_free()
		_wind_source_line = null

	if _inset_corners.size() < 3:
		return

	var centroid := get_inset_centroid()
	var surface_normal := _tile_surface_normal()
	if surface_normal.dot(centroid) < 0.0:
		surface_normal = -surface_normal

	var lift := maxf(arrow_radius * ARROW_LIFT_RADIUS_FACTOR, ARROW_LIFT_MIN)
	var lifted_centroid := centroid + surface_normal * lift

	if not direction_targets.is_empty():
		var line_vertices := PackedVector3Array()
		for target in direction_targets:
			if target == null or not is_instance_valid(target):
				continue
			var end_on_tile := _surface_point_for_direction_target(target)
			if end_on_tile.is_equal_approx(centroid):
				continue
			var end := end_on_tile + surface_normal * lift
			if lifted_centroid.is_equal_approx(end):
				continue
			line_vertices.append(lifted_centroid)
			line_vertices.append(end)

		_direction_line = _make_line_mesh_instance(
			"DirectionLine", line_vertices, Color(0.12, 0.12, 0.16)
		)
		if _direction_line != null:
			add_child(_direction_line)

	if not wind_source_tiles.is_empty():
		var source_vertices := PackedVector3Array()
		for source in wind_source_tiles:
			if source == null or not is_instance_valid(source):
				continue
			var from_on_tile := _surface_point_for_direction_target(source)
			if from_on_tile.is_equal_approx(centroid):
				continue
			var start := from_on_tile + surface_normal * lift
			if start.is_equal_approx(lifted_centroid):
				continue
			source_vertices.append(start)
			source_vertices.append(lifted_centroid)

		_wind_source_line = _make_line_mesh_instance(
			"WindSourceLine", source_vertices, Color.WHITE
		)
		if _wind_source_line != null:
			add_child(_wind_source_line)


func _make_line_mesh_instance(
	node_name: String,
	vertices: PackedVector3Array,
	color: Color
) -> MeshInstance3D:
	if vertices.is_empty():
		return null

	var line_mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	line_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)

	var line_node := MeshInstance3D.new()
	line_node.name = node_name
	line_node.mesh = line_mesh

	var line_material := StandardMaterial3D.new()
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.albedo_color = color
	line_material.disable_ambient_light = true
	line_node.material_override = line_material
	line_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return line_node


func _surface_point_for_direction_target(target: Tile) -> Vector3:
	var centroid := get_inset_centroid()
	var corner_count := _inset_corners.size()

	for edge_index in neighbours.size():
		if neighbours[edge_index] == target:
			var p0: Vector3 = _inset_corners[edge_index]
			var p1: Vector3 = _inset_corners[(edge_index + 1) % corner_count]
			return (p0 + p1) * 0.5

	for corner_index in opposites.size():
		if opposites[corner_index] == target:
			return _inset_corners[corner_index]

	if _inset_corners.size() == 3:
		return _clip_point_to_tile_polygon(
			centroid,
			_project_onto_tile_plane(target.get_inset_centroid()),
			3
		)
	return _project_onto_tile_plane(target.get_inset_centroid())


func _project_onto_tile_plane(point: Vector3) -> Vector3:
	var centroid := get_inset_centroid()
	var normal := _tile_surface_normal()
	if normal.dot(centroid) < 0.0:
		normal = -normal
	var offset := point - centroid
	return point - normal * normal.dot(offset)


func _clip_point_to_tile_polygon(origin: Vector3, point: Vector3, corner_count: int) -> Vector3:
	var direction := point - origin
	var max_distance := direction.length()
	if max_distance < 0.000001:
		return origin

	var normal := _tile_surface_normal()
	if normal.dot(origin) < 0.0:
		normal = -normal
	var axis_x := normal.cross(direction).normalized()
	if axis_x.length_squared() < 0.000001:
		axis_x = normal.cross(_inset_corners[1] - origin).normalized()
	var axis_y := normal.cross(axis_x)

	var origin_2d := Vector2(origin.dot(axis_x), origin.dot(axis_y))
	var direction_2d := Vector2(direction.dot(axis_x), direction.dot(axis_y))
	var best_t := 1.0
	var found := false

	for i in corner_count:
		var a_3d: Vector3 = _inset_corners[i]
		var b_3d: Vector3 = _inset_corners[(i + 1) % corner_count]
		var a_2d := Vector2(a_3d.dot(axis_x), a_3d.dot(axis_y))
		var b_2d := Vector2(b_3d.dot(axis_x), b_3d.dot(axis_y))
		var t := _intersect_ray_segment_2d(origin_2d, direction_2d, a_2d, b_2d)
		if t >= 0.0 and t <= 1.0 and t < best_t:
			best_t = t
			found = true

	if found:
		return origin + direction * best_t
	return point


func _intersect_ray_segment_2d(
	ray_origin: Vector2,
	ray_vector: Vector2,
	seg_a: Vector2,
	seg_b: Vector2
) -> float:
	var segment := seg_b - seg_a
	var denom := ray_vector.cross(segment)
	if absf(denom) < 0.000001:
		return -1.0

	var t := (seg_a - ray_origin).cross(segment) / denom
	var u := (seg_a - ray_origin).cross(ray_vector) / denom
	if t < 0.0 or t > 1.0 or u < 0.0 or u > 1.0:
		return -1.0
	return t


func _tile_surface_normal() -> Vector3:
	if _inset_corners.size() < 3:
		return Vector3.UP
	return _outward_surface_normal(_inset_corners, get_inset_centroid())


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
