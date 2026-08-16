# فشل بناء الـAPK — الشبكة مقفولة على dl.google.com

**التاريخ:** 2026-08-16 (UTC)
**الكوميت:** 15d8f08 (master)
**السبب:** بيئة التنفيذ البعيدة بتمنع الاتصال بـ `dl.google.com`، وده الهوست الوحيد لتنزيل Android SDK (commandlinetools + platforms + build-tools). من غيره مافيش بناء أندرويد.

## ناتج فحص الشبكة (الأمر المطلوب في الخطوة ١)

```
$ curl -sI https://dl.google.com/android/repository/repository2-3.xml
HTTP/1.1 403 Forbidden
Content-Type: text/plain; charset=utf-8
X-Content-Type-Options: nosniff
Content-Length: 71
```

## إعادة المحاولة (٣ مرات بفاصل ثانيتين)

```
attempt 1: 000
attempt 2: 000
attempt 3: 000
```

## تشخيص إضافي من بروكسي البيئة

سجلّ البروكسي (`$HTTPS_PROXY/__agentproxy/status`) بيأكد إن الرفض سياسة شبكة مش عطل مؤقت:

```
"kind": "connect_rejected",
"detail": "gateway answered 403 to CONNECT (policy denial or upstream failure)",
"host": "dl.google.com:443"
```

للمقارنة: `storage.googleapis.com` (هوست Flutter engine) شغّال وبيرد — المشكلة محصورة في `dl.google.com`.

## المطلوب عشان البناء ينجح المرة الجاية

إضافة `dl.google.com` (ويُفضَّل كمان `maven.google.com`) لقائمة الهوستات المسموحة في network policy بتاعة بيئة Claude Code البعيدة، وبعدين إعادة تشغيل المهمة.
