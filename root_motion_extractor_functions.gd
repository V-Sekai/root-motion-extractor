@tool
extends Node

const root_motion_flags_const = preload("root_motion_flags.gd")

const ROOT_BONE = 0

static func _find_skeletons(p_node: Node, p_skeleton_array: Array) -> Array:
	if p_node is Skeleton3D:
		p_skeleton_array.append(p_node)
		
	for child in p_node.get_children():
		p_skeleton_array = _find_skeletons(child, p_skeleton_array)
		
	return p_skeleton_array
	
static func _find_animation_players(p_node: Node, p_animation_player_array: Array) -> Array:
	if p_node is AnimationPlayer:
		p_animation_player_array.append(p_node)
		
	for child in p_node.get_children():
		p_animation_player_array = _find_animation_players(child, p_animation_player_array)
		
	return p_animation_player_array

static func _get_root_reset_transforms(p_reset_animation: Animation, p_skeletons: Array, p_root_node: Node) -> Dictionary:
	var skeleton_root_reset_transforms: Dictionary = {}
	for skeleton in p_skeletons:
		skeleton_root_reset_transforms[skeleton] = Transform3D()
	
	# Extract base position and rotation from RESET track
	for track_idx in range(0, p_reset_animation.get_track_count()):
		var animation_track_path: NodePath = p_reset_animation.track_get_path(track_idx)
		var track_node: Node = p_root_node.get_node_or_null(animation_track_path)
		assert(track_node)
		
		if track_node is Skeleton3D and p_skeletons.find(track_node) != -1:
			var skeleton_node: Skeleton3D = track_node
			if animation_track_path.get_subname_count() > 0:
				var bone_name: String = str(animation_track_path.get_subname(0))
				var bone_idx: int = skeleton_node.find_bone(bone_name)
				if bone_idx == ROOT_BONE:
					var track_type: int = p_reset_animation.track_get_type(track_idx)
					if track_type == Animation.TYPE_POSITION_3D:
						skeleton_root_reset_transforms[skeleton_node].origin = p_reset_animation.track_get_key_value(track_idx, 0)
					elif track_type == Animation.TYPE_ROTATION_3D:
						skeleton_root_reset_transforms[skeleton_node].basis = Basis(p_reset_animation.track_get_key_value(track_idx, 0))

	return skeleton_root_reset_transforms

static func _remove_root_tracks(p_animation: Animation, p_skeleton: Skeleton3D, p_root_node: Node) -> void:
	var skeleton_parent: Node3D = p_skeleton.get_parent()
	if skeleton_parent:
		for track_idx in range(0, p_animation.get_track_count()):
			var track_type: int = p_animation.track_get_type(track_idx)
			if track_type == Animation.TYPE_POSITION_3D or track_type == Animation.TYPE_ROTATION_3D:
				var animation_track_path: NodePath = p_animation.track_get_path(track_idx)
				var track_node: Node = p_root_node.get_node(animation_track_path)
				if track_node == skeleton_parent:
					p_animation.remove_track(track_idx)

static func _convert_track(
	p_animation: Animation,
	p_skeleton: Skeleton3D,
	p_track_idx: int,
	p_root_reset_transform: Transform3D,
	p_root_motion_extraction_flags: int) -> Array:
		
	var root_keys: Array = []
		
	var skeleton_gt: Transform3D = p_skeleton.get_parent().transform * p_skeleton.transform
		
	var track_type: int = p_animation.track_get_type(p_track_idx)
	if track_type == Animation.TYPE_POSITION_3D or track_type == Animation.TYPE_ROTATION_3D:
		for key_idx in range(0, p_animation.track_get_key_count(p_track_idx)):
			var time: float = p_animation.track_get_key_time(p_track_idx, key_idx)
			var transition: float = p_animation.track_get_key_transition(p_track_idx, key_idx)
			var value = p_animation.track_get_key_value(p_track_idx, key_idx)
			
			var current_key: Dictionary = {"time":time, "transition":transition}
			
			var root_rest_transform_gt: Transform3D = skeleton_gt * p_root_reset_transform
			
			match track_type:
				Animation.TYPE_POSITION_3D:
					var bone_gt: Transform3D = skeleton_gt * Transform3D(Basis(), value)
					var offset: Vector3 = Vector3()
					
					if p_root_motion_extraction_flags & root_motion_flags_const.EXTRACT_ORIGIN_X:
						offset.x = bone_gt.origin.x - root_rest_transform_gt.origin.x
						bone_gt.origin.x = root_rest_transform_gt.origin.x
					if p_root_motion_extraction_flags & root_motion_flags_const.EXTRACT_ORIGIN_Y:
						offset.y = bone_gt.origin.y - root_rest_transform_gt.origin.y
						bone_gt.origin.y = root_rest_transform_gt.origin.y
					if p_root_motion_extraction_flags & root_motion_flags_const.EXTRACT_ORIGIN_Z:
						offset.z = bone_gt.origin.z - root_rest_transform_gt.origin.z
						bone_gt.origin.z = root_rest_transform_gt.origin.z
					
					current_key["value"] = offset
					p_animation.track_set_key_value(p_track_idx, key_idx, skeleton_gt.affine_inverse() * bone_gt.origin)
				Animation.TYPE_ROTATION_3D:
					var bone_gt: Transform3D = skeleton_gt * Transform3D(Basis(value), Vector3())
					
					var bone_gt_euler = bone_gt.basis.get_euler()
					var offset = Vector3()
					if p_root_motion_extraction_flags & root_motion_flags_const.EXTRACT_ROTATION_Y:
						offset.y = bone_gt_euler.y - root_rest_transform_gt.basis.get_euler().y
						bone_gt_euler.y = root_rest_transform_gt.basis.get_euler().y
					bone_gt.basis = Basis().from_euler(bone_gt_euler)
					
					current_key["value"] = Basis().from_euler(offset).get_rotation_quaternion()
					p_animation.track_set_key_value(p_track_idx, key_idx, (skeleton_gt.basis.inverse() * bone_gt.basis).get_rotation_quaternion())
				
			root_keys.push_back(current_key)
	
	return root_keys

static func _convert_animation(
	p_animation: Animation,
	p_root_node: Node,
	p_skeletons: Array,
	p_root_reset_transforms: Dictionary,
	p_root_motion_extraction_flags: int) -> void:
		
	for track_idx in range(0, p_animation.get_track_count()):
		var animation_track_path: NodePath = p_animation.track_get_path(track_idx)
		
		var track_node: Node = p_root_node.get_node_or_null(animation_track_path)
		if(!track_node):
			continue
		
		# Check if track points to one of the valid skeletons
		if track_node is Skeleton3D and p_skeletons.find(track_node) != -1:
			var skeleton_node: Skeleton3D = track_node
			if animation_track_path.get_subname_count() > 0:
				animation_track_path.get_subname(0)
				var bone_name: String = str(animation_track_path.get_subname(0))
				var bone_idx: int = skeleton_node.find_bone(bone_name)
				if bone_idx == ROOT_BONE:
					var track_type: int = p_animation.track_get_type(track_idx)
					if track_type == Animation.TYPE_POSITION_3D or track_type == Animation.TYPE_ROTATION_3D:
						var keys: Array = _convert_track(p_animation, skeleton_node, track_idx, p_root_reset_transforms[skeleton_node], p_root_motion_extraction_flags)
							
						#_remove_root_tracks(p_animation, skeleton_node, p_root_node)
							
						var skeleton_parent: Node = skeleton_node.get_parent()
						var root_path: NodePath = p_root_node.get_path_to(skeleton_parent)
						
						match track_type:
							Animation.TYPE_POSITION_3D:
								var root_track_idx: int = p_animation.add_track(Animation.TYPE_POSITION_3D)
								p_animation.track_set_path(root_track_idx, root_path)
								p_animation.track_set_imported(root_track_idx, true)
								
								for key in keys:
									p_animation.track_insert_key(
										root_track_idx,
										key["time"],
										skeleton_parent.transform.origin + key["value"],
										key["transition"])
							Animation.TYPE_ROTATION_3D:
								var root_track_idx: int = p_animation.add_track(Animation.TYPE_ROTATION_3D)
								p_animation.track_set_path(root_track_idx, root_path)
								p_animation.track_set_imported(root_track_idx, true)
								
								for key in keys:
									p_animation.track_insert_key(
										root_track_idx,
										key["time"],
										key["value"] * skeleton_parent.transform.basis.get_rotation_quaternion(),
										key["transition"])
						
static func _add_reset_tracks(
	p_animation: Animation,
	p_skeletons: Array,
	p_root_node: Node
	) -> void:
	for skeleton in p_skeletons:
		_remove_root_tracks(p_animation, skeleton, p_root_node)
		
		var skeleton_parent: Node = skeleton.get_parent()
		
		# Position
		var position_idx: int = p_animation.add_track(Animation.TYPE_POSITION_3D)
		p_animation.track_set_path(position_idx, p_root_node.get_path_to(skeleton_parent))
		p_animation.track_set_imported(position_idx, true)
		p_animation.track_insert_key(
			position_idx,
			0.0,
			skeleton_parent.transform.origin
			)
		#
		
		# Rotation
		var rotation_idx: int = p_animation.add_track(Animation.TYPE_ROTATION_3D)
		p_animation.track_set_path(rotation_idx, p_root_node.get_path_to(skeleton_parent))
		p_animation.track_set_imported(rotation_idx, true)
		p_animation.track_insert_key(
			rotation_idx,
			0.0,
			skeleton_parent.transform.basis.get_rotation_quaternion()
			)
						
static func _convert_animation_player(p_animation_player: AnimationPlayer, p_skeletons: Array, p_animation_conversion_table: Dictionary) -> void:
	var animation_names: PackedStringArray = p_animation_player.get_animation_list()
	var root_node_path: NodePath = p_animation_player.root_node
	var root_node: Node = p_animation_player.get_node_or_null(root_node_path)
	assert(root_node)
	
	###################
	# Reset Animation #
	###################
	var reset_animation_name: String = p_animation_player.assigned_animation
	var reset_animation: Animation = null
	if reset_animation_name != "":
		reset_animation = p_animation_player.get_animation(reset_animation_name)
		
	if !reset_animation:
		printerr("RESET animation not found!")
		return
		
	var root_reset_transforms: Dictionary = _get_root_reset_transforms(reset_animation, p_skeletons, root_node)
		
	_add_reset_tracks(reset_animation, p_skeletons, root_node)
		
	for animation_name in animation_names:
		var animation: Animation = p_animation_player.get_animation(animation_name)
		
		if p_animation_conversion_table.has(animation_name):
			var root_motion_extraction_flags: int = p_animation_conversion_table[animation_name]
			# Not flags set, don't do anything
			if root_motion_extraction_flags == 0:
				continue
			
			_convert_animation(animation, root_node, p_skeletons, root_reset_transforms, root_motion_extraction_flags)
		else:
			_add_reset_tracks(animation, p_skeletons, root_node)
		
			
		if !animation.resource_local_to_scene:
			ResourceSaver.save(animation.resource_path, animation)	
		
		
static func rename_animations_import_function(p_file_path: String, p_scene: Node, p_animation_map: Dictionary) -> Node:
	var config_file: ConfigFile = ConfigFile.new()
	# STUB (THIS RETURN RANDOM NUMBERS, WTF)
	#if config_file.load(p_file_path + ".import") == OK:
	if 1:
		var empty_array: Array = []
		var animation_players: Array = _find_animation_players(p_scene, empty_array)
		#var animation_players: Array = _find_animation_players(p_scene, [])
		
		for animation_player in animation_players:
			var animation_name_list: PackedStringArray = animation_player.get_animation_list()
			for animation_name in animation_name_list:
				if p_animation_map.has(animation_name):
					animation_player.rename_animation(StringName(animation_name), StringName(p_animation_map[animation_name]))
					var animation = animation_player.get_animation(StringName(p_animation_map[animation_name]))
					animation.resource_name = p_animation_map[animation_name]
					
					# Save the animation again if it was saved externally
					if !animation.resource_local_to_scene:
						ResourceSaver.save(animation.resource_path, animation)
	else:
		printerr("Could not load .import file for %s" % p_file_path)
	
	return p_scene
	
static func root_motion_import_function(p_file_path: String, p_scene: Node, p_animation_conversion_table: Dictionary) -> Node:
	var config_file: ConfigFile = ConfigFile.new()
	# STUB (THIS RETURN RANDOM NUMBERS, WTF)
	#if config_file.load(p_file_path + ".import") == OK:
	if 1:
		var animation_players: Array = _find_animation_players(p_scene, [])
		var skeletons: Array = _find_skeletons(p_scene, [])
		
		for animation_player in animation_players:
			_convert_animation_player(animation_player, skeletons, p_animation_conversion_table)
	else:
		printerr("Could not load .import file for %s" % p_file_path)
		
	return p_scene
