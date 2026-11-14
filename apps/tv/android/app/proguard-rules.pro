# Flutter / media_kit / media_kit_video — keep JNI entry points.
-keep class com.alexmercerind.** { *; }
-keep class com.alexmercerind.media_kit_video.** { *; }
-dontwarn com.alexmercerind.**

# Play Core (deferred components) — not shipped; silence R8 missing-class errors.
-dontwarn com.google.android.play.core.**

# Keep Flutter embedding.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
