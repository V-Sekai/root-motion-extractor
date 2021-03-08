tool
extends Node

const root_motion_extractor_functions_const = preload("root_motion_extractor_functions.gd")

static func root_motion_import_function(p_file_path: String, p_scene: Node, root_motion_import_function: Dictionary) -> Node:
	return root_motion_extractor_functions_const.root_motion_import_function(p_file_path, p_scene, root_motion_import_function)
