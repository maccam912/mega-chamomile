extends SceneTree
## Generates reusable StaticBody3D scenes for every Kenney GLB in the project.
##
## Run from the project root:
##   godot --headless --path . --script res://tools/generate_kenney_scenes.gd
##
## The scale is shared by the entire asset pack so the original size differences
## (for example, bottles versus trees) are preserved. At 3x, barrel.glb is about
## 1.03 m tall next to the project's 1.7 m player.

const MODEL_DIR := "res://assets/models"
const OUTPUT_DIR := "res://scenes/objects/kenney"
const GENERATED_BY := "res://tools/generate_kenney_scenes.gd"
const KENNEY_SCALE := 3.0

var _created := 0
var _updated := 0
var _skipped := 0
var _failed := 0
var _collision_shape_count := 0


func _initialize() -> void:
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	if error != OK and error != ERR_ALREADY_EXISTS:
		push_error("Could not create output directory %s (error %d)." % [OUTPUT_DIR, error])
		quit(1)
		return

	var model_paths: Array[String] = []
	_collect_glbs(MODEL_DIR, model_paths)
	model_paths.sort()

	if model_paths.is_empty():
		push_error("No GLB files found below %s." % MODEL_DIR)
		quit(1)
		return

	for model_path in model_paths:
		_generate_scene(model_path)

	print(
		(
			"Kenney scene generation complete: %d created, %d updated, %d skipped, "
			+ "%d failed; %d collision shapes across %d GLBs."
		)
		% [_created, _updated, _skipped, _failed, _collision_shape_count, model_paths.size()]
	)
	quit(1 if _failed > 0 else 0)


func _collect_glbs(directory_path: String, paths: Array[String]) -> void:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		push_error("Could not open model directory: %s" % directory_path)
		_failed += 1
		return

	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var entry_path := directory_path.path_join(entry)
			if directory.current_is_dir():
				_collect_glbs(entry_path, paths)
			elif entry.get_extension().to_lower() == "glb":
				paths.append(entry_path)
		entry = directory.get_next()
	directory.list_dir_end()


func _generate_scene(model_path: String) -> void:
	var relative_path := model_path.trim_prefix(MODEL_DIR + "/")
	var output_path := OUTPUT_DIR.path_join(relative_path.get_basename() + ".tscn")
	var output_parent := output_path.get_base_dir()
	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(output_parent)
	)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		push_error("Could not create %s (error %d)." % [output_parent, directory_error])
		_failed += 1
		return

	var existed := ResourceLoader.exists(output_path)
	if existed and not _is_generated_scene(output_path):
		push_warning("Skipping hand-authored scene: %s" % output_path)
		_skipped += 1
		return

	var source := load(model_path) as PackedScene
	if source == null:
		push_error("Could not load GLB as a PackedScene: %s" % model_path)
		_failed += 1
		return

	var model := source.instantiate()
	if not model is Node3D:
		push_error("GLB root is not Node3D: %s" % model_path)
		model.queue_free()
		_failed += 1
		return

	var root := StaticBody3D.new()
	root.name = _scene_name(relative_path.get_basename())
	root.set_meta("generated_by", GENERATED_BY)
	root.set_meta("source_glb", model_path)
	root.set_meta("kenney_scale", KENNEY_SCALE)

	model.name = "Model"
	model.scale *= KENNEY_SCALE
	root.add_child(model)
	model.owner = root

	var collision_count := _add_collision_shapes(root, model)
	if collision_count == 0:
		push_error("No mesh collision could be generated for %s" % model_path)
		root.free()
		_failed += 1
		return

	var packed_scene := PackedScene.new()
	var pack_error := packed_scene.pack(root)
	if pack_error != OK:
		push_error("Could not pack %s (error %d)." % [output_path, pack_error])
		root.free()
		_failed += 1
		return

	var save_error := ResourceSaver.save(packed_scene, output_path)
	root.free()
	if save_error != OK:
		push_error("Could not save %s (error %d)." % [output_path, save_error])
		_failed += 1
		return

	_collision_shape_count += collision_count
	if existed:
		_updated += 1
	else:
		_created += 1


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
		shape.set_faces(transformed_faces)

		var collision := CollisionShape3D.new()
		collision_index += 1
		collision.name = "Collision" if collision_index == 1 else "Collision%d" % collision_index
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
			meshes.append({"mesh": mesh_instance.mesh, "transform": node_transform})

	for child in node.get_children():
		_collect_meshes(child, node_transform, meshes)


func _is_generated_scene(scene_path: String) -> bool:
	var existing := load(scene_path) as PackedScene
	if existing == null:
		return false
	var instance := existing.instantiate()
	var is_generated: bool = (
		instance.has_meta("generated_by")
		and instance.get_meta("generated_by") == GENERATED_BY
	)
	instance.free()
	return is_generated


func _scene_name(relative_basename: String) -> String:
	var words := relative_basename.replace("/", "-").split("-", false)
	var result := ""
	for word in words:
		result += word.capitalize().replace(" ", "")
	return result
