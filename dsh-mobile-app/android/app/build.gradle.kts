import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // 显式应用 Kotlin（settings 已声明 2.4.0）：冷启动可靠，不依赖 Flutter 插件动态应用
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release 签名：读取 android/key.properties（gitignore，见根 .gitignore）。
// 没有 key.properties 时 release 直接失败，不再静默回退 debug 签名。
// debug 密钥签出来的包和正式包不是同一个应用，静默回退会让人装出两份或覆盖失败。
// debug / profile 不走这条检查，干净克隆仍可 flutter run、flutter test。
// 仅测试分发需要 debug 签名的 release 包时显式打开（产物无法覆盖已安装的正式包）：
//   ORG_GRADLE_PROJECT_allowDebugSignedRelease=true flutter build apk --release
//   或在 android/ 目录：./gradlew assembleRelease -PallowDebugSignedRelease=true
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

fun gradleFlag(name: String): Boolean {
    val values = listOf(
        findProperty(name)?.toString(),
        rootProject.findProperty(name)?.toString(),
        System.getenv("ORG_GRADLE_PROJECT_$name"),
    )
    return values.any { it?.equals("true", ignoreCase = true) == true }
}

val allowDebugSignedRelease = gradleFlag("allowDebugSignedRelease")

android {
    namespace = "com.dsh.remote"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.dsh.remote"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                // storeFile 相对 android/ 项目根（key.properties 里写 app/dsh-release.jks）
                storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            } else if (allowDebugSignedRelease) {
                // 显式放行：测试 / CI 用 debug 密钥签 release。
                signingConfig = signingConfigs.getByName("debug")
            }
            // 否则不签名。真正执行 release 任务时由下面的检查失败，debug 构建不受影响。
        }
    }
}

// 配置期不能抛：AGP 会在 flutter run / assembleDebug 时同样配置 release buildType。
// 等任务图确定后再看是不是真的在打 release。
gradle.taskGraph.whenReady {
    if (keystorePropertiesFile.exists() || allowDebugSignedRelease) return@whenReady
    val buildingRelease = allTasks.any { task ->
        task.project == project &&
            task.name.endsWith("Release") &&
            (task.name.startsWith("assemble") ||
                task.name.startsWith("bundle") ||
                task.name.startsWith("install") ||
                task.name.startsWith("package") ||
                task.name.startsWith("sign"))
    }
    if (buildingRelease) {
        throw GradleException(
            """
            Release 构建失败：缺少 android/key.properties，已拒绝回退到 debug 签名。
            正式包请先生成 keystore 并写入 key.properties（见 dsh-mobile-app/README.md）。
            调试请用 flutter run 或 flutter build apk --debug，不需要正式签名。
            仅测试分发可显式放行（产物用 debug 密钥签名，无法覆盖已安装的正式包）：
              ORG_GRADLE_PROJECT_allowDebugSignedRelease=true flutter build apk --release
              或在 android/ 目录执行 ./gradlew assembleRelease -PallowDebugSignedRelease=true
            """.trimIndent()
        )
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // 悬浮球面板模型 seam 的纯 JVM 单测（UsagePanelModelTest）：
    // org.json 在 Android 与 JVM 同规范，测试类路径单独引入即可。
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
}

