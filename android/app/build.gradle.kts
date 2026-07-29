import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Firma de release. Las credenciales viven en android/key.properties, que está
// fuera del control de versiones; el keystore es android/nutrimat-upload.jks.
// Si el archivo no está, el release cae a la firma de debug para que
// `flutter run --release` siga andando en una máquina sin las claves.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val hasReleaseSigning = keystoreProperties.getProperty("storeFile") != null &&
    rootProject.file(keystoreProperties.getProperty("storeFile") ?: "").exists()

android {
    namespace = "io.nutrimat.nutrimat"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        // `flutter_local_notifications` usa java.time, que no existe antes de
        // API 26. El desugaring lo traduce para que ande desde minSdk 24.
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "io.nutrimat.app"
        // 24 es el piso de los plugins usados y del ícono adaptativo.
        // Health Connect (D-21) va a exigir 29 cuando se integre de verdad.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}

// ⚠️ No compilar con `--split-per-abi` mientras el updater baje un solo APK.
//
// Con esa opción el plugin de Flutter le suma a cada APK un corrimiento por
// arquitectura (`abi * 1000 + versionCode`): el universal queda en 11 y el de
// arm64 en 2011. Como el updater baja **siempre el universal**, quien había
// instalado el de su arquitectura recibía la actualización, la descargaba, y
// Android la rechazaba por downgrade (2011 → 12). El síntoma es "No se
// instaló la app", sin explicación, y no hay salida más que desinstalar —
// perdiendo los datos locales.
//
// Se intentó anular el corrimiento desde acá con `androidComponents
// .onVariants { output.versionCode.set(...) }` y **no alcanza**: el plugin lo
// pisa con la API vieja (`versionCodeOverride`) en su `afterEvaluate`, que
// corre después. Verificado con `aapt2 dump badging`: seguía dando 6000 /
// 7000 / 9000. Por eso el release publica un único APK universal en vez de
// pelearle al orden de los callbacks, y `release.yml` verifica el
// versionCode de lo que publica.

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    // `FileProvider`, para entregarle el APK de la actualización al instalador
    // de paquetes como `content://`. Va explícita y no de arrastre: lo que
    // llega transitivamente de un AAR no queda en el classpath de compilación.
    implementation("androidx.core:core-ktx:1.13.1")
}
