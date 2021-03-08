tool
extends Node

const ROOT_BONE = 0

static func _find_skeletons(p_node: Node, p_skeleton_array: Array) -> Array:
	if p_node is Skeleton:
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
	var animation_names: PoolStringArray = p_animation_player.get_animation_list()
	var root_node_path: NodePath = p_animation_player.root_node
	var root_node: Node = p_animation_player.get_node(root_node_path)
	
	for animation_name in animation_names:
		var animation: Animation = p_animation_player.get_animation(animation_name)
		
		if p_animation_conversion_table.has(animation.resource_name):
			var skeleton_transform_keys: Dictionary = {}
			for track_idx in range(0, animation.get_track_count()):
				var root_keys: Array = []
				
				############################
				# Find the root transforms #
				############################
				if animation.track_get_type(track_idx) == Animation.TYPE_TRANSFORM:
					var animation_track_path: NodePath = animation.track_get_path(track_idx)
					var track_node: Node = root_node.get_node(animation_track_path)
					
					if track_node is Skeleton and p_skeletons.find(track_node) != -1:
						var skeleton_node: Skeleton = track_node
						if animation_track_path.get_subname_count() > 0:
							var bone_name: String = animation_track_path.get_subname(0)
							var bone_idx: int = skeleton_node.find_bone(bone_name)
							
							# Bone is the root
							if bone_idx == ROOT_BONE:
								var rest_transform: Transform = skeleton_node.get_bone_rest(bone_idx)
								
								for key_idx in range(0, animation.track_get_key_count(track_idx)):
									var time: float = animation.track_get_key_time(track_idx, key_idx)
									var transition: float = animation.track_get_key_transition(track_idx, key_idx)
									
									var value = animation.track_get_key_value(track_idx, key_idx)
									var pose_local_transform: Transform = convert_tranform_value_to_transform(value)
									
									var pose_gt: Transform = rest_transform\
									* pose_local_transform
									
									var modified_pose_gt: Transform = pose_gt
									
									modified_pose_gt.origin.x = 0.0
									modified_pose_gt.origin.z = 0.0
									
									pose_local_transform = rest_transform.affine_inverse()\
									* modified_pose_gt
									
									animation.track_set_key_value(track_idx, key_idx,
									convert_tranform_to_transform_value(pose_local_transform))
									
									var cumulative_transform: Transform = Transform()
									for key in root_keys:
										cumulative_transform *= key["relative_gt"]
										
									root_keys.append({
										"time":time,
										"transition":transition,
										"relative_gt":cumulative_transform.inverse() * Transform(Basis(), Vector3(pose_gt.origin.x, 0.0, pose_gt.origin.z))})
							
						skeleton_transform_keys[skeleton_node] = root_keys
			
			###########################################
			# Move extracted root data to actual root #
			###########################################
			for skeleton in p_skeletons:
				var skeleton_parent: Spatial = skeleton.get_parent()
				if skeleton_parent:
					for track_idx in range(0, animation.get_track_count()):
						if animation.track_get_type(track_idx) == Animation.TYPE_TRANSFORM:
							var animation_track_path: NodePath = animation.track_get_path(track_idx)
							var track_node: Node = root_node.get_node(animation_track_path)
							
							if track_node == skeleton_parent:
								animation.remove_track(track_idx)
								
				var track_idx: int = animation.add_track(Animation.TYPE_TRANSFORM)
				animation.track_set_path(track_idx, root_node.get_path_to(skeleton_parent))
				animation.track_set_imported(track_idx, true)
				
				var root_keys: Array = skeleton_transform_keys[skeleton]
				var cumulative_transform: Transform = Transform()
				for key in root_keys:
					cumulative_transform *= key["relative_gt"]
					var track_transform: Transform = cumulative_transform.scaled(skeleton_parent.get_scale())
					
					animation.track_insert_key(
						track_idx,
						key["time"],
						convert_tranform_to_transform_value(track_transform),
						key["transition"])
		
		# Save the animation again if it was saved externally
		if !animation.resource_local_to_scene:
			ResourceSaver.save(animation.resource_path, animation)
						
		
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
