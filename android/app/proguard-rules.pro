# Play Store split install rules
-dontwarn com.google.android.play.core.**

# Flutter rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }

# GoMobile rules
-keep class libxray.** { *; }
-keep class go.** { *; }
