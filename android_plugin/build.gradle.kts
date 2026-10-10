// Top-level build file where you can add configuration options common to all sub-projects/modules.
plugins {
    id("com.android.library") version "8.13.2" apply false
    // LiteRT-LM is built with Kotlin 2.4, whose metadata an older compiler cannot read.
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
}
