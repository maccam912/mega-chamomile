class_name AvatarCatalog
extends RefCounted
## Data-only avatar authoring catalog. The paint/ragdoll implementation consumes
## this contract, so adding a body is a catalog entry rather than a new player.

const DEFAULT_ID := "human"
const ORDER := ["human", "cat", "dog"]

const AVATARS := {
	"human": {
		"label": "Human",
		"scale": 1.0,
		"parts": [
			{"name": "LowerLegL", "size": Vector3(0.22, 0.36, 0.22), "pos": Vector3(-0.13, 0.18, 0)},
			{"name": "LowerLegR", "size": Vector3(0.22, 0.36, 0.22), "pos": Vector3(0.13, 0.18, 0)},
			{"name": "UpperLegL", "size": Vector3(0.24, 0.38, 0.24), "pos": Vector3(-0.13, 0.55, 0)},
			{"name": "UpperLegR", "size": Vector3(0.24, 0.38, 0.24), "pos": Vector3(0.13, 0.55, 0)},
			{"name": "Pelvis", "size": Vector3(0.46, 0.22, 0.28), "pos": Vector3(0, 0.81, 0)},
			{"name": "Torso", "size": Vector3(0.5, 0.52, 0.28), "pos": Vector3(0, 1.15, 0)},
			{"name": "UpperArmL", "size": Vector3(0.17, 0.31, 0.17), "pos": Vector3(-0.34, 1.245, 0)},
			{"name": "UpperArmR", "size": Vector3(0.17, 0.31, 0.17), "pos": Vector3(0.34, 1.245, 0)},
			{"name": "LowerArmL", "size": Vector3(0.16, 0.34, 0.16), "pos": Vector3(-0.34, 0.92, 0)},
			{"name": "LowerArmR", "size": Vector3(0.16, 0.34, 0.16), "pos": Vector3(0.34, 0.92, 0)},
			{"name": "Head", "size": Vector3(0.36, 0.36, 0.36), "pos": Vector3(0, 1.59, 0)},
		],
		"joints": [
			{"type": "hinge", "name": "KneeL", "a": "UpperLegL", "b": "LowerLegL", "anchor": Vector3(-0.13, 0.36, 0), "lower": -0.08, "upper": 2.35},
			{"type": "hinge", "name": "KneeR", "a": "UpperLegR", "b": "LowerLegR", "anchor": Vector3(0.13, 0.36, 0), "lower": -0.08, "upper": 2.35},
			{"type": "hinge", "name": "ElbowL", "a": "UpperArmL", "b": "LowerArmL", "anchor": Vector3(-0.34, 1.09, 0), "lower": -2.35, "upper": 0.08},
			{"type": "hinge", "name": "ElbowR", "a": "UpperArmR", "b": "LowerArmR", "anchor": Vector3(0.34, 1.09, 0), "lower": -2.35, "upper": 0.08},
			{"type": "cone", "name": "HipL", "a": "Pelvis", "b": "UpperLegL", "anchor": Vector3(-0.13, 0.72, 0), "swing": 0.7, "twist": 0.35},
			{"type": "cone", "name": "HipR", "a": "Pelvis", "b": "UpperLegR", "anchor": Vector3(0.13, 0.72, 0), "swing": 0.7, "twist": 0.35},
			{"type": "cone", "name": "Waist", "a": "Pelvis", "b": "Torso", "anchor": Vector3(0, 0.91, 0), "swing": 0.4, "twist": 0.25},
			{"type": "cone", "name": "ShoulderL", "a": "Torso", "b": "UpperArmL", "anchor": Vector3(-0.3, 1.35, 0), "swing": 1.0, "twist": 0.65},
			{"type": "cone", "name": "ShoulderR", "a": "Torso", "b": "UpperArmR", "anchor": Vector3(0.3, 1.35, 0), "swing": 1.0, "twist": 0.65},
			{"type": "cone", "name": "Neck", "a": "Torso", "b": "Head", "anchor": Vector3(0, 1.41, 0), "swing": 0.35, "twist": 0.25},
		],
		"root_part": "Torso",
		"collision_shapes": [
			{"type": "capsule", "radius": 0.32, "height": 1.7,
				"pos": Vector3(0, 0.85, 0)},
		],
		"camera_pivot": Vector3(0, 1.45, 0), "orbit_length": 2.6,
		"nameplate_position": Vector3(0, 1.95, 0),
		"target_position": Vector3(0, 1.0, 0), "eye_position": Vector3(0, 1.45, 0),
		"gun_position": Vector3(0.34, 1.15, -0.3),
		"preview_height": 1.8,
	},
	"cat": {
		"label": "Cat",
		"scale": 0.72,
		"parts": [
			{"name": "Torso", "size": Vector3(0.44, 0.38, 0.82), "pos": Vector3(0, 0.67, 0)},
			{"name": "Chest", "size": Vector3(0.46, 0.43, 0.42), "pos": Vector3(0, 0.72, -0.42)},
			{"name": "Pelvis", "size": Vector3(0.42, 0.36, 0.4), "pos": Vector3(0, 0.65, 0.43)},
			{"name": "UpperFrontLegL", "size": Vector3(0.15, 0.34, 0.16), "pos": Vector3(-0.17, 0.43, -0.43)},
			{"name": "UpperFrontLegR", "size": Vector3(0.15, 0.34, 0.16), "pos": Vector3(0.17, 0.43, -0.43)},
			{"name": "LowerFrontLegL", "size": Vector3(0.14, 0.3, 0.15), "pos": Vector3(-0.17, 0.16, -0.43)},
			{"name": "LowerFrontLegR", "size": Vector3(0.14, 0.3, 0.15), "pos": Vector3(0.17, 0.16, -0.43)},
			{"name": "UpperBackLegL", "size": Vector3(0.19, 0.35, 0.2), "pos": Vector3(-0.16, 0.42, 0.43)},
			{"name": "UpperBackLegR", "size": Vector3(0.19, 0.35, 0.2), "pos": Vector3(0.16, 0.42, 0.43)},
			{"name": "LowerBackLegL", "size": Vector3(0.15, 0.28, 0.17), "pos": Vector3(-0.16, 0.15, 0.43)},
			{"name": "LowerBackLegR", "size": Vector3(0.15, 0.28, 0.17), "pos": Vector3(0.16, 0.15, 0.43)},
			{"name": "Head", "size": Vector3(0.4, 0.4, 0.38), "pos": Vector3(0, 1.03, -0.55)},
			{"name": "Muzzle", "size": Vector3(0.28, 0.2, 0.28), "pos": Vector3(0, 0.96, -0.84)},
			{"name": "EarL", "size": Vector3(0.13, 0.24, 0.13), "pos": Vector3(-0.13, 1.29, -0.55), "rot": Vector3(0, 0, -0.18)},
			{"name": "EarR", "size": Vector3(0.13, 0.24, 0.13), "pos": Vector3(0.13, 1.29, -0.55), "rot": Vector3(0, 0, 0.18)},
			{"name": "TailBase", "size": Vector3(0.14, 0.14, 0.45), "pos": Vector3(0, 0.78, 0.72), "rot": Vector3(-0.38, 0, 0)},
			{"name": "TailTip", "size": Vector3(0.12, 0.12, 0.42), "pos": Vector3(0, 0.98, 1.08), "rot": Vector3(-0.7, 0, 0)},
		],
		"joints": [
			{"type": "cone", "name": "SpineFront", "a": "Torso", "b": "Chest", "anchor": Vector3(0, 0.69, -0.25), "swing": 0.38, "twist": 0.28},
			{"type": "cone", "name": "SpineBack", "a": "Torso", "b": "Pelvis", "anchor": Vector3(0, 0.66, 0.27), "swing": 0.38, "twist": 0.28},
			{"type": "cone", "name": "ShoulderL", "a": "Chest", "b": "UpperFrontLegL", "anchor": Vector3(-0.17, 0.58, -0.43), "swing": 0.75, "twist": 0.35},
			{"type": "cone", "name": "ShoulderR", "a": "Chest", "b": "UpperFrontLegR", "anchor": Vector3(0.17, 0.58, -0.43), "swing": 0.75, "twist": 0.35},
			{"type": "hinge", "name": "FrontKneeL", "a": "UpperFrontLegL", "b": "LowerFrontLegL", "anchor": Vector3(-0.17, 0.3, -0.43), "lower": -0.2, "upper": 1.9},
			{"type": "hinge", "name": "FrontKneeR", "a": "UpperFrontLegR", "b": "LowerFrontLegR", "anchor": Vector3(0.17, 0.3, -0.43), "lower": -0.2, "upper": 1.9},
			{"type": "cone", "name": "HipL", "a": "Pelvis", "b": "UpperBackLegL", "anchor": Vector3(-0.16, 0.57, 0.43), "swing": 0.8, "twist": 0.4},
			{"type": "cone", "name": "HipR", "a": "Pelvis", "b": "UpperBackLegR", "anchor": Vector3(0.16, 0.57, 0.43), "swing": 0.8, "twist": 0.4},
			{"type": "hinge", "name": "BackKneeL", "a": "UpperBackLegL", "b": "LowerBackLegL", "anchor": Vector3(-0.16, 0.29, 0.43), "lower": -1.9, "upper": 0.2},
			{"type": "hinge", "name": "BackKneeR", "a": "UpperBackLegR", "b": "LowerBackLegR", "anchor": Vector3(0.16, 0.29, 0.43), "lower": -1.9, "upper": 0.2},
			{"type": "cone", "name": "Neck", "a": "Chest", "b": "Head", "anchor": Vector3(0, 0.9, -0.53), "swing": 0.48, "twist": 0.35},
			{"type": "cone", "name": "MuzzleJoint", "a": "Head", "b": "Muzzle", "anchor": Vector3(0, 0.98, -0.7), "swing": 0.12, "twist": 0.08},
			{"type": "cone", "name": "EarLJoint", "a": "Head", "b": "EarL", "anchor": Vector3(-0.13, 1.18, -0.55), "swing": 0.2, "twist": 0.15},
			{"type": "cone", "name": "EarRJoint", "a": "Head", "b": "EarR", "anchor": Vector3(0.13, 1.18, -0.55), "swing": 0.2, "twist": 0.15},
			{"type": "cone", "name": "TailRoot", "a": "Pelvis", "b": "TailBase", "anchor": Vector3(0, 0.72, 0.58), "swing": 0.75, "twist": 0.5},
			{"type": "cone", "name": "TailJoint", "a": "TailBase", "b": "TailTip", "anchor": Vector3(0, 0.88, 0.9), "swing": 0.8, "twist": 0.55},
		],
		"root_part": "Torso",
		"collision_shapes": [
			{"type": "capsule", "radius": 0.3, "height": 1.25,
				"pos": Vector3(0, 0.625, -0.48)},
			{"type": "capsule", "radius": 0.28, "height": 1.1,
				"pos": Vector3(0, 0.55, 0.35)},
		],
		"camera_pivot": Vector3(0, 1.05, 0), "orbit_length": 2.35,
		"nameplate_position": Vector3(0, 1.55, 0),
		"target_position": Vector3(0, 0.72, 0), "eye_position": Vector3(0, 1.03, -0.5),
		"gun_position": Vector3(0.3, 0.85, -0.55),
		"preview_height": 1.45,
	},
	"dog": {
		"label": "Dog",
		"scale": 0.88,
		"parts": [
			{"name": "Torso", "size": Vector3(0.54, 0.46, 0.92), "pos": Vector3(0, 0.75, 0)},
			{"name": "Chest", "size": Vector3(0.56, 0.55, 0.48), "pos": Vector3(0, 0.79, -0.46)},
			{"name": "Pelvis", "size": Vector3(0.5, 0.43, 0.44), "pos": Vector3(0, 0.71, 0.48)},
			{"name": "UpperFrontLegL", "size": Vector3(0.18, 0.4, 0.19), "pos": Vector3(-0.21, 0.48, -0.46)},
			{"name": "UpperFrontLegR", "size": Vector3(0.18, 0.4, 0.19), "pos": Vector3(0.21, 0.48, -0.46)},
			{"name": "LowerFrontLegL", "size": Vector3(0.17, 0.34, 0.18), "pos": Vector3(-0.21, 0.18, -0.46)},
			{"name": "LowerFrontLegR", "size": Vector3(0.17, 0.34, 0.18), "pos": Vector3(0.21, 0.18, -0.46)},
			{"name": "UpperBackLegL", "size": Vector3(0.23, 0.41, 0.24), "pos": Vector3(-0.19, 0.47, 0.48)},
			{"name": "UpperBackLegR", "size": Vector3(0.23, 0.41, 0.24), "pos": Vector3(0.19, 0.47, 0.48)},
			{"name": "LowerBackLegL", "size": Vector3(0.18, 0.32, 0.2), "pos": Vector3(-0.19, 0.17, 0.48)},
			{"name": "LowerBackLegR", "size": Vector3(0.18, 0.32, 0.2), "pos": Vector3(0.19, 0.17, 0.48)},
			{"name": "Head", "size": Vector3(0.48, 0.46, 0.44), "pos": Vector3(0, 1.18, -0.62)},
			{"name": "Muzzle", "size": Vector3(0.34, 0.25, 0.38), "pos": Vector3(0, 1.08, -0.95)},
			{"name": "EarL", "size": Vector3(0.17, 0.32, 0.16), "pos": Vector3(-0.22, 1.13, -0.6), "rot": Vector3(0, 0, -0.35)},
			{"name": "EarR", "size": Vector3(0.17, 0.32, 0.16), "pos": Vector3(0.22, 1.13, -0.6), "rot": Vector3(0, 0, 0.35)},
			{"name": "Tail", "size": Vector3(0.16, 0.16, 0.5), "pos": Vector3(0, 0.9, 0.78), "rot": Vector3(-0.45, 0, 0)},
		],
		"joints": [
			{"type": "cone", "name": "SpineFront", "a": "Torso", "b": "Chest", "anchor": Vector3(0, 0.76, -0.28), "swing": 0.36, "twist": 0.25},
			{"type": "cone", "name": "SpineBack", "a": "Torso", "b": "Pelvis", "anchor": Vector3(0, 0.73, 0.3), "swing": 0.36, "twist": 0.25},
			{"type": "cone", "name": "ShoulderL", "a": "Chest", "b": "UpperFrontLegL", "anchor": Vector3(-0.21, 0.64, -0.46), "swing": 0.72, "twist": 0.35},
			{"type": "cone", "name": "ShoulderR", "a": "Chest", "b": "UpperFrontLegR", "anchor": Vector3(0.21, 0.64, -0.46), "swing": 0.72, "twist": 0.35},
			{"type": "hinge", "name": "FrontKneeL", "a": "UpperFrontLegL", "b": "LowerFrontLegL", "anchor": Vector3(-0.21, 0.33, -0.46), "lower": -0.2, "upper": 1.8},
			{"type": "hinge", "name": "FrontKneeR", "a": "UpperFrontLegR", "b": "LowerFrontLegR", "anchor": Vector3(0.21, 0.33, -0.46), "lower": -0.2, "upper": 1.8},
			{"type": "cone", "name": "HipL", "a": "Pelvis", "b": "UpperBackLegL", "anchor": Vector3(-0.19, 0.63, 0.48), "swing": 0.78, "twist": 0.4},
			{"type": "cone", "name": "HipR", "a": "Pelvis", "b": "UpperBackLegR", "anchor": Vector3(0.19, 0.63, 0.48), "swing": 0.78, "twist": 0.4},
			{"type": "hinge", "name": "BackKneeL", "a": "UpperBackLegL", "b": "LowerBackLegL", "anchor": Vector3(-0.19, 0.32, 0.48), "lower": -1.8, "upper": 0.2},
			{"type": "hinge", "name": "BackKneeR", "a": "UpperBackLegR", "b": "LowerBackLegR", "anchor": Vector3(0.19, 0.32, 0.48), "lower": -1.8, "upper": 0.2},
			{"type": "cone", "name": "Neck", "a": "Chest", "b": "Head", "anchor": Vector3(0, 1.0, -0.57), "swing": 0.45, "twist": 0.32},
			{"type": "cone", "name": "MuzzleJoint", "a": "Head", "b": "Muzzle", "anchor": Vector3(0, 1.11, -0.79), "swing": 0.12, "twist": 0.08},
			{"type": "cone", "name": "EarLJoint", "a": "Head", "b": "EarL", "anchor": Vector3(-0.2, 1.23, -0.6), "swing": 0.6, "twist": 0.35},
			{"type": "cone", "name": "EarRJoint", "a": "Head", "b": "EarR", "anchor": Vector3(0.2, 1.23, -0.6), "swing": 0.6, "twist": 0.35},
			{"type": "cone", "name": "TailRoot", "a": "Pelvis", "b": "Tail", "anchor": Vector3(0, 0.82, 0.62), "swing": 0.65, "twist": 0.45},
		],
		"root_part": "Torso",
		"collision_shapes": [
			{"type": "capsule", "radius": 0.34, "height": 1.4,
				"pos": Vector3(0, 0.7, -0.5)},
			{"type": "capsule", "radius": 0.34, "height": 1.3,
				"pos": Vector3(0, 0.65, 0.4)},
		],
		"camera_pivot": Vector3(0, 1.15, 0), "orbit_length": 2.45,
		"nameplate_position": Vector3(0, 1.7, 0),
		"target_position": Vector3(0, 0.8, 0), "eye_position": Vector3(0, 1.16, -0.55),
		"gun_position": Vector3(0.36, 0.95, -0.6),
		"preview_height": 1.55,
	},
}


static func is_valid(avatar_id: String) -> bool:
	return AVATARS.has(avatar_id)


static func normalize(avatar_id: String) -> String:
	return avatar_id if is_valid(avatar_id) else DEFAULT_ID


static func profile(avatar_id: String) -> Dictionary:
	var data: Dictionary = AVATARS[normalize(avatar_id)].duplicate(true)
	var avatar_scale := float(data.get("scale", 1.0))
	for part: Dictionary in data["parts"]:
		part["size"] = Vector3(part["size"]) * avatar_scale
		part["pos"] = Vector3(part["pos"]) * avatar_scale
	for joint: Dictionary in data["joints"]:
		joint["anchor"] = Vector3(joint["anchor"]) * avatar_scale
	for shape: Dictionary in data["collision_shapes"]:
		shape["radius"] = float(shape["radius"]) * avatar_scale
		shape["height"] = float(shape["height"]) * avatar_scale
		shape["pos"] = Vector3(shape["pos"]) * avatar_scale
	for key in ["camera_pivot", "nameplate_position", "target_position",
			"eye_position", "gun_position"]:
		data[key] = Vector3(data[key]) * avatar_scale
	for key in ["orbit_length", "preview_height"]:
		data[key] = float(data[key]) * avatar_scale
	return data


static func label(avatar_id: String) -> String:
	return str(AVATARS[normalize(avatar_id)]["label"])


## Contract validation is intentionally data-level so every future roster entry
## can be checked headlessly before anyone tunes its art or physics.
static func contract_errors(avatar_id: String) -> PackedStringArray:
	var errors := PackedStringArray()
	if not is_valid(avatar_id):
		errors.append("unknown avatar id")
		return errors
	var data: Dictionary = AVATARS[avatar_id]
	for key in ["label", "scale", "parts", "joints", "root_part", "collision_shapes",
			"camera_pivot", "orbit_length",
			"nameplate_position", "target_position", "eye_position", "gun_position"]:
		if not data.has(key):
			errors.append("missing %s" % key)
	if float(data.get("scale", 0.0)) <= 0.0:
		errors.append("scale must be positive")
	var names := {}
	for part: Dictionary in data.get("parts", []):
		for key in ["name", "size", "pos"]:
			if not part.has(key):
				errors.append("part missing %s" % key)
		var part_name := str(part.get("name", ""))
		if names.has(part_name):
			errors.append("duplicate part %s" % part_name)
		names[part_name] = true
	if not names.has(str(data.get("root_part", ""))):
		errors.append("root_part is not a part")
	for shape: Dictionary in data.get("collision_shapes", []):
		if shape.get("type") != "capsule":
			errors.append("unsupported movement collision shape")
		for key in ["radius", "height", "pos"]:
			if not shape.has(key):
				errors.append("movement collision missing %s" % key)
	if data.get("collision_shapes", []).is_empty():
		errors.append("avatar has no movement collision")
	var graph := {}
	for part_name: String in names:
		graph[part_name] = []
	var joint_names := {}
	for joint: Dictionary in data.get("joints", []):
		var joint_name := str(joint.get("name", "?"))
		if joint_names.has(joint_name):
			errors.append("duplicate joint %s" % joint_name)
		joint_names[joint_name] = true
		var a := str(joint.get("a", ""))
		var b := str(joint.get("b", ""))
		if not names.has(a) or not names.has(b):
			errors.append("joint %s references a missing part" % joint.get("name", "?"))
		else:
			graph[a].append(b)
			graph[b].append(a)
		var joint_type := str(joint.get("type", ""))
		if joint_type == "hinge":
			for key in ["lower", "upper"]:
				if not joint.has(key):
					errors.append("hinge %s missing %s" % [joint_name, key])
		elif joint_type == "cone":
			for key in ["swing", "twist"]:
				if not joint.has(key):
					errors.append("cone %s missing %s" % [joint_name, key])
		else:
			errors.append("joint %s has unsupported type" % joint_name)
	if data.get("joints", []).size() != maxi(0, data.get("parts", []).size() - 1):
		errors.append("rig is not a single connected tree")
	elif not names.is_empty():
		var visited := {names.keys()[0]: true}
		var pending := [names.keys()[0]]
		while not pending.is_empty():
			var current: String = pending.pop_back()
			for neighbor: String in graph[current]:
				if not visited.has(neighbor):
					visited[neighbor] = true
					pending.append(neighbor)
		if visited.size() != names.size():
			errors.append("rig is not a single connected tree")
	return errors
