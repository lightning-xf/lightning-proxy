plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.lightning.proxy"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.lightning.proxy"
        minSdk = 26
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName

/*
        ndk {
            // [Optimization] 锁定目标架构，剔除冗余 ABI
            abiFilters.addAll(listOf("arm64-v8a", "armeabi-v7a", "x86_64"))
        }
*/

        externalNativeBuild {
            cmake {
                arguments("-DCMAKE_C_COMPILER_WORKS=1", "-DCMAKE_CXX_COMPILER_WORKS=1")
            }
        }
    }

    externalNativeBuild {
        cmake {
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            // [Optimization] 开启混淆与资源缩减，极限压缩产物体积
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // [Fix] 铁血防缓存：强制 Gradle 每次构建都检查本地 AAR 变更
    // 配合 build_release 脚本中的物理覆盖，确保 Go 核心逻辑实时同步
    implementation(files("libs/libxray.aar") {
        builtBy("rebuildXray") 
    })
}

// 注册一个虚拟任务，辅助 Gradle 感知 AAR 文件的物理变化
tasks.register("rebuildXray") {
    inputs.file("libs/libxray.aar")
}
