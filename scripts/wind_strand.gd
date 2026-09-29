@tool
class_name WindStrand
extends Node3D

@export var interval_seconds: float = 2.0:
	set(value):
		interval_seconds = maxf(value, 0.05)

@export var origins_per_burst: int = 3:
	set(value):
		origins_per_burst = maxi(value, 1)

@export_range(0, 32, 1) var hop_count: int = 5

@export var strand_length: float = 0.35:
	set(value):
		strand_length = maxf(value, 0.01)

@export var strand_speed: float = 0.5:
	set(value):
		strand_speed = maxf(value, 0.01)

@export var tile_strand_cooldown_seconds: float = 2.0:
	set(value):
		tile_strand_cooldown_seconds = maxf(value, 0.0)

@export var ribbon_width: float = 0.02:
	set(value):
		ribbon_width = maxf(value, 0.001)

@export var surface_lift: float = 0.012:
	set(value):
		surface_lift = maxf(value, 0.0)

@export var wave_amplitude: float = 0.006:
	set(value):
		wave_amplitude = maxf(value, 0.0)

@export var wave_frequency: float = 5.0:
	set(value):
		wave_frequency = maxf(value, 0.0)

@export var wave_speed: float = 4.0

@export var ribbon_color: Color = Color(0.85, 0.92, 1.0, 0.275)

@export var curve_samples_per_unit: float = 24.0:
	set(value):
		curve_samples_per_unit = maxf(value, 4.0)

const _SAMPLES_PER_UNIT := 24.0

var _eligible_tiles: Array[Tile] = []
var _active_ribbons: Array[_Ribbon] = []
var _tile_last_strand_through: Dictionary = {}
var _burst_timer: float = 0.0
var _burst_rng: RandomNumberGenerator


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_burst_rng = RandomNumberGenerator.new()
	_burst_rng.randomize()
	_burst_timer = interval_seconds


func refresh(tiles: Array) -> void:
	_clear_active_ribbons()
	_tile_last_strand_through.clear()
	_eligible_tiles.clear()
	for item in tiles:
		if item is Tile:
			var tile := item as Tile
			if not tile.direction_targets.is_empty():
				_eligible_tiles.append(tile)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	_update_ribbons(delta)

	_burst_timer -= delta
	if _burst_timer > 0.0:
		return
	_burst_timer = interval_seconds
	_emit_burst()


func _emit_burst() -> void:
	if _eligible_tiles.is_empty():
		return

	var pool := _build_prioritized_origin_pool()
	var count := mini(origins_per_burst, pool.size())
	for i in count:
		_emit_from_origin(pool[i])


func _build_prioritized_origin_pool() -> Array[Tile]:
	var now := Time.get_ticks_msec() * 0.001
	var preferred: Array[Tile] = []
	var fallback: Array[Tile] = []
	for tile in _eligible_tiles:
		if not is_instance_valid(tile):
			continue
		if _seconds_since_strand_through(tile, now) >= tile_strand_cooldown_seconds:
			preferred.append(tile)
		else:
			fallback.append(tile)
	_shuffle_tiles(preferred)
	_shuffle_tiles(fallback)
	var pool: Array[Tile] = []
	pool.append_array(preferred)
	pool.append_array(fallback)
	return pool


func _seconds_since_strand_through(tile: Tile, now: float) -> float:
	if not _tile_last_strand_through.has(tile):
		return INF
	return now - float(_tile_last_strand_through[tile])


func _mark_tiles_strand_through(tiles: Dictionary, now: float) -> void:
	for tile in tiles:
		if tile is Tile and is_instance_valid(tile):
			_tile_last_strand_through[tile] = now


func _emit_from_origin(origin: Tile) -> void:
	if not is_instance_valid(origin):
		return

	var tiles_touched: Dictionary = {}
	tiles_touched[origin] = true

	for first_target in origin.direction_targets:
		if first_target == null or not is_instance_valid(first_target):
			continue
		var tile_paths := _expand_tile_paths(origin, first_target, hop_count)
		for tile_path in tile_paths:
			for tile in tile_path:
				if is_instance_valid(tile):
					tiles_touched[tile] = true
			var snapshot := _snapshot_path(tile_path)
			if snapshot["points"].size() < 2:
				continue
			var ribbon := _Ribbon.new()
			ribbon.setup(snapshot, self)
			_active_ribbons.append(ribbon)

	_mark_tiles_strand_through(tiles_touched, Time.get_ticks_msec() * 0.001)


func _expand_tile_paths(origin: Tile, first_target: Tile, hops_remaining: int) -> Array:
	var seed_path: Array[Tile] = [origin, first_target]
	return _expand_branch(seed_path, hops_remaining)


func _expand_branch(tile_path: Array[Tile], hops_remaining: int) -> Array:
	if hops_remaining <= 0:
		return [tile_path]

	var current := tile_path[-1]
	if not is_instance_valid(current):
		return [tile_path]

	var targets := _valid_outgoing(current)
	if targets.is_empty():
		return [tile_path]

	if targets.size() == 1:
		var continued: Array[Tile] = tile_path.duplicate()
		continued.append(targets[0])
		return _expand_branch(continued, hops_remaining - 1)

	var results: Array = []
	for target in targets:
		var branch: Array[Tile] = tile_path.duplicate()
		branch.append(target)
		results.append_array(_expand_branch(branch, hops_remaining - 1))
	return results


func _valid_outgoing(tile: Tile) -> Array[Tile]:
	var result: Array[Tile] = []
	for target in tile.direction_targets:
		if target != null and is_instance_valid(target):
			result.append(target)
	return result


func _snapshot_path(tile_path: Array[Tile]) -> Dictionary:
	var control := _build_path_control_points(tile_path)
	var smoothed := _resample_catmull_rom(control["points"], control["normals"])
	var points: PackedVector3Array = smoothed["points"]
	var normals: PackedVector3Array = smoothed["normals"]
	var arc_lengths := _build_arc_lengths(points)
	return {
		"points": points,
		"normals": normals,
		"arc_lengths": arc_lengths,
		"path_length": arc_lengths[arc_lengths.size() - 1] if not arc_lengths.is_empty() else 0.0,
	}


func _build_path_control_points(tile_path: Array[Tile]) -> Dictionary:
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	var count := tile_path.size()
	for i in count:
		var tile := tile_path[i]
		if not is_instance_valid(tile):
			continue
		points.append(_world_lifted_centroid(tile))
		normals.append(_world_outward_normal(tile))
		if i >= count - 1:
			continue
		var next_tile := tile_path[i + 1]
		if not is_instance_valid(next_tile):
			continue
		var bridge := _world_bridge_point(tile, next_tile)
		points.append(bridge["position"])
		normals.append(bridge["normal"])

	return {"points": points, "normals": normals}


func _local_connection_point(from_tile: Tile, to_tile: Tile) -> Vector3:
	var inset := from_tile.get_inset_corners()
	if inset.is_empty():
		return from_tile.get_inset_centroid()

	var corner_count := inset.size()
	for edge_index in from_tile.neighbours.size():
		if from_tile.neighbours[edge_index] == to_tile:
			var p0: Vector3 = inset[edge_index]
			var p1: Vector3 = inset[(edge_index + 1) % corner_count]
			return (p0 + p1) * 0.5

	for corner_index in from_tile.opposites.size():
		if from_tile.opposites[corner_index] == to_tile:
			return inset[corner_index]

	return from_tile.get_inset_centroid().lerp(to_tile.get_inset_centroid(), 0.5)


func _world_bridge_point(from_tile: Tile, to_tile: Tile) -> Dictionary:
	var local_point := _local_connection_point(from_tile, to_tile)
	var from_centroid := from_tile.get_inset_centroid()
	var to_centroid := to_tile.get_inset_centroid()
	var from_normal := _local_outward_normal(from_tile, from_centroid)
	var to_normal := _local_outward_normal(to_tile, to_centroid)
	var world_normal := (
		from_tile.global_transform.basis * from_normal + to_tile.global_transform.basis * to_normal
	).normalized()
	var world_base := from_tile.global_transform * local_point
	return {
		"position": world_base + world_normal * surface_lift,
		"normal": world_normal,
	}


func _resample_catmull_rom(control_points: PackedVector3Array, control_normals: PackedVector3Array) -> Dictionary:
	var count := control_points.size()
	if count == 0:
		return {"points": control_points, "normals": control_normals}
	if count == 1:
		return {"points": control_points, "normals": control_normals}

	var out_points := PackedVector3Array()
	var out_normals := PackedVector3Array()

	for seg in range(count - 1):
		var p0 := _catmull_control(control_points, seg - 1)
		var p1 := control_points[seg]
		var p2 := control_points[seg + 1]
		var p3 := _catmull_control(control_points, seg + 2)
		var n1 := control_normals[seg]
		var n2 := control_normals[seg + 1]
		var steps := maxi(int(ceil(p1.distance_to(p2) * curve_samples_per_unit)), 2)

		for step in range(steps):
			if seg > 0 and step == 0:
				continue
			var t := float(step) / float(steps - 1) if steps > 1 else 0.0
			out_points.append(_catmull_rom_point(p0, p1, p2, p3, t))
			out_normals.append(n1.lerp(n2, t).normalized())

	out_points.append(control_points[count - 1])
	out_normals.append(control_normals[count - 1])
	return {"points": out_points, "normals": out_normals}


func _catmull_control(points: PackedVector3Array, index: int) -> Vector3:
	if index < 0:
		return points[0]
	if index >= points.size():
		return points[points.size() - 1]
	return points[index]


func _catmull_rom_point(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * (
		(2.0 * p1)
		+ (-p0 + p2) * t
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
	)


func _world_lifted_centroid(tile: Tile) -> Vector3:
	var local_centroid := tile.get_inset_centroid()
	var local_normal := _local_outward_normal(tile, local_centroid)
	return tile.global_transform * (local_centroid + local_normal * surface_lift)


func _world_outward_normal(tile: Tile) -> Vector3:
	var local_centroid := tile.get_inset_centroid()
	var local_normal := _local_outward_normal(tile, local_centroid)
	return (tile.global_transform.basis * local_normal).normalized()


func _local_outward_normal(tile: Tile, centroid: Vector3) -> Vector3:
	var corners := tile.get_pre_inset_corners()
	if corners.size() < 3:
		return Vector3.UP
	var normal := (corners[2] - corners[0]).cross(corners[1] - corners[0])
	if normal.length_squared() < 0.000001:
		return Vector3.UP
	normal = normal.normalized()
	if normal.dot(centroid) < 0.0:
		normal = -normal
	return normal


func _build_arc_lengths(points: PackedVector3Array) -> PackedFloat32Array:
	var cumulative := PackedFloat32Array()
	cumulative.append(0.0)
	for i in range(1, points.size()):
		cumulative.append(cumulative[i - 1] + points[i - 1].distance_to(points[i]))
	return cumulative


func _update_ribbons(delta: float) -> void:
	var wave_time := Time.get_ticks_msec() * 0.001
	var i := 0
	while i < _active_ribbons.size():
		var ribbon: _Ribbon = _active_ribbons[i]
		if ribbon.update(delta, wave_time, self):
			_active_ribbons.remove_at(i)
		else:
			i += 1


func _clear_active_ribbons() -> void:
	for ribbon in _active_ribbons:
		ribbon.free_mesh()
	_active_ribbons.clear()


func _shuffle_tiles(tiles: Array[Tile]) -> void:
	for i in range(tiles.size() - 1, 0, -1):
		var j := _burst_rng.randi_range(0, i)
		var tmp := tiles[i]
		tiles[i] = tiles[j]
		tiles[j] = tmp


func _segment_index_for_s(s: float, arc_lengths: PackedFloat32Array) -> int:
	var last_seg := arc_lengths.size() - 2
	if last_seg < 0:
		return 0
	for i in range(last_seg + 1):
		if s < arc_lengths[i + 1] - 0.000001:
			return i
	return last_seg


func _sample_path(
	points: PackedVector3Array,
	normals: PackedVector3Array,
	arc_lengths: PackedFloat32Array,
	s: float
) -> Dictionary:
	if points.is_empty():
		return {"position": Vector3.ZERO, "normal": Vector3.UP, "tangent": Vector3.FORWARD}
	if s <= 0.0:
		var tangent := (points[1] - points[0]).normalized() if points.size() > 1 else Vector3.FORWARD
		return {"position": points[0], "normal": normals[0], "tangent": tangent}

	var path_length := arc_lengths[arc_lengths.size() - 1]
	if s >= path_length:
		var last := points.size() - 1
		var tangent := (points[last] - points[last - 1]).normalized() if last > 0 else Vector3.FORWARD
		return {"position": points[last], "normal": normals[last], "tangent": tangent}

	var seg_index := _segment_index_for_s(s, arc_lengths)
	var seg_start := arc_lengths[seg_index]
	var seg_end := arc_lengths[seg_index + 1]
	var seg_len := maxf(seg_end - seg_start, 0.000001)
	var t := (s - seg_start) / seg_len
	var p0 := points[seg_index]
	var p1 := points[seg_index + 1]
	var n0 := normals[seg_index]
	var n1 := normals[seg_index + 1]
	var prev_index := maxi(seg_index - 1, 0)
	var next_index := mini(seg_index + 2, points.size() - 1)
	var tangent := points[next_index] - points[prev_index]
	if tangent.length_squared() < 0.000001:
		tangent = p1 - p0
	tangent = tangent.normalized()
	return {
		"position": p0.lerp(p1, t),
		"normal": n0.lerp(n1, t).normalized(),
		"tangent": tangent,
	}


func _build_ribbon_mesh(
	points: PackedVector3Array,
	normals: PackedVector3Array,
	arc_lengths: PackedFloat32Array,
	path_length: float,
	tail_s: float,
	head_s: float,
	wave_time: float,
	owner: WindStrand
) -> ArrayMesh:
	if head_s - tail_s <= 0.00001:
		return null

	var span := head_s - tail_s
	var sample_count := maxi(int(ceil(span * _SAMPLES_PER_UNIT)), 2)
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var half_width := owner.ribbon_width * 0.5

	for i in sample_count:
		var u := float(i) / float(sample_count - 1)
		var s := lerpf(tail_s, head_s, u)
		var sample := _sample_path(points, normals, arc_lengths, s)
		var pos: Vector3 = sample["position"]
		var normal: Vector3 = sample["normal"]
		var tangent: Vector3 = sample["tangent"]

		var binormal := tangent.cross(normal)
		if binormal.length_squared() < 0.000001:
			binormal = normal.cross(Vector3.UP)
		binormal = binormal.normalized()

		var wave := sin(s * owner.wave_frequency + wave_time * owner.wave_speed) * owner.wave_amplitude
		pos += binormal * wave

		var left := pos - binormal * half_width
		var right := pos + binormal * half_width
		var alpha := u * owner.ribbon_color.a
		var vert_color := Color(owner.ribbon_color.r, owner.ribbon_color.g, owner.ribbon_color.b, alpha)

		vertices.append(owner.to_local(left))
		vertices.append(owner.to_local(right))
		colors.append(vert_color)
		colors.append(vert_color)

	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLE_STRIP, arrays)
	return mesh


class _Ribbon:
	var points: PackedVector3Array
	var normals: PackedVector3Array
	var arc_lengths: PackedFloat32Array
	var path_length: float
	var tail_s: float = 0.0
	var head_s: float = 0.0
	var window_length: float
	var mesh_instance: MeshInstance3D
	var material: StandardMaterial3D

	func setup(snapshot: Dictionary, owner: WindStrand) -> void:
		points = snapshot["points"]
		normals = snapshot["normals"]
		arc_lengths = snapshot["arc_lengths"]
		path_length = snapshot["path_length"]
		window_length = minf(owner.strand_length, path_length)
		tail_s = 0.0
		head_s = 0.0

		material = StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.vertex_color_use_as_albedo = true
		material.albedo_color = Color.WHITE
		material.disable_ambient_light = true

		mesh_instance = MeshInstance3D.new()
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh_instance.material_override = material
		owner.add_child(mesh_instance)

	func update(delta: float, wave_time: float, owner: WindStrand) -> bool:
		var ds := owner.strand_speed * delta
		var max_span := window_length
		var extruding := head_s - tail_s < max_span - 0.00001 and tail_s <= 0.00001

		if extruding:
			head_s = minf(head_s + ds, minf(max_span, path_length))
		else:
			tail_s += ds
			head_s = minf(tail_s + max_span, path_length)

		if tail_s >= path_length - 0.00001:
			free_mesh()
			return true
		return not _apply_mesh(wave_time, owner)

	func _apply_mesh(wave_time: float, owner: WindStrand) -> bool:
		var mesh: ArrayMesh = owner._build_ribbon_mesh(
			points,
			normals,
			arc_lengths,
			path_length,
			tail_s,
			head_s,
			wave_time,
			owner
		)
		if mesh == null:
			return head_s - tail_s <= 0.00001
		mesh_instance.mesh = mesh
		return true

	func free_mesh() -> void:
		if mesh_instance != null and is_instance_valid(mesh_instance):
			mesh_instance.queue_free()
			mesh_instance = null
