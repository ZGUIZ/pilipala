allprojects {
    repositories {
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/central") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        google()
        mavenCentral()
    }
}

// 为缺少 namespace 的旧插件补充 namespace（AGP 8.x 要求）
val namespaceMap = mapOf(
    "appscheme" to "com.app.scheme",
    "auto_orientation" to "de.bytepark.autoorientation",
    "device_info" to "io.flutter.plugins.deviceinfo",
    "gt3_flutter_plugin" to "com.geetest.gt3captcha.gt3_flutter_plugin",
    "status_bar_control" to "com.foo.statusbarcontrol",
    "system_proxy" to "com.kaivean.system_proxy",
    "webview_cookie_manager" to "io.flutter.plugins.webview_cookie_manager",
)

subprojects {
    val ns = namespaceMap[project.name]

    // 部分旧插件在自身 build.gradle 中硬编码了较低的 compileSdkVersion，
    // 会因缺少新版 Android 属性（如 android:attr/lStar）导致资源链接失败。
    // 这里在其构建脚本求值之后统一覆盖。
    // 注意：此钩子必须注册在 evaluationDependsOn 之前，否则项目已被求值。
    afterEvaluate {
        extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)
            ?.let { ext ->
                if (ns != null && ext.namespace == null) {
                    ext.namespace = ns
                }
                if (ext.compileSdk == null || ext.compileSdk!! < 34) {
                    ext.compileSdk = 34
                }
            }
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
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}