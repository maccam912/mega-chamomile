@tool
class_name KeepOutVolume
extends Area3D
## Editor-placeable forbidden region. Entering it returns the locally
## controlled player to their assigned spawn through the normal recovery path.

@export var preview_through_geometry := false:
	set(value):
		preview_through_geometry = value
		_update_editor_preview()

var _preview_material: StandardMaterial3D


func _ready() -> void:
	_update_editor_preview()
	if Engine.is_editor_hint():
		return
	body_entered.connect(_on_body_entered)


func _update_editor_preview() -> void:
	var editor_preview := get_node_or_null("EditorPreview") as MeshInstance3D
	if editor_preview == null:
		return
	editor_preview.visible = Engine.is_editor_hint()
	# Every placed volume gets its own material so its X-ray toggle does not
	# change sibling copies made from the same PackedScene.
	if _preview_material == null:
		var source := editor_preview.get_active_material(0) as StandardMaterial3D
		if source != null:
			_preview_material = source.duplicate() as StandardMaterial3D
			editor_preview.material_override = _preview_material
	if _preview_material != null:
		_preview_material.no_depth_test = preview_through_geometry


func _on_body_entered(body: Node3D) -> void:
	var player := recovery_target_for(body)
	if player != null and player.is_local():
		player.recover_to_spawn()


## Standing avatars enter as their CharacterBody3D. Ragdolled avatars enter as
## one of the RigidBody3D parts below PaintableBody, so walk upward until the
## owning player is found.
static func recovery_target_for(body: Node) -> Node:
	var candidate := body
	while candidate != null:
		if candidate.has_method("is_local") and candidate.has_method("recover_to_spawn"):
			return candidate
		candidate = candidate.get_parent()
	return null
