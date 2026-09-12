# Flutter engine classes are referenced reflectively from native code.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }

# Flutter's embedding references the Play Core split-install API to support
# deferred components. This app does not use deferred components and does not
# depend on Play Core, so those classes are legitimately absent — tell R8 not
# to treat the dangling references as errors.
-dontwarn com.google.android.play.core.**
