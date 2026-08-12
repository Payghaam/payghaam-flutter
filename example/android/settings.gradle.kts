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

// Prefer the local Android SDK when developing next to payghaam-android so
// fixes (e.g. hot-restart apiKey refresh) apply without republishing to Maven.
val localAndroidSdk = file("../../../payghaam-android")
if (localAndroidSdk.exists()) {
    includeBuild(localAndroidSdk) {
        dependencySubstitution {
            substitute(module("com.payghaam:payghaam")).using(project(":payghaam"))
        }
    }
}
// Otherwise resolves "com.payghaam:payghaam" from Maven Central.
