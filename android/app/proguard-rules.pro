# R8 / ProGuard rules for the release build.

# yt-dlp / ffmpeg wrapper: loaded and called through reflection and JSON mapping.
-keep class com.yausername.** { *; }
-keep class io.github.junkfood02.** { *; }
-keepclassmembers class com.yausername.** { *; }

# JSON mapping used by the wrapper.
-keep class com.fasterxml.jackson.** { *; }
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod
-dontwarn com.fasterxml.jackson.databind.**
-dontwarn java.beans.**
-dontwarn javax.lang.model.**

# Archive extraction used while unpacking the bundled python / ffmpeg.
-keep class org.apache.commons.compress.** { *; }
-dontwarn org.apache.commons.compress.**
-dontwarn org.tukaani.xz.**
-dontwarn com.github.luben.zstd.**
-dontwarn org.brotli.dec.**

# Our own platform channels.
-keep class com.example.mediahub.** { *; }
