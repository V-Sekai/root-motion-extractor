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

static func convert_tranform_value_to_transform(p_value: Dictionary) -> Transform:
	return Transform(p_value["rotation"], p_value["location"])

static func convert_tranform_to_transform_value(p_transform: Transform) -> Dictionary:
	var value: Dictionary = {
		"location":p_transform.origin,
		"rotation":p_transform.basis.get_rotation_quat(),
		"scale":p_transform.basis.get_scale()
	}
	
	return value

static func _convert_animation_player(p_animation_player: AnimationPlayer, p_skeletons: Array, p_animation_conversion_table: Dictionary) -> void:
	var animation_names: PackedStringArray = p_animation_player.get_animation_list()
	var root_node_path: NodePath = p_animation_player.root_node
	var root_node: Node = p_animation_player.get_node(root_node_path)
	
	for animation_name in animation_names:
		var animation: Animation = p_animation_player.get_animation(animation_name)
		
		if p_animation_conversion_table.has(animation.resource_name):
			var root_motion_extraction_flags: int = p_animation_conversion_table[animation.resource_name]
			
			# Not flags set, don't do anything
			if root_motion_extraction_flags == 0:
				continue
			
			var skeleton_transform_keys: Dictionary = {}
			for track_idx in range(0, animation.get_track_count()):
				var root_keys: Array = []
				
				############################
				# Find the root transforms #
				############################
				if animation.track_get_type(track_idx) == Animation.TYPE_TRANSFORM:
					var animation_track_path: NodePath = animation.track_get_path(track_idx)
					var track_node: Node = root_node.get_node(animation_track_path)
					
					if track_node is Skeleton3D and p_skeletons.find(track_node) != -1:
						var skeleton_node: Skeleton3D = track_node
						if animation_track_path.get_subname_count() > 0:
							var bone_name: String = animation_track_path.get_subname(0)
							var bone_idx: int = skeleton_node.find_bone(bone_name)
							
							# Bone is the root
							if bone_idx == ROOT_BONE:
								var rest_gt_transform: Transform = skeleton_node.get_parent().transform * skeleton_node.transform * skeleton_node.get_bone_rest(bone_idx)
								
								var last_y_euler: float = 0.0
								for key_idx in range(0, animation.track_get_key_count(track_idx)):
									var time: float = animation.track_get_key_time(track_idx, key_idx)
									var transition: float = animation.track_get_key_transition(track_idx, key_idx)
									
									var value = animation.track_get_key_value(track_idx, key_idx)
									var pose_local_transform: Transform = convert_tranform_value_to_transform(value)
									
									var pose_gt: Transform = rest_gt_transform * pose_local_transform
									
									var modified_pose_gt: Transform = pose_gt
									
									var global_y_rotation: float = 0.0
									
									if root_motion_extraction_flags & root_motion_flags_const.EXTRACT_ROTATION_Y:
										global_y_rotation = modified_pose_gt.basis.orthonormalized().get_euler().y
									
									if root_motion_extraction_flags & root_motion_flags_const.EXTRACT_ORIGIN_X:
										modified_pose_gt.origin.x = 0.0
									if root_motion_extraction_flags & root_motion_flags_const.EXTRACT_ORIGIN_Y:
										modified_pose_gt.origin.y = 0.0
									if root_motion_extraction_flags & root_motion_flags_const.EXTRACT_ORIGIN_Z:
										modified_pose_gt.origin.z = 0.0
									
									modified_pose_gt = modified_pose_gt.rotated(Vector3.UP, -global_y_rotation)
									
									pose_local_transform = rest_gt_transform.affine_inverse()\
									* modified_pose_gt
									
									animation.track_set_key_value(track_idx, key_idx,
									convert_tranform_to_transform_value(pose_local_transform))
									
									var cumulative_transform: Transform = Transform()
									for key in root_keys:
										cumulative_transform *= key["relative_gt"]
										
									var relative_y_rotation: float = global_y_rotation - last_y_euler
									var relative_gt_origin: Vector3 = Vector3()
									
									if root_motion_extraction_flags & root_motion_flags_const.EXTRACT_ORIGIN_X:
										relative_gt_origin.x = pose_gt.origin.x
									if root_motion_extraction_flags & root_motion_flags_const.EXTRACT_ORIGIN_Y:
										relative_gt_origin.y = pose_gt.origin.y
									if root_motion_extraction_flags & root_motion_flags_const.EXTRACT_ORIGIN_Z:
										relative_gt_origin.z = pose_gt.origin.z
										
									root_keys.append({
										"time":time,
										"transition":transition,
										"relative_y_rotation":relative_y_rotation,
										"relative_gt":cumulative_transform.inverse() *
										Transform(Basis(),
										relative_gt_origin)})
										
									last_y_euler = global_y_rotation
								skeleton_transform_keys[skeleton_node] = root_keys
			
			###########################################
			# Move extracted root data to actual root #
			###########################################
			for skeleton in p_skeletons:
				var skeleton_parent: Node3D = skeleton.get_parent()
				if skeleton_parent:
					for track_idx in range(0, animation.get_track_count()):
						if animation.track_get_type(track_idx) == Animation.TYPE_TRANSFORM:
							var animation_track_path: NodePath = animation.track_get_path(track_idx)
							var track_node: Node = root_node.get_node(animation_track_path)
							
							if track_node == skeleton_parent:
								animation.remove_track(track_idx)
								
				var root_path: NodePath = root_node.get_path_to(skeleton_parent)
				var track_idx: int = animation.find_track(root_path)
				if track_idx == -1:
					track_idx = animation.add_track(Animation.TYPE_TRANSFORM)
					animation.track_set_path(track_idx, root_path)
					animation.track_set_imported(track_idx, true)
				
				var root_keys: Array = skeleton_transform_keys[skeleton]
				var cumulative_transform: Transform = Transform()
				var cumulative_y_rotation: float = float()
				for key in root_keys:
					var relative_gt: Transform = key["relative_gt"]
					var relative_y_rotation: float = key["relative_y_rotation"]
					
					cumulative_transform *= \
					Transform(
						Basis(), relative_gt.origin
					)
					
					var rotated_transform: Transform = Transform(cumulative_transform.basis.rotated(skeleton_parent.transform.basis.y, cumulative_y_rotation), cumulative_transform.origin)
					var track_transform: Transform = rotated_transform
					
					cumulative_y_rotation += relative_y_rotation
					
					animation.track_insert_key(
						track_idx,
						key["time"],
						convert_tranform_to_transform_value(track_transform * skeleton_parent.transform),
						key["transition"])
		
		# Save the animation again if it was saved externally
		if !animation.resource_local_to_scene:
			ResourceSaver.save(animation.resource_path, animation)
						
static func fill_missing_skeleton_tracks(p_file_path: String, p_scene: Node) -> Node:
	var config_file: ConfigFile = ConfigFile.new()
	if config_file.load(p_file_path + ".import") == OK:
		var animation_players: Array = _find_animation_players(p_scene, [])
		var skeletons: Array = _find_skeletons(p_scene, [])
		
		for animation_player in animation_players:
			var root: Node = animation_player.get_node(animation_player.root_node)
			var animation_name_list: PackedStringArray = animation_player.get_animation_list()
			for animation_name in animation_name_list:
				var animation: Animation = animation_player.get_animation(animation_name)
				for skeleton in skeletons:
					for i in range(0, skeleton.get_bone_count()):
						var bone_name: String = skeleton.get_bone_name(i)
						
						var path: NodePath = NodePath(str(root.get_path_to(skeleton)) + ":" + bone_name)
						
						if animation.find_track(path) == -1:
							var track_idx: int = animation.add_track(Animation.TYPE_TRANSFORM)
							animation.track_set_path(track_idx, path)
							animation.track_insert_key(track_idx, 0.0, convert_tranform_to_transform_value(Transform()))
							animation.track_insert_key(track_idx, animation.length, convert_tranform_to_transform_value(Transform()))
							animation.track_set_imported(track_idx, true)
				# Save the animation again if it was saved externally
				if !animation.resource_local_to_scene:
					ResourceSaver.save(animation.resource_path, animation)
					
	return p_scene
		
		
static func rename_animations_import_function(p_file_path: String, p_scene: Node, p_animation_map: Dictionary) -> Node:
	var config_file: ConfigFile = ConfigFile.new()
	if config_file.load(p_file_path + ".import") == OK:
		var animation_players: Array = _find_animation_players(p_scene, [])
		
		for animation_player in animation_players:
			var animation_name_list: PackedStringArray = animation_player.get_animation_list()
			for animation_name in animation_name_list:
				if p_animation_map.has(animation_name):
					animation_player.rename_animation(animation_name, p_animation_map[animation_name])
					var animation = animation_player.get_animation(p_animation_map[animation_name])
					animation.resource_name = p_animation_map[animation_name]
					
					# Save the animation again if it was saved externally
					if !animation.resource_local_to_scene:
						ResourceSaver.save(animation.resource_path, animation)
	else:
		printerr("Could not load .import file for %s" % p_file_path)
	
	return p_scene
	
static func set_animations_loop_mode(p_file_path: String, p_scene: Node, p_loop_table: Dictionary) -> Node:
	var config_file: ConfigFile = ConfigFile.new()
	if config_file.load(p_file_path + ".import") == OK:
		var animation_players: Array = _find_animation_players(p_scene, [])
		
		for animation_player in animation_players:
			var animation_name_list: PackedStringArray = animation_player.get_animation_list()
			for animation_name in animation_name_list:
				if p_loop_table.has(animation_name):
					var animation = animation_player.get_animation(animation_name)
					animation.loop = p_loop_table[animation_name]
					# Save the animation again if it was saved externally
					if !animation.resource_local_to_scene:
						ResourceSaver.save(animation.resource_path, animation)
	else:
		printerr("Could not load .import file for %s" % p_file_path)
	
	return p_scene
					
static func root_motion_import_function(p_file_path: String, p_scene: Node, p_animation_conversion_table: Dictionary) -> Node:
	var config_file: ConfigFile = ConfigFile.new()
	if config_file.load(p_file_path + ".import") == OK:
		var animation_players: Array = _find_animation_players(p_scene, [])
		var skeletons: Array = _find_skeletons(p_scene, [])
		
		for animation_player in animation_players:
			_convert_animation_player(animation_player, skeletons, p_animation_conversion_table)
	else:
		printerr("Could not load .import file for %s" % p_file_path)
		
	return p_scene
