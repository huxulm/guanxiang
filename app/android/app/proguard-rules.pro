# 高德地图 SDK：官方要求保留这些包，否则 release 包（R8 压缩）运行时会找不到类
-keep class com.amap.** { *; }
-keep class com.autonavi.** { *; }
-keep class com.loc.** { *; }
-dontwarn com.amap.**
-dontwarn com.autonavi.**
-dontwarn com.loc.**
