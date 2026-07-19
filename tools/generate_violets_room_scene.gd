extends SceneTree
## Generates the scaled, collidable Violets Room model scene used by the map.
##
## The OpenMVS reconstruction is authored in small reconstruction units. Its
## floor is at Y=0 and its ceiling is about 0.04 units high. A scale of 250
## makes that ceiling roughly 10 Godot metres high, so the 1.8 m human avatar
## reads as a large, approximately quarter-scale doll in the real room.
##
## Run from the project root:
##   godot --headless --path . --script res://tools/generate_violets_room_scene.gd

const MODEL_PATH := "res://assets/maps/violets_room.glb"
const OUTPUT_PATH := "res://scenes/objects/violets_room.scn"
const GENERATED_BY := "res://tools/generate_violets_room_scene.gd"
const ROOM_SCALE := 250.0
# Best-fit floor plane from the reconstructed rug and wood floor. OpenMVS did
# not align the room to glTF's Y-up axis, so level and center it during baking.
const SOURCE_FLOOR_NORMAL := Vector3(0.083, 1.0, 0.264)
const SOURCE_ROOM_CENTER := Vector3(-0.02, 0.0308, 0.02)


func _initialize() -> void:
	var source := load(MODEL_PATH) as PackedScene
	if source == null:
		push_error("Could not load Violets Room GLB: %s" % MODEL_PATH)
		quit(1)
		return

	var model := source.instantiate()
	if not model is Node3D:
		push_error("Violets Room GLB root is not Node3D.")
		model.free()
		quit(1)
		return

	var root := StaticBody3D.new()
	root.name = "VioletsRoomModel"
	root.collision_layer = 1
	root.collision_mask = 0
	root.set_meta("generated_by", GENERATED_BY)
	root.set_meta("source_glb", MODEL_PATH)
	root.set_meta("room_scale", ROOM_SCALE)
	root.set_meta("changes", "Scaled for quarter-size doll play and supplied with concave collision.")

	model.name = "Model"
	var source_up := SOURCE_FLOOR_NORMAL.normalized()
	var level_rotation := Quaternion(
			source_up.cross(Vector3.UP).normalized(), source_up.angle_to(Vector3.UP))
	var level_basis := Basis(level_rotation).scaled(Vector3.ONE * ROOM_SCALE)
	# The reconstruction's interior lies below its floor plane. Reflect the
	# already-leveled model through that plane so players stand inside the room
	# rather than on its exterior shell.
	var vertical_flip := Basis.from_scale(Vector3(1, -1, 1))
	var model_basis := vertical_flip * level_basis
	model.transform = Transform3D(
			model_basis, -(model_basis * SOURCE_ROOM_CENTER))
	root.add_child(model)
	model.owner = root

	var collision_count := _add_collision_shapes(root, model)
	if collision_count == 0:
		push_error("No collision shapes could be generated for Violets Room.")
		root.free()
		quit(1)
		return

	var packed_scene := PackedScene.new()
	var pack_error := packed_scene.pack(root)
	if pack_error != OK:
		push_error("Could not pack Violets Room scene (error %d)." % pack_error)
		root.free()
		quit(1)
		return

	var save_error := ResourceSaver.save(packed_scene, OUTPUT_PATH, ResourceSaver.FLAG_COMPRESS)
	root.free()
	if save_error != OK:
		push_error("Could not save %s (error %d)." % [OUTPUT_PATH, save_error])
		quit(1)
		return

	print("Generated %s with %d concave collision shapes at %.0fx scale." % [
			OUTPUT_PATH, collision_count, ROOM_SCALE])
	quit()


func _add_collision_shapes(root: StaticBody3D, model: Node3D) -> int:
	var meshes: Array[Dictionary] = []
	_collect_meshes(model, Transform3D.IDENTITY, meshes)

	var collision_index := 0
	for mesh_info in meshes:
		var mesh := mesh_info.mesh as Mesh
		var source_shape := mesh.create_trimesh_shape() as ConcavePolygonShape3D
		if source_shape == null or source_shape.get_faces().is_empty():
			continue

		var transformed_faces := PackedVector3Array()
		var mesh_transform := mesh_info.transform as Transform3D
		for vertex in source_shape.get_faces():
			transformed_faces.append(mesh_transform * vertex)

		var shape := ConcavePolygonShape3D.new()
		# Photogrammetry winding is inconsistent around thin rugs, floors, and
		# furniture. Two-sided collision keeps those scanned surfaces walkable.
		shape.backface_collision = true
		shape.set_faces(transformed_faces)
		var collision := CollisionShape3D.new()
		collision_index += 1
		collision.name = "Collision%d" % collision_index
		collision.shape = shape
		root.add_child(collision)
		collision.owner = root

	return collision_index


func _collect_meshes(node: Node, parent_transform: Transform3D,
		meshes: Array[Dictionary]) -> void:
	var node_transform := parent_transform
	if node is Node3D:
		node_transform = parent_transform * (node as Node3D).transform

	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			meshes.append({
				"mesh": mesh_instance.mesh,
				"transform": node_transform,
			})

	for child in node.get_children():
		_collect_meshes(child, node_transform, meshes)
