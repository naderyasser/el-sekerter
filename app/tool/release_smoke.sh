#!/usr/bin/env bash
# تدخين النسخة النهائية على أندرويد: تثبيت + تشغيل + تأكد إنها عايشة + صورة.
#
# ملف مستقل لأن reactivecircus/android-emulator-runner بينفّذ كل سطر من
# script: بـ sh -c لوحده — أي جملة متعددة الأسطر بتتقطع وبتفشل بـ
# «Syntax error: expecting fi» (حصل فعلًا). هنا بنتنده بسطر واحد.
set -euo pipefail

adb install -r build/app/outputs/flutter-apk/app-release.apk
adb logcat -c
adb shell am start -n com.elsekerter.sekerter/.MainActivity
sleep 25

pid=$(adb shell pidof com.elsekerter.sekerter || true)
if [ -z "$pid" ]; then
  echo "::error::النسخة النهائية وقعت عند الإقلاع — مش هتتنشر"
  adb logcat -d | grep -iE "FATAL|AndroidRuntime" | tail -50 || true
  exit 1
fi

if adb logcat -d | grep -q "FATAL EXCEPTION"; then
  echo "::error::انهيار في اللوج رغم إن العملية عايشة"
  adb logcat -d | grep -A25 "FATAL EXCEPTION" | tail -60 || true
  exit 1
fi

adb exec-out screencap -p > release-boot.png
echo "النسخة النهائية فتحت وعايشة (pid=$pid) ✅"
