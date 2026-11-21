# The AdMob SDK pulls in WorkManager 2.7 / Room 2.2.5, whose bundled rule keeps
# Room database classes but not their no-arg constructor. R8 full mode then
# strips it and WorkManager crashes at startup ("Failed to create an instance
# of androidx.work.impl.WorkDatabase"). Room creates these reflectively.
-keep class * extends androidx.room.RoomDatabase { <init>(); }
