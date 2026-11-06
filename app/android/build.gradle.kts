allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// 部分插件（如 amap_map 1.0.15）仍按 compileSdk 35 编译，而 flutter_plugin_android_lifecycle
// 要求 36 及以上。只提高插件的编译 SDK，不影响 minSdk/targetSdk。
subprojects {
    val raiseCompileSdk: Project.() -> Unit = {
        extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)?.let { ext ->
            if ((ext.compileSdk ?: 0) < 36) ext.compileSdk = 36
        }
    }
    if (state.executed) raiseCompileSdk() else afterEvaluate { raiseCompileSdk() }
}
// amap_map 1.0.15 自带的高德 SDK 10.1.200 的原生库只按 4 KB 对齐，不支持 16 KB 页设备；
// 统一换成新版。
subprojects {
    configurations.all {
        resolutionStrategy.force("com.amap.api:3dmap-location-search:11.3.100_loc11.3.101_sea9.8.1")
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
