import java.security.KeyStore
import java.util.Base64

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "app.volti.volti"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "app.volti.volti"
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

    // Fester Signier-Schlüssel aus den GitHub-Geheimnissen (VOLTI_KEYSTORE als
    // Base64 der .jks, VOLTI_KEYSTORE_PASSWORD). Nur mit immer demselben
    // Schlüssel lässt Android ein Update über die installierte App installieren
    // (auch über Obtainium). Der Name des Schlüssels in der Datei wird gelesen,
    // so passt auch der Schlüssel von Conti. Fehlt er, wird mit dem Test-Schlüssel
    // signiert (dann muss man vor einem Update die alte App entfernen).
    val keystoreB64 = System.getenv("VOLTI_KEYSTORE") ?: ""
    val keystorePassword = System.getenv("VOLTI_KEYSTORE_PASSWORD") ?: ""
    val hasKey = keystoreB64.isNotBlank() && keystorePassword.isNotBlank()
    signingConfigs {
        if (hasKey) {
            create("release") {
                val f = layout.buildDirectory.file("volti-release.jks").get().asFile
                f.parentFile.mkdirs()
                f.writeBytes(Base64.getMimeDecoder().decode(keystoreB64.trim()))
                val ks = KeyStore.getInstance(KeyStore.getDefaultType())
                f.inputStream().use { ks.load(it, keystorePassword.toCharArray()) }
                storeFile = f
                storePassword = keystorePassword
                keyAlias = ks.aliases().nextElement()
                keyPassword = keystorePassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasKey) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
        }
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
