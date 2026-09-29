class_name WindDirection
extends RefCounted


static func generate(
	tiles: Array[Tile],
	corner_tiles: Dictionary,
	seed: int
) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	var result: Dictionary = {}
	var sources: Dictionary = {}
	var assigned: Dictionary = {}
	var pending_branch: Array = []
	var seed_tiles: Array[Tile] = []

	for tile in tiles:
		if tile.is_pentagon() or corner_tiles.has(tile):
			seed_tiles.append(tile)

	seed_tiles.sort_custom(func(a: Tile, b: Tile) -> bool:
		return a.get_sort_index() < b.get_sort_index()
	)

	for tile in seed_tiles:
		if assigned.has(tile):
			continue
		var pool := _neighbor_pool_for_seed(tile, corner_tiles)
		pool.sort_custom(func(a: Tile, b: Tile) -> bool:
			return a.get_sort_index() < b.get_sort_index()
		)
		if pool.is_empty():
			assigned[tile] = true
			result[tile] = []
			continue
		var target_count := _seed_target_count(rng, pool.size()) if tile.is_pentagon() else 1
		var chosen := _pick_distinct_from_pool(pool, target_count, {}, assigned, rng)
		assigned[tile] = true
		result[tile] = chosen

	while true:
		pending_branch = _assign_branch_sources(pending_branch, assigned, result, sources, rng)

		var incoming: Dictionary = {}
		var wave: Array[Tile] = []
		var wave_seen: Dictionary = {}

		for source in assigned:
			if not result.has(source):
				continue
			for target in result[source] as Array:
				if target == null or assigned.has(target):
					continue
				if not wave_seen.has(target):
					wave_seen[target] = true
					wave.append(target)
				if not incoming.has(target):
					incoming[target] = []
				(incoming[target] as Array).append(source)

		if wave.is_empty():
			if pending_branch.is_empty():
				break
			continue

		wave.sort_custom(func(a: Tile, b: Tile) -> bool:
			return a.get_sort_index() < b.get_sort_index()
		)

		for tile in wave:
			var from_tiles: Array = incoming.get(tile, [])
			var forbidden: Dictionary = {}
			for source in from_tiles:
				forbidden[source] = true

			_store_incoming_sources(sources, tile, from_tiles)

			var all_options := _collect_all_direction_options(tile)
			assigned[tile] = true
			if all_options.is_empty():
				result[tile] = []
				continue

			var picked := _pick_prioritized_wind_target(all_options, forbidden, assigned, rng)
			if picked == null:
				result[tile] = []
				continue
			result[tile] = [picked]

			if _is_opposite_target(tile, picked):
				var extra := _pick_opposite_corner_neighbor(
					tile, picked, forbidden, [picked], assigned, rng
				)
				if extra != null:
					pending_branch.append({"tile": extra, "from": tile})

	return {"targets": result, "sources": sources}


static func _store_incoming_sources(sources: Dictionary, tile: Tile, from_tiles: Array) -> void:
	var typed: Array[Tile] = []
	var seen: Dictionary = {}
	for item in from_tiles:
		if item == null or not item is Tile:
			continue
		var source: Tile = item as Tile
		if seen.has(source):
			continue
		seen[source] = true
		typed.append(source)
	typed.sort_custom(func(a: Tile, b: Tile) -> bool:
		return a.get_sort_index() < b.get_sort_index()
	)
	sources[tile] = typed


static func _assign_branch_sources(
	pending_branch: Array,
	assigned: Dictionary,
	result: Dictionary,
	sources: Dictionary,
	rng: RandomNumberGenerator
) -> Array:
	if pending_branch.is_empty():
		return pending_branch

	pending_branch.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var tile_a: Tile = a["tile"]
		var tile_b: Tile = b["tile"]
		return tile_a.get_sort_index() < tile_b.get_sort_index()
	)

	var still_pending: Array = []
	for entry in pending_branch:
		var branch_tile: Tile = entry["tile"]
		var from_tile: Tile = entry["from"]
		if assigned.has(branch_tile):
			continue

		_store_incoming_sources(sources, branch_tile, [from_tile])

		var forbidden: Dictionary = {from_tile: true}
		var all_options := _collect_all_direction_options(branch_tile)
		assigned[branch_tile] = true
		if all_options.is_empty():
			result[branch_tile] = []
			continue

		var picked := _pick_prioritized_wind_target(all_options, forbidden, assigned, rng)
		if picked == null:
			result[branch_tile] = []
			continue
		result[branch_tile] = [picked]

		if _is_opposite_target(branch_tile, picked):
			var extra := _pick_opposite_corner_neighbor(
				branch_tile, picked, forbidden, [picked], assigned, rng
			)
			if extra != null:
				still_pending.append({"tile": extra, "from": branch_tile})

	return still_pending


static func _neighbor_pool_for_seed(tile: Tile, corner_tiles: Dictionary) -> Array[Tile]:
	var pool: Array[Tile] = []
	for neighbor in tile.neighbours:
		if neighbor == null:
			continue
		if corner_tiles.has(tile) and not tile.is_pentagon():
			if corner_tiles.has(neighbor):
				continue
		pool.append(neighbor)
	return pool


static func _seed_target_count(rng: RandomNumberGenerator, pool_size: int) -> int:
	var target_count := 1 if rng.randi_range(0, 1) == 0 else 2
	return mini(target_count, pool_size)


static func _pick_distinct_from_pool(
	pool: Array[Tile],
	count: int,
	forbidden: Dictionary,
	assigned: Dictionary,
	rng: RandomNumberGenerator
) -> Array[Tile]:
	var chosen: Array[Tile] = []
	var working := pool.duplicate()
	for _i in count:
		if working.is_empty():
			break
		var picked := _pick_prioritized_wind_target(working, forbidden, assigned, rng)
		if picked == null:
			break
		chosen.append(picked)
		working.erase(picked)
	return chosen


static func _collect_all_direction_options(tile: Tile) -> Array[Tile]:
	var options: Array[Tile] = []
	var seen: Dictionary = {}

	for neighbor in tile.neighbours:
		if neighbor == null or seen.has(neighbor):
			continue
		seen[neighbor] = true
		options.append(neighbor)

	for opposite in tile.opposites:
		if opposite == null or not opposite is Tile:
			continue
		if seen.has(opposite):
			continue
		seen[opposite] = true
		options.append(opposite)

	options.sort_custom(func(a: Tile, b: Tile) -> bool:
		return a.get_sort_index() < b.get_sort_index()
	)
	return options


static func _pick_prioritized_wind_target(
	all_options: Array[Tile],
	forbidden: Dictionary,
	assigned: Dictionary,
	rng: RandomNumberGenerator
) -> Tile:
	if all_options.is_empty():
		return null

	var without_wind: Array[Tile] = []
	var without_origin: Array[Tile] = []

	for option in all_options:
		if not forbidden.has(option):
			without_origin.append(option)
			if not assigned.has(option):
				without_wind.append(option)

	if not without_wind.is_empty():
		return without_wind[rng.randi_range(0, without_wind.size() - 1)]
	if not without_origin.is_empty():
		return without_origin[rng.randi_range(0, without_origin.size() - 1)]
	return all_options[rng.randi_range(0, all_options.size() - 1)]


static func _is_opposite_target(tile: Tile, target: Tile) -> bool:
	for opposite in tile.opposites:
		if opposite == target:
			return true
	return false


static func _pick_opposite_corner_neighbor(
	tile: Tile,
	opposite: Tile,
	forbidden: Dictionary,
	already_chosen: Array[Tile],
	assigned: Dictionary,
	rng: RandomNumberGenerator
) -> Tile:
	var corner_count := tile.neighbours.size()
	for corner_index in tile.opposites.size():
		if tile.opposites[corner_index] != opposite:
			continue
		var candidates: Array[Tile] = []
		var a: Tile = tile.neighbours[corner_index]
		var b: Tile = tile.neighbours[(corner_index - 1 + corner_count) % corner_count]
		for candidate in [a, b]:
			if candidate == null:
				continue
			if forbidden.has(candidate):
				continue
			if already_chosen.has(candidate):
				continue
			if not candidates.has(candidate):
				candidates.append(candidate)
		return _pick_prioritized_wind_target(candidates, forbidden, assigned, rng)
	return null
