@tool
extends MeshInstance3D


func set_corners(a: Vector3, b: Vector3, c: Vector3) -> void:
	mesh = _build_triangle_mesh(a, b, c)


func apply_surface_material(material: Material) -> void:
	material_override = material


func _build_triangle_mesh(a: Vector3, b: Vector3, c: Vector3) -> ArrayMesh:
	var normal := (c - a).cross(b - a)
	if normal.length_squared() < 0.000001:
		normal = Vector3.UP
	else:
		normal = normal.normalized()
	# Vertex order stays clockwise from the outside. The cross product points inward, so flip it.
	var centroid := (a + b + c) / 3.0
	if normal.dot(centroid) < 0.0:
		normal = -normal

	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface_tool.set_normal(normal)
	surface_tool.add_vertex(a)
	surface_tool.set_normal(normal)
	surface_tool.add_vertex(c)
	surface_tool.set_normal(normal)
	surface_tool.add_vertex(b)

	return surface_tool.commit()
