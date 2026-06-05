# mobile_scanner 7.2.0 keeps only direct com.google.mlkit.* classes. Release R8
# can remove nested barcode classes that ML Kit resolves while creating clients.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.libraries.barhopper.** { *; }
-keep class com.google.photos.** { *; }
