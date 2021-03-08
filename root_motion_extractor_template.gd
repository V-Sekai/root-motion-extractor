tool
extends EditorScenePostImport

# Use this as an example script for writing your own custom post-import scripts. The function requires you pass a table
# of valid animation names and parameters

func post_import(p_scene: Object) -> Object:
	var source_file_path: String = get_source_file()
	p_scene = RootMotionExtractor.root_motion_import_function(source_file_path, p_scene,
	{
		"Run":{},
		"Walk":{},
		"Idle":{}
	})
	
	return p_scene
