extends SceneTree
## Generates the static Hallwyl Museum model scene used by the map.
##
## Run from the project root:
##   godot --headless --path . --script res://tools/generate_hallwyl_scene.gd

const MODEL_PATH := "res://assets/map_assets/the_hallwyl_museum_1st_floor_combined.glb"
const OUTPUT_PATH := "res://scenes/objects/hallwyl_museum.scn"
const GENERATED_BY := "res://tools/generate_hallwyl_scene.gd"
const MODEL_URL := "https://sketchfab.com/3d-models/the-hallwyl-museum-1st-floor-combined-f74eefe9f1cd4a2795a689451e723ee9"
const LICENSE_URL := "https://creativecommons.org/licenses/by/4.0/"
const COLLISION_EXCLUDED_MESHES := [&"Floor Plan_0"]


func _initialize() -> void:
	var source := load(MODEL_PATH) as PackedScene
	if source == null:
		push_error("Could not load Hallwyl Museum GLB: %s" % MODEL_PATH)
		quit(1)
		return

	var model := source.instantiate()
	if not model is Node3D:
		push_error("Hallwyl Museum GLB root is not Node3D.")
		model.free()
		quit(1)
		return

	var root := StaticBody3D.new()
	root.name = "HallwylMuseumModel"
	root.collision_layer = 1
	root.collision_mask = 0
	root.set_meta("generated_by", GENERATED_BY)
	root.set_meta("source_glb", MODEL_PATH)
	root.set_meta("source_model", MODEL_URL)
	root.set_meta("title", "The Hallwyl Museum 1st Floor Combined")
	root.set_meta("creator", "Thomas Flynn")
	root.set_meta("original_models_creator", "Erik Lernestål")
	root.set_meta("license", "CC BY 4.0")
	root.set_meta("license_url", LICENSE_URL)
	root.set_meta("changes", "Converted to a Godot map and generated concave collision meshes.")

	model.name = "Model"
	root.add_child(model)
	model.owner = root

	var collision_count := _add_collision_shapes(root, model)
	if collision_count == 0:
		push_error("No collision shapes could be generated for Hallwyl Museum.")
		root.free()
		quit(1)
		return

	var packed_scene := PackedScene.new()
	var pack_error := packed_scene.pack(root)
	if pack_error != OK:
		push_error("Could not pack Hallwyl Museum scene (error %d)." % pack_error)
		root.free()
		quit(1)
		return

	var save_error := ResourceSaver.save(packed_scene, OUTPUT_PATH, ResourceSaver.FLAG_COMPRESS)
	root.free()
	if save_error != OK:
		push_error("Could not save %s (error %d)." % [OUTPUT_PATH, save_error])
		quit(1)
		return

	print("Generated %s with %d concave collision shapes." % [OUTPUT_PATH, collision_count])
	quit()


func _add_collision_shapes(root: StaticBody3D, model: Node3D) -> int:
	var meshes: Array[Dictionary] = []
	_collect_meshes(model, Transform3D.IDENTITY, meshes)

	var collision_index := 0
	for mesh_info in meshes:
		if (mesh_info.name as StringName) in COLLISION_EXCLUDED_MESHES:
			continue
		var mesh := mesh_info.mesh as Mesh
		var source_shape := mesh.create_trimesh_shape() as ConcavePolygonShape3D
		if source_shape == null or source_shape.get_faces().is_empty():
			continue

		var transformed_faces := PackedVector3Array()
		var mesh_transform := mesh_info.transform as Transform3D
		for vertex in source_shape.get_faces():
			transformed_faces.append(mesh_transform * vertex)

		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(transformed_faces)
		var collision := CollisionShape3D.new()
		collision_index += 1
		collision.name = "Collision%d" % collision_index
		collision.shape = shape
		root.add_child(collision)
		collision.owner = root

	return collision_index


func _collect_meshes(node: Node, parent_transform: Transform3D, meshes: Array[Dictionary]) -> void:
	var node_transform := parent_transform
	if node is Node3D:
		node_transform = parent_transform * (node as Node3D).transform

	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			meshes.append({
				"name": mesh_instance.name,
				"mesh": mesh_instance.mesh,
				"transform": node_transform,
			})

	for child in node.get_children():
		_collect_meshes(child, node_transform, meshes)
