@tool
extends Node3D

const TILE_SCENE := preload("res://objects/tile.tscn")

const VERTEX_SNAP_SCALE := 10000.0

@export var radius: float = 1.0:
	set(value):
		radius = max(value, 0.001)
		_rebuild()

@export_range(2, 8, 1) var frequency: int = 2:
	set(value):
		frequency = max(value, 2)
		_rebuild()

@export_range(0.0, 0.4, 0.01) var gap: float = 0.08:
	set(value):
		gap = clampf(value, 0.0, 0.4)
		_rebuild()

@export var albedo_color: Color = Color(0.45, 0.62, 0.92):
	set(value):
		albedo_color = value
		_update_tile_base_colors()

@export var direction_seed: int = 1:
	set(value):
		direction_seed = value
		_rebuild()

var _facets_root: Node3D
var _next_tile_id: int = 0


func _enter_tree() -> void:
	_rebuild()


func _ready() -> void:
	_rebuild()
	if Engine.is_editor_hint():
		return
	get_viewport().physics_object_picking = true


func _rebuild() -> void:
	if not is_inside_tree():
		return

	_ensure_scene_roots()
	_remove_stale_generated_children()
	_clear_facets()
	_next_tile_id = 0

	var vertices := _build_vertices(radius)
	var faces := _build_faces()
	var edge_map: Dictionary = {}

	for face in faces:
		var a := vertices[face[0]]
		var b := vertices[face[1]]
		var c := vertices[face[2]]
		for small_triangle in _subdivide_face(a, b, c, frequency):
			var pre_a: Vector3 = small_triangle[0]
			var pre_b: Vector3 = small_triangle[1]
			var pre_c: Vector3 = small_triangle[2]
			var inset := _inset_triangle(pre_a, pre_b, pre_c, gap)
			var tile := _add_tile(
				[inset[0], inset[1], inset[2]],
				[pre_a, pre_b, pre_c]
			)
			_register_tile_edges(tile, [pre_a, pre_b, pre_c], edge_map)

	var vertex_map := _build_vertex_map()
	_replace_vertex_fans_with_pentagons(vertices, vertex_map)

	edge_map.clear()
	for child in _facets_root.get_children():
		if child is Tile:
			_register_tile_edges(child as Tile, (child as Tile).get_pre_inset_corners(), edge_map)

	_link_tile_neighbours(edge_map)
	vertex_map = _build_vertex_map()
	_link_tile_opposites(vertex_map)
	_assign_tile_directions()


func _register_tile_edges(
	tile: Tile,
	pre_corners: Array,
	edge_map: Dictionary
) -> void:
	var count := pre_corners.size()
	for i in count:
		var a: Vector3 = pre_corners[i]
		var b: Vector3 = pre_corners[(i + 1) % count]
		var key := _edge_key(a, b)
		if not edge_map.has(key):
			edge_map[key] = []
		(edge_map[key] as Array).append(tile)


func _link_tile_neighbours(edge_map: Dictionary) -> void:
	if _facets_root == null:
		return

	for child in _facets_root.get_children():
		if not child is Tile:
			continue
		var tile: Tile = child as Tile
		tile.neighbours.clear()
		var pre_corners := tile.get_pre_inset_corners()
		var corner_count := pre_corners.size()
		for edge_index in corner_count:
			var a: Vector3 = pre_corners[edge_index]
			var b: Vector3 = pre_corners[(edge_index + 1) % corner_count]
			var key := _edge_key(a, b)
			if not edge_map.has(key):
				continue
			var tiles: Array = edge_map[key]
			if tiles.size() != 2:
				continue
			var other: Tile = tiles[1] if tiles[0] == tile else tiles[0]
			tile.neighbours.append(other)


func _build_vertex_map() -> Dictionary:
	var vertex_map: Dictionary = {}
	if _facets_root == null:
		return vertex_map

	for child in _facets_root.get_children():
		if not child is Tile:
			continue
		var tile: Tile = child as Tile
		for corner in tile.get_pre_inset_corners():
			var key := _vertex_key(corner)
			if not vertex_map.has(key):
				vertex_map[key] = []
			(vertex_map[key] as Array).append(tile)
	return vertex_map


func _link_tile_opposites(vertex_map: Dictionary) -> void:
	if _facets_root == null:
		return

	for child in _facets_root.get_children():
		if not child is Tile:
			continue
		var tile: Tile = child as Tile
		if tile.is_pentagon():
			tile.opposites = []
			continue

		tile.opposites = [null, null, null]
		var pre_corners := tile.get_pre_inset_corners()
		var forbidden: Dictionary = {}
		for neighbor in tile.neighbours:
			forbidden[neighbor] = true
			for adjacent in neighbor.neighbours:
				forbidden[adjacent] = true

		for corner_index in 3:
			var corner: Vector3 = pre_corners[corner_index]
			var key := _vertex_key(corner)
			if not vertex_map.has(key):
				push_warning("Tile %s missing vertex map entry for corner %d" % [tile.name, corner_index])
				continue

			var candidates: Array[Tile] = []
			for candidate in vertex_map[key] as Array:
				if candidate == tile:
					continue
				if candidate.is_pentagon():
					continue
				if forbidden.has(candidate):
					continue
				candidates.append(candidate)

			if candidates.is_empty():
				push_warning("Tile %s has no opposite candidate for corner %d" % [tile.name, corner_index])
				continue

			candidates.sort_custom(func(a: Tile, b: Tile) -> bool:
				return a.get_sort_index() < b.get_sort_index()
			)
			tile.opposites[corner_index] = candidates[0]


func _collect_corner_tiles(icosahedron_vertices: PackedVector3Array) -> Dictionary:
	var vertex_map := _build_vertex_map()
	var corner_tiles: Dictionary = {}
	for vertex in icosahedron_vertices:
		var key := _vertex_key(vertex)
		if not vertex_map.has(key):
			continue
		var fan: Array = vertex_map[key]
		if fan.size() != 5:
			continue
		for item in fan:
			if item is Tile:
				var tile: Tile = item as Tile
				if not tile.is_pentagon():
					corner_tiles[tile] = true
	return corner_tiles


func _assign_tile_directions() -> void:
	if _facets_root == null:
		return

	var tiles: Array[Tile] = []
	for child in _facets_root.get_children():
		if child is Tile:
			tiles.append(child as Tile)
	tiles.sort_custom(func(a: Tile, b: Tile) -> bool:
		return a.get_sort_index() < b.get_sort_index()
	)

	var corner_tiles := _collect_corner_tiles(_build_vertices(radius))
	var wind := WindDirection.generate(tiles, corner_tiles, direction_seed)
	var targets_map: Dictionary = wind["targets"]
	var sources_map: Dictionary = wind["sources"]

	for tile in tiles:
		if targets_map.has(tile):
			var targets: Array = targets_map[tile]
			if targets.is_empty():
				tile.clear_direction()
			else:
				var typed_targets: Array[Tile] = []
				for target in targets:
					if target is Tile:
						typed_targets.append(target as Tile)
				var typed_sources: Array[Tile] = []
				if sources_map.has(tile):
					for source in sources_map[tile] as Array:
						if source is Tile:
							typed_sources.append(source as Tile)
				tile.setup_directions(typed_targets, typed_sources)
		else:
			tile.clear_direction()

	var wind_strand := get_node_or_null("WindStrand") as WindStrand
	if wind_strand != null:
		wind_strand.refresh(tiles)


func _replace_vertex_fans_with_pentagons(
	icosahedron_vertices: PackedVector3Array,
	vertex_map: Dictionary
) -> void:
	if _facets_root == null:
		return

	var consumed: Dictionary = {}

	for vertex in icosahedron_vertices:
		var key := _vertex_key(vertex)
		if not vertex_map.has(key):
			continue
		var fan_tiles: Array = vertex_map[key]
		if fan_tiles.size() != 5:
			continue

		var tiles: Array[Tile] = []
		for item in fan_tiles:
			if not item is Tile:
				continue
			var fan_tile: Tile = item as Tile
			if fan_tile.is_pentagon() or consumed.has(fan_tile):
				tiles.clear()
				break
			tiles.append(fan_tile)

		if tiles.size() != 5:
			continue

		var loop := _build_pentagon_corner_loop(vertex, tiles)
		if loop.size() != 5:
			continue

		for fan_tile in tiles:
			consumed[fan_tile] = true
			_facets_root.remove_child(fan_tile)
			fan_tile.free()

		var inset := _inset_polygon(loop, gap)
		_add_tile(
			[inset[0], inset[1], inset[2], inset[3], inset[4]],
			[loop[0], loop[1], loop[2], loop[3], loop[4]]
		)


func _build_pentagon_corner_loop(vertex: Vector3, fan_tiles: Array[Tile]) -> Array[Vector3]:
	var vertex_key := _vertex_key(vertex)
	var segments: Array = []

	for fan_tile in fan_tiles:
		var corners := fan_tile.get_pre_inset_corners()
		var vertex_corner := -1
		for corner_index in corners.size():
			if _vertex_key(corners[corner_index]) == vertex_key:
				vertex_corner = corner_index
				break
		if vertex_corner < 0:
			return []

		var a: Vector3 = corners[(vertex_corner + 1) % 3]
		var b: Vector3 = corners[(vertex_corner + 2) % 3]
		segments.append([a, b])

	if segments.size() != 5:
		return []

	var first_a: Vector3 = segments[0][0]
	var first_b: Vector3 = segments[0][1]
	var ordered: Array[Vector3] = [first_a, first_b]
	var prev_key := _vertex_key(first_a)
	var curr_key := _vertex_key(first_b)

	while ordered.size() < 5:
		var extended := false
		for segment in segments:
			var seg_a: Vector3 = segment[0]
			var seg_b: Vector3 = segment[1]
			var key_a := _vertex_key(seg_a)
			var key_b := _vertex_key(seg_b)
			if key_a == curr_key and key_b != prev_key:
				ordered.append(seg_b)
				prev_key = curr_key
				curr_key = key_b
				extended = true
				break
			if key_b == curr_key and key_a != prev_key:
				ordered.append(seg_a)
				prev_key = curr_key
				curr_key = key_a
				extended = true
				break
		if not extended:
			return []

	if ordered.size() != 5:
		return []

	var centroid := Vector3.ZERO
	for point in ordered:
		centroid += point
	centroid /= 5.0
	var outward := centroid.normalized()
	var polygon_normal := (ordered[2] - ordered[0]).cross(ordered[1] - ordered[0])
	if polygon_normal.dot(outward) < 0.0:
		ordered.reverse()

	return _array_to_vector3(ordered)


func _array_to_vector3(source: Array) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for item in source:
		result.append(item as Vector3)
	return result


func _vertex_key(point: Vector3) -> String:
	var snapped := (point * VERTEX_SNAP_SCALE).round()
	return "%.0f,%.0f,%.0f" % [snapped.x, snapped.y, snapped.z]


func _edge_key(p: Vector3, q: Vector3) -> String:
	var key_p := _vertex_key(p)
	var key_q := _vertex_key(q)
	if key_p < key_q:
		return "%s|%s" % [key_p, key_q]
	return "%s|%s" % [key_q, key_p]


func _ensure_scene_roots() -> void:
	_facets_root = _get_or_create_child_node("Facets", _facets_root)


func _get_or_create_child_node(node_name: String, cached: Node3D) -> Node3D:
	if cached != null and is_instance_valid(cached):
		return cached

	var existing := get_node_or_null(NodePath(node_name)) as Node3D
	if existing:
		return existing

	var node := Node3D.new()
	node.name = node_name
	add_child(node)
	_set_editor_owner(node)
	return node


func _set_editor_owner(node: Node) -> void:
	if not _should_persist_editor_children():
		return
	var edited_root := get_tree().edited_scene_root
	if edited_root:
		node.owner = edited_root


func _should_persist_editor_children() -> bool:
	# Generated facets are rebuilt from exports; never save them into .tscn files.
	return false


func _remove_stale_generated_children() -> void:
	for child in get_children():
		if child == _facets_root:
			continue
		if child.name == "Facets":
			continue
		if child.name == "WindStrand":
			continue
		remove_child(child)
		child.free()


func _update_tile_base_colors() -> void:
	if _facets_root == null:
		return
	for child in _facets_root.get_children():
		if child is Tile:
			(child as Tile).set_base_color(albedo_color)


func _clear_facets() -> void:
	if _facets_root == null:
		return
	for child in _facets_root.get_children():
		_facets_root.remove_child(child)
		child.free()


func _add_tile(inset_corners: Array, pre_inset_corners: Array) -> Tile:
	var tile: Tile = TILE_SCENE.instantiate()
	tile.name = "Tile%d" % _next_tile_id
	_next_tile_id += 1
	tile.configure(inset_corners, pre_inset_corners, albedo_color)
	_facets_root.add_child(tile)
	_set_editor_owner(tile)
	return tile


func _get_pole_alignment_basis() -> Basis:
	var phi := (1.0 + sqrt(5.0)) * 0.5
	# Vertices 1 and 2 are opposite; align vertex 1 to +Y so the poles are icosahedron vertices.
	var north_vertex := Vector3(1.0, phi, 0.0).normalized()
	return _basis_from_direction_to_direction(north_vertex, Vector3.UP)


func _basis_from_direction_to_direction(from_direction: Vector3, to_direction: Vector3) -> Basis:
	var from := from_direction.normalized()
	var to := to_direction.normalized()
	var axis := from.cross(to)

	if axis.length_squared() < 0.000001:
		if from.dot(to) > 0.0:
			return Basis.IDENTITY
		axis = from.cross(Vector3.FORWARD)
		if axis.length_squared() < 0.000001:
			axis = from.cross(Vector3.RIGHT)
		axis = axis.normalized()
		return Basis(Quaternion(axis, PI))

	axis = axis.normalized()
	var angle := from.angle_to(to)
	return Basis(Quaternion(axis, angle))


func _build_vertices(size: float) -> PackedVector3Array:
	var phi := (1.0 + sqrt(5.0)) * 0.5
	var raw_vertices: Array[Vector3] = [
		Vector3(-1.0, phi, 0.0),
		Vector3(1.0, phi, 0.0),
		Vector3(-1.0, -phi, 0.0),
		Vector3(1.0, -phi, 0.0),
		Vector3(0.0, -1.0, phi),
		Vector3(0.0, 1.0, phi),
		Vector3(0.0, -1.0, -phi),
		Vector3(0.0, 1.0, -phi),
		Vector3(phi, 0.0, -1.0),
		Vector3(phi, 0.0, 1.0),
		Vector3(-phi, 0.0, -1.0),
		Vector3(-phi, 0.0, 1.0),
	]

	var alignment := _get_pole_alignment_basis()
	var vertices := PackedVector3Array()
	vertices.resize(raw_vertices.size())
	for i in raw_vertices.size():
		vertices[i] = alignment * raw_vertices[i].normalized() * size
	return vertices


func _build_faces() -> Array[PackedInt32Array]:
	return [
		PackedInt32Array([0, 11, 5]),
		PackedInt32Array([0, 5, 1]),
		PackedInt32Array([0, 1, 7]),
		PackedInt32Array([0, 7, 10]),
		PackedInt32Array([0, 10, 11]),
		PackedInt32Array([1, 5, 9]),
		PackedInt32Array([5, 11, 4]),
		PackedInt32Array([11, 10, 2]),
		PackedInt32Array([10, 7, 6]),
		PackedInt32Array([7, 1, 8]),
		PackedInt32Array([3, 9, 4]),
		PackedInt32Array([3, 4, 2]),
		PackedInt32Array([3, 2, 6]),
		PackedInt32Array([3, 6, 8]),
		PackedInt32Array([3, 8, 9]),
		PackedInt32Array([4, 9, 5]),
		PackedInt32Array([2, 4, 11]),
		PackedInt32Array([6, 2, 10]),
		PackedInt32Array([8, 6, 7]),
		PackedInt32Array([9, 8, 1]),
	]


func _face_point(a: Vector3, b: Vector3, c: Vector3, i: int, j: int, subdivisions: int) -> Vector3:
	var weight_a := float(subdivisions - i - j)
	var weight_b := float(i)
	var weight_c := float(j)
	return (a * weight_a + b * weight_b + c * weight_c) / float(subdivisions)


func _subdivide_face(a: Vector3, b: Vector3, c: Vector3, subdivisions: int) -> Array:
	var triangles: Array = []
	var grid: Dictionary = {}

	for i in subdivisions + 1:
		for j in subdivisions + 1 - i:
			grid[Vector2i(i, j)] = _face_point(a, b, c, i, j, subdivisions)

	for i in subdivisions:
		for j in subdivisions - i:
			var p00: Vector3 = grid[Vector2i(i, j)]
			var p10: Vector3 = grid[Vector2i(i + 1, j)]
			var p01: Vector3 = grid[Vector2i(i, j + 1)]
			triangles.append([p00, p10, p01])

			if i + j < subdivisions - 1:
				var p11: Vector3 = grid[Vector2i(i + 1, j + 1)]
				triangles.append([p10, p11, p01])

	return triangles


func _inset_triangle(a: Vector3, b: Vector3, c: Vector3, inset_amount: float) -> Array[Vector3]:
	return _inset_polygon([a, b, c], inset_amount)


func _inset_polygon(corners: Array, inset_amount: float) -> Array[Vector3]:
	var points := _array_to_vector3(corners)
	if inset_amount <= 0.0:
		return points

	var scale := 1.0 - inset_amount
	var centroid := Vector3.ZERO
	for point in points:
		centroid += point
	centroid /= float(points.size())

	var result: Array[Vector3] = []
	for point in points:
		result.append(centroid + (point - centroid) * scale)
	return result
