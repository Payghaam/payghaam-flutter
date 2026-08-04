pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.9.1" apply false
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
}

include(":app")

// Canonical native SDK — engagekaro_flutter's build.gradle depends on
// "com.engagekaro:engagekaro"; this composite build substitution resolves that to
// the local sdks/android module instead of a Maven repo. See
// sdk-native-wrapper-design.md.
includeBuild("../../../android") {
    dependencySubstitution {
        substitute(module("com.engagekaro:engagekaro")).using(project(":engagekaro"))
    }
}
