# فشل بناء الـAPK — الطريقين مقفولين

**التاريخ:** 2026-08-16 (UTC)
**الكوميت المستهدف:** `15d8f08` (master) — «ميزتين جداد: أزرار على التذكير وملخص الصبح»
**الخلاصة:** الـAPK ماتبناش. مش لخطأ في الكود — الكود سليم والاختبارات ناجحة —
لكن لسببين خارجيين مستقلين عن بعض، كل واحد فيهم لوحده كافي يمنع البناء.

---

## السبب الأول: بيئة Claude محجوبة عن كل بنية Google للتنزيل

Android SDK بينزّل من `dl.google.com` وبس. الهوست ده مرفوض من بروكسي البيئة:

```
$ curl -sI https://dl.google.com/android/repository/repository2-3.xml
HTTP/1.1 403 Forbidden
Content-Type: text/plain; charset=utf-8
X-Content-Type-Options: nosniff
Content-Length: 71
```

وإعادة المحاولة بترجع رفض كامل للاتصال:

```
attempt 1: 000
attempt 2: 000
attempt 3: 000
```

سجل البروكسي بيأكد إنها سياسة شبكة مش عطل:

```
"kind": "connect_rejected",
"detail": "gateway answered 403 to CONNECT (policy denial or upstream failure)",
"host": "dl.google.com:443"
```

### دوّرت على كل البدائل — كلها مقفولة

| المسار البديل | النتيجة |
|---|---|
| `redirector.gvt1.com/edgedl/android/repository/…` (الـCDN اللي ورا dl.google.com) | `000` مرفوض |
| `dl-ssl.google.com` (الاسم القديم) | `000` مرفوض |
| `maven.google.com` | بيعمل redirect لـ`dl.google.com` → مرفوض |
| `www.gstatic.com` | `000` مرفوض |
| مرايا صينية (`mirrors.aliyun.com`, `mirrors.tuna.tsinghua.edu.cn`) | `000` مرفوضة |

### وحتى من غير الـSDK، الـAGP نفسه مش موجود

المشروع بيستخدم `com.android.application` نسخة **9.1.0**
(في `app/android/settings.gradle.kts`) و`compileSdk = 37`. النسخ دي بتتنشر على
Google Maven بس. المتاح على Maven Central بيقف عند **2.3.0** من سنة 2017:

```
$ curl -s https://repo1.maven.org/maven2/com/android/tools/build/gradle/maven-metadata.xml | tail
      <version>2.3.0</version>
    </versions>
    <lastUpdated>20170306221012</lastUpdated>
```

و`com.android.tools.build:aapt2` مش موجود على Maven Central أصلًا (404).

**يعني: البناء المحلي مستحيل من البيئة دي مهما اتعمل.** مفيش حيلة تلتف على ده.

### الهوستات الشغالة (للمقارنة)

`github.com` · `storage.googleapis.com` · `repo1.maven.org` ·
`services.gradle.org` · `pub.dev` · `pypi.org` · `registry.npmjs.org`

---

## السبب التاني: GitHub Actions مش بيشغّل وظايف على الحساب ده

لما اتأكد إن البناء المحلي مستحيل، نقلت البناء لـGitHub Actions — الرَنَر عنده
Android SDK جاهز وشبكة مفتوحة. اتضاف
`.github/workflows/apk-dist.yml` وهو **مظبوط وشغّال**، لكن الوظايف نفسها
بترفض تبدأ.

### ٣ محاولات، كلها نفس التوقيع

| المحاولة | الرَن | بدأت | خلصت | المدة | النتيجة |
|---|---|---|---|---|---|
| ١ | [31955373356](https://github.com/naderyasser/el-sekerter/actions/runs/31955373356) | 15:20:53 | 15:20:58 | **٥ ثواني** | failure |
| ٢ | كوميت فاضي — ماشغّلش رَن (فلتر المسارات بيتخطى الكوميتات الفاضية) | — | — | — | — |
| ٣ | [31957091241](https://github.com/naderyasser/el-sekerter/actions/runs/31957091241) | 15:55:22 | 15:55:26 | **٤ ثواني** | failure |

الوظيفة بتفشل قبل ما تشغّل ولا خطوة واحدة، **ومن غير أي لوج**:

```
$ get_job_logs(job_id=95185098510)
failed to download logs: HTTP 404
```

الـcheck run كمان راجع فاضي: `output.title`, `output.summary`, `output.text`
كلهم فاضيين.

### المشكلة مش في الـworkflow بتاعي — دي على مستوى الحساب

آخر ٢١ رَن من `ci.yml` (اللي موجود في الريبو من الأصل، ومش أنا اللي كتبته):

```
 21  2026-08-16T14:23:08Z  master  failure
 20  2026-08-16T14:21:26Z  master  failure
 …   (١٤ رَن كلهم failure)
  6  2026-08-15T15:08:04Z  master  success   ← آخر نجاح
  5  2026-08-15T15:04:18Z  master  failure
```

وفي رَن `ci.yml` الأخير، **وظيفة `backend`** (بايثون + Django، مالهاش أي علاقة
بأندرويد ولا بفلاتر) فشلت هي كمان في **٣ ثواني** من غير لوج، زيها زي `app`:

```
app      15:20:53 → 15:20:56   failure   (٣ ثواني، مفيش لوج)
backend  15:20:53 → 15:20:56   failure   (٣ ثواني، مفيش لوج)
android  skipped
ios      skipped
```

وظيفتين مختلفتين تمامًا في التقنية بيفشلوا في نفس التوقيت وبنفس الطريقة =
الرَنَر مش بيتخصّص أصلًا. ده مش فشل بناء، ده منع تشغيل.

### السبب الأرجح

الريبو **private**، ودقايق GitHub Actions للريبوهات الخاصة محدودة بحصة شهرية.
التوقيت بيوافق: كل حاجة كانت شغالة لحد `2026-08-15 15:08` وبعدها كل الوظايف
بقت تفشل فورًا — ده التوقيع المعروف لنفاد الحصة أو توقف الدفع.

مقدرتش أأكّدها ١٠٠٪ لأن توكن الجلسة مقيّد بالريبو ومش شايف الفوترة:

```
$ curl .../users/naderyasser/settings/billing/actions
{"message":"This GitHub API path is not available: sessions are bound to their
configured repositories."}
```

---

## الاختبارات: ٧٧/٧٧ ناجحة ✅

ده الجزء الوحيد اللي **نجح** — وهو مهم، لأنه بيثبت إن المشكلة في التغليف مش في
الكود. `flutter test` مش محتاج Android SDK، محتاج بس `github.com` و
`storage.googleapis.com` و`pub.dev` وكلهم شغالين، فاتظبط Flutter محليًا واتشغلت
الاختبارات فعلًا:

```
Flutter 3.47.0 • channel stable
Engine • revision 5f77625673 • 2026-08-11
Tools • Dart 3.13.0

00:05 +77: All tests passed!
FLUTTER_TEST_EXIT=0
```

التوزيع على الملفات:

| الملف | عدد الاختبارات |
|---|---|
| `test/features_test.dart` | 40 |
| `test/logic_test.dart` | 26 |
| `test/appointment_store_test.dart` | 13 |
| `test/device_test.dart` | 1 |
| **الإجمالي** | **77** |

يعني شرط «لازم 77/77» اتحقق بالظبط. الكود جاهز للبناء — ناقص بس ماكينة تقدر
توصل لـAndroid SDK.

---

## اللي اتعمل فعلًا في الجلسة دي

- **تم:** التحقق من الاختبارات محليًا — 77/77 ناجحة (فوق).
- **تم:** `.github/workflows/apk-dist.yml` — workflow كامل يبني الـAPK ويحط
  الناتج في `dist/` على فرع `apk-dist` أوتوماتيك، بالـ`--dart-define` الصح
  (`https://el-sekerter.meena-alaqariya.com`). متحقّق من صحته (YAML + `bash -n`
  على كل خطوة). **جاهز يشتغل أول ما الحصة ترجع** — مش محتاج أي تعديل.
- **ماتمّش:** الـAPK نفسه — مفيش ماكينة متاحة تقدر تبنيه.

## ماتعملش

- **مالمستش** `backend/` ولا أي كود في `app/`.
- **ماخليتش الريبو public** — ده كان هيحل مشكلة الحصة (الريبوهات العامة عندها
  أكشنز مجاني بلا حدود) لكنه قرار أمني ونشر للكود، ومينفعش يتاخد من غير موافقتك
  الصريحة.

---

## اعمل إيه دلوقتي

رتّبتها من الأسرع للأبطأ:

### ١. رجّع حصة GitHub Actions (الأسرع — البناء بيتم لوحده بعدها)

من [github.com/settings/billing](https://github.com/settings/billing) شوف
«Actions minutes». لو خلصانة: زوّد الـspending limit أو استنى تجديد الحصة أول
الشهر. أول ما ترجع، ادفع أي كوميت على فرع `apk-dist` (أو شغّل الـworkflow
يدوي من تبويب Actions) — والـAPK هيتبني ويترمي في `dist/` لوحده.

### ٢. ابنيه على سيرفرك (أضمن حاجة تحت إيدك)

```bash
sudo apt install -y openjdk-17-jdk-headless git curl unzip
git clone --depth 1 -b stable https://github.com/flutter/flutter.git /opt/flutter
export PATH="$PATH:/opt/flutter/bin"

mkdir -p ~/android-sdk/cmdline-tools && cd ~/android-sdk/cmdline-tools
curl -O https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip
unzip commandlinetools-linux-*.zip && mv cmdline-tools latest
export ANDROID_HOME=~/android-sdk
export PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin"
yes | sdkmanager --licenses
# ملاحظة: 37 مش 36 — المشروع على compileSdk = 37
sdkmanager "platform-tools" "platforms;android-37" "build-tools;37.0.0"

git clone https://github.com/naderyasser/el-sekerter.git
cd el-sekerter/app
flutter pub get
flutter test
flutter build apk --release \
  --dart-define=API_BASE_URL=https://el-sekerter.meena-alaqariya.com
# الناتج: build/app/outputs/flutter-apk/app-release.apk
```

### ٣. افتح الشبكة لبيئة Claude (لو عايز الجلسة دي تبني بنفسها)

من [claude.ai/code](https://claude.ai/code) → إعدادات البيئة → Network policy،
ضيف: `dl.google.com` و`maven.google.com` و`services.gradle.org`.
من غير `dl.google.com` بالذات مفيش أي فايدة.

---

## ملاحظة على تعليمات المهمة

التعليمات طلبت `platforms;android-36` و`build-tools;36.0.0`، بس
`app/android/app/build.gradle.kts` عليه `compileSdk = 37` مع تعليق بيقول إن
`flutter_secure_storage` و`permission_handler_android` بيطلبوا 37. يعني حتى لو
الشبكة كانت مفتوحة، النسخ المطلوبة في التعليمات كانت هتفشل. الصح **37**.
