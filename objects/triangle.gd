@tool
extends MeshInstance3D


func set_corners(a: Vector3, b: Vector3, c: Vector3) -> void:
	mesh = _build_triangle_mesh(a, b, c)


func apply_surface_material(material: Material) -> void:
	material_override = material


func _build_triangle_mesh(a: Vector3, b: Vector3, c: Vector3) -> ArrayMesh:
	var normal := (c - a).cross(b - a).normalized()

	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface_tool.set_normal(normal)
	surface_tool.add_vertex(a)
	surface_tool.set_normal(normal)
	surface_tool.add_vertex(c)
	surface_tool.set_normal(normal)
	surface_tool.add_vertex(b)

	return surface_tool.commit()
