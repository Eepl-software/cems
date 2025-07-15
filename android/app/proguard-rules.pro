# Keep all ML Kit Vision classes
-keep class com.google.mlkit.vision.** { *; }
-dontwarn com.google.mlkit.vision.**

# Keep specific language recognizer options
-keep class com.google.mlkit.vision.text.chinese.** { *; }
-keep class com.google.mlkit.vision.text.japanese.** { *; }
-keep class com.google.mlkit.vision.text.korean.** { *; }
-keep class com.google.mlkit.vision.text.devanagari.** { *; }
