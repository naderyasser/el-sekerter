plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.elsekerter.sekerter"
    // flutter_secure_storage و permission_handler_android بيطلبوا 37، وفحص
    // AAR بيوقّع البناء لو أقل. Flutter لسه على 36 فبنحدّدها بإيدينا.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications بيستخدم java.time، وده بيحتاج
        // desugaring عشان يشتغل على أندرويد أقدم من 8.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.elsekerter.sekerter"
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

    // مفتاح توقيع ثابت — الملف نفسه **مش** في الريبو (الريبو عام، ومفتاح
    // منشور معناه إن أي حد يقدر يوقّع نسخة مزيفة تتثبّت فوق تطبيق المستخدم).
    // الـCI بيفكّه من GitHub Secret اسمه ANDROID_KEYSTORE_B64 قبل البناء.
    //
    // ليه أصلًا مفتاح ثابت؟ التوقيع بمفاتيح الديباج كان بيولّد مفتاح *جديد*
    // على رَنَر GitHub في كل بيلد، وأندرويد يرفض تثبيت تحديث توقيعه مختلف
    // عن المثبّت — **ويرفض بصمت**. النتيجة اللي حصلت فعلًا: المستخدم «يحدّث»
    // ويفضل على النسخة القديمة من غير ما يعرف.
    //
    // الباسورد مكتوب هنا عادي: من غير ملف المفتاح نفسه مالوش أي قيمة.
    // محليًا (flutter run) الملف مش موجود فبنقع على مفاتيح الديباج.
    signingConfigs {
        create("release") {
            val keystore = file("sekerter-release.jks")
            if (keystore.exists()) {
                storeFile = keystore
                storePassword = "sekerter2026"
                keyAlias = "sekerter"
                keyPassword = "sekerter2026"
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (file("sekerter-release.jks").exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // التصغير مطفّي عن قصد. R8 كان بيشوّه ويشيل كود الإضافات اللي
            // بتتنده عبر method channels (permission_handler, url_launcher,
            // android_intent_plus, speech_to_text) من غير keep rules —
            // فالأذونات والاتصال والواتساب والصوت كلهم كانوا بيفشلوا في
            // صمت في نسخة release. التطبيق يتوزّع يدوي (مش على المتجر)
            // فمفيش داعي أصلًا للتصغير، والحجم الأكبر شوية مقبول تمامًا.
            // ده كمان بيمنع شيل أيقونة الإشعار اللي كانت بتوقّع الإقلاع.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
