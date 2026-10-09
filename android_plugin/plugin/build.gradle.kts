import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

val pluginName = "GeminiNano"
val pluginPackageName = "com.kirbycope.duck.gemininano"
// Where the built AARs and the export script go: the project's own addons folder.
val addonDir = "${rootDir}/../addons/$pluginName"

android {
    namespace = pluginPackageName
    compileSdk = 36

    buildFeatures {
        buildConfig = true
    }

    defaultConfig {
        // ML Kit's GenAI Prompt API needs Android 8.0.
        minSdk = 26

        manifestPlaceholders["godotPluginName"] = pluginName
        manifestPlaceholders["godotPluginPackageName"] = pluginPackageName
        buildConfigField("String", "GODOT_PLUGIN_NAME", "\"${pluginName}\"")
        setProperty("archivesBaseName", pluginName)
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlin {
        compilerOptions {
            jvmTarget.set(JvmTarget.JVM_17)
        }
    }
}

dependencies {
    implementation("org.godotengine:godot:4.5.1.stable")
    // These two are also named in export_plugin.gd, which adds them to the app.
    implementation("com.google.mlkit:genai-prompt:1.0.0-beta4")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
}

val copyDebugAAR by tasks.registering(Copy::class) {
    from("build/outputs/aar")
    include("$pluginName-debug.aar")
    into("$addonDir/bin/debug")
}

val copyReleaseAAR by tasks.registering(Copy::class) {
    from("build/outputs/aar")
    include("$pluginName-release.aar")
    into("$addonDir/bin/release")
}

val copyAddon by tasks.registering(Copy::class) {
    description = "Copies the export script and the AARs into the project's addons/GeminiNano"
    finalizedBy(copyDebugAAR)
    finalizedBy(copyReleaseAAR)
    from("export_scripts_template")
    into(addonDir)
}

tasks.named("assemble").configure {
    finalizedBy(copyAddon)
}
