@tool
extends EditorPlugin
## Adds the GeminiNano Android plugin (Gemini Nano, LiteRT-LM, the phone's own stats and its speech recognizer), and the
## libraries it needs, to the Android export.

var export_plugin: AndroidExportPlugin


func _enter_tree() -> void:
	export_plugin = AndroidExportPlugin.new()
	add_export_plugin(export_plugin)


func _exit_tree() -> void:
	remove_export_plugin(export_plugin)
	export_plugin = null


class AndroidExportPlugin extends EditorExportPlugin:
	const PLUGIN_NAME: String = "GeminiNano"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(_platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
		var kind: String = "debug" if debug else "release"
		return PackedStringArray([PLUGIN_NAME + "/bin/%s/%s-%s.aar" % [kind, PLUGIN_NAME, kind]])

	func _get_android_dependencies(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray(["com.google.mlkit:genai-prompt:1.0.0-beta4", "org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2", "com.google.ai.edge.litertlm:litertlm-android:0.18.0"])

	func _get_name() -> String:
		return PLUGIN_NAME
