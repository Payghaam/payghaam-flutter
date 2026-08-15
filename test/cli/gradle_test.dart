import 'package:flutter_test/flutter_test.dart';

import '../../cli/gradle.dart';

void main() {
  test('adds google-services to a Kotlin DSL plugins block', () {
    const src = '''
plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}
''';
    final edit = ensureAppGoogleServices(src, kotlinDsl: true);
    expect(edit.changed, isTrue);
    expect(edit.content, contains('id("com.google.gms.google-services")'));
    expect(ensureAppGoogleServices(edit.content, kotlinDsl: true).changed, isFalse);
  });

  test('adds google-services to settings.gradle.kts with version', () {
    const src = '''
plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.9.1" apply false
}
''';
    final edit = ensureSettingsGoogleServices(src, kotlinDsl: true);
    expect(edit.changed, isTrue);
    expect(
      edit.content,
      contains(
        'id("com.google.gms.google-services") version "$googleServicesVersion" apply false',
      ),
    );
  });

  test('legacy Groovy apply plugin when there is no plugins block', () {
    const src = '''
android {
    namespace "com.example.app"
}
''';
    final edit = ensureAppGoogleServices(src, kotlinDsl: false);
    expect(edit.changed, isTrue);
    expect(edit.content, contains("apply plugin: 'com.google.gms.google-services'"));
  });

  test('bumps numeric minSdk below 21 and leaves flutter.minSdkVersion', () {
    const src = '''
defaultConfig {
    minSdk = 19
    minSdkVersion flutter.minSdkVersion
}
''';
    final edit = ensureMinSdk(src);
    expect(edit.changed, isTrue);
    expect(edit.content, contains('minSdk = 21'));
    expect(edit.content, contains('minSdkVersion flutter.minSdkVersion'));
  });

  test('bumps Java 8 / jvmTarget 1.8 to 17', () {
    const src = '''
compileOptions {
    sourceCompatibility = JavaVersion.VERSION_1_8
    targetCompatibility = JavaVersion.VERSION_1_8
}
kotlinOptions {
    jvmTarget = '1.8'
}
''';
    final edit = ensureJvm17(src);
    expect(edit.changed, isTrue);
    expect(edit.content, contains('JavaVersion.VERSION_17'));
    expect(edit.content, contains("jvmTarget = '17'"));
  });

  test('adds classpath inside buildscript dependencies', () {
    const src = '''
buildscript {
    dependencies {
        classpath 'com.android.tools.build:gradle:8.1.0'
    }
}
''';
    final edit = ensureBuildscriptClasspath(src);
    expect(edit.changed, isTrue);
    expect(edit.content, contains("classpath 'com.google.gms:google-services:"));
    expect(ensureBuildscriptClasspath(edit.content).changed, isFalse);
  });
}
