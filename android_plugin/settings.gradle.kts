// The GeminiNano Android plugin: Gemini Nano, through Android's AICore, for the phone app's local LLM.
// Built from Godot's Android plugin template (https://github.com/m4gr3d/Godot-Android-Plugin-Template, MIT).
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "GeminiNano"
include(":plugin")
