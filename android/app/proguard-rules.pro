# Brain Train release shrinking rules (R8 runs on every release build).
#
# WorkManager (pulled in by the Google Mobile Ads SDK) opens its Room database at
# launch through androidx.startup. Room finds the generated WorkDatabase_Impl by
# name and calls its no-argument constructor by reflection. The keep rule shipped
# with room-runtime 2.2.5 keeps the class but not that constructor, and R8's full
# mode removed it: every release build crashed at launch with "Failed to create
# an instance of androidx.work.impl.WorkDatabase" (1.1.0 build 9).
-keep class * extends androidx.room.RoomDatabase {
    <init>();
}
