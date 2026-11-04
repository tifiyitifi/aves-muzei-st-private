# cf https://developer.android.com/topic/performance/app-optimization/add-keep-rules

# e.g. com.drew.metadata.exif.ExifSubIFDDirectory
-keep class com.drew.metadata.**{ *; }

-keep class org.beyka.tiffbitmapfactory.**{ *; }

-keep class org.mp4parser.**{ *; }

# referenced from: com.google.crypto.tink
-dontwarn com.google.errorprone.annotations.**
-dontwarn javax.annotation.**

# The ported ReFra editor navigates with Compose Navigation's type-safe routes, which resolve the
# route class through kotlinx.serialization at runtime. kotlinx's bundled rules cover the generated
# serializers, but the reflective lookup also needs the route classes themselves (and the enum
# arguments their serializers carry) to survive R8.
-keep class com.dot.gallery.feature_node.domain.model.editor.** { *; }
-keep class com.dot.gallery.feature_node.presentation.edit.adjustments.varfilter.VariableFilterTypes { *; }
-keep class com.dot.gallery.feature_node.presentation.edit.adjustments.filters.ImageFilterTypes { *; }