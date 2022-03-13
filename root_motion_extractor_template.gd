@tool
extends EditorScenePostImport

const root_motion_extractor_const = preload("res://addons/root-motion-extractor/root_motion_extractor.gd")

# Use this as an example script for writing your own custom post-import scripts. The function requires you pass a table
# of valid animation names and parameters

func post_import(p_scene: Object) -> Object:
	var source_file_path: String = get_source_file()
	
	p_scene = root_motion_extractor_const.root_motion_import_function(source_file_path, p_scene,
	{
		"Run": 
			root_motion_extractor_const.root_motion_flags_const.EXTRACT_ORIGIN_X | 
			root_motion_extractor_const.root_motion_flags_const.EXTRACT_ORIGIN_Z,
		"BaseballPitch":
			root_motion_extractor_const.root_motion_flags_const.EXTRACT_ORIGIN_X | 
			root_motion_extractor_const.root_motion_flags_const.EXTRACT_ORIGIN_Z,
		"ChangeDirection":
			root_motion_extractor_const.root_motion_flags_const.EXTRACT_ORIGIN_X | 
			root_motion_extractor_const.root_motion_flags_const.EXTRACT_ORIGIN_Z |
			root_motion_extractor_const.root_motion_flags_const.EXTRACT_ROTATION_Y,
	})

	return p_scene
