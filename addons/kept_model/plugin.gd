@tool
extends EditorPlugin
## A duck run from the editor leaves its chat model loaded, so the next run starts in a second
## instead of 45. This frees it when the editor closes.


func _exit_tree() -> void:
	KeptModel.release(KeptModel.PATH)
