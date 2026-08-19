import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// حماية التطبيق من قتل الخلفية على أجهزة الشركات الصينية.
///
/// المشكلة حقيقية ومالهاش حل برمجي كامل: شاومي وأوبو وفيفو وهواوي وتكنو
/// وإنفنكس بتضيف طبقة «تشغيل تلقائي» فوق أندرويد، والتطبيق اللي مش مفعّل
/// فيها بيتقتل لما المستخدم يقفله من المهام الأخيرة — ومعاه منبّهاته.
/// الإعداد ده **ما ينفعش يتفعّل من الكود**؛ لازم المستخدم يفعّله بإيده.
///
/// اللي نقدر نعمله: نوصّله للصفحة الصح بضغطة واحدة بدل ما يدوّر فيها.
/// وشاشات الشركات دي مش مضمونة تفضل بنفس الاسم، فكل محاولة ليها بديل،
/// وآخر بديل هو صفحة إعدادات التطبيق العادية اللي موجودة على كل جهاز.
class AutostartService {
  const AutostartService();

  /// شاشات «التشغيل التلقائي» المعروفة لكل شركة.
  ///
  /// المفتاح جزء من اسم الشركة زي ما `Build.MANUFACTURER` بيرجّعه.
  static const Map<String, List<(String, String)>> _screens = {
    'xiaomi': [
      (
        'com.miui.securitycenter',
        'com.miui.permcenter.autostart.AutoStartManagementActivity',
      ),
    ],
    'redmi': [
      (
        'com.miui.securitycenter',
        'com.miui.permcenter.autostart.AutoStartManagementActivity',
      ),
    ],
    'poco': [
      (
        'com.miui.securitycenter',
        'com.miui.permcenter.autostart.AutoStartManagementActivity',
      ),
    ],
    'oppo': [
      (
        'com.coloros.safecenter',
        'com.coloros.safecenter.permission.startup.StartupAppListActivity',
      ),
      (
        'com.oppo.safe',
        'com.oppo.safe.permission.startup.StartupAppListActivity',
      ),
    ],
    'realme': [
      (
        'com.coloros.safecenter',
        'com.coloros.safecenter.permission.startup.StartupAppListActivity',
      ),
    ],
    'oneplus': [
      (
        'com.oneplus.security',
        'com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity',
      ),
    ],
    'vivo': [
      (
        'com.vivo.permissionmanager',
        'com.vivo.permissionmanager.activity.BgStartUpManagerActivity',
      ),
    ],
    'huawei': [
      (
        'com.huawei.systemmanager',
        'com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity',
      ),
      (
        'com.huawei.systemmanager',
        'com.huawei.systemmanager.optimize.process.ProtectActivity',
      ),
    ],
    'honor': [
      (
        'com.huawei.systemmanager',
        'com.huawei.systemmanager.optimize.process.ProtectActivity',
      ),
    ],
    // تكنو وإنفنكس وآيتل كلهم Transsion بنفس طبقة HiOS/XOS.
    'tecno': [
      (
        'com.transsion.phonemaster',
        'com.cyin.himgr.autostart.AutoStartActivity',
      ),
    ],
    'infinix': [
      (
        'com.transsion.phonemaster',
        'com.cyin.himgr.autostart.AutoStartActivity',
      ),
    ],
    'itel': [
      (
        'com.transsion.phonemaster',
        'com.cyin.himgr.autostart.AutoStartActivity',
      ),
    ],
    'samsung': [
      (
        'com.samsung.android.lool',
        'com.samsung.android.sm.ui.battery.BatteryActivity',
      ),
    ],
  };

  /// هل الجهاز ده من الشركات اللي محتاجة الخطوة الزيادة دي؟
  ///
  /// بنسأل النظام عن الشركة بدل ما نفترض — الرد بيحدد نص الشرح كمان.
  Future<String?> vendor() async {
    if (!Platform.isAndroid) return null;
    final name = (await _manufacturer())?.toLowerCase();
    if (name == null) return null;
    for (final key in _screens.keys) {
      if (name.contains(key)) return key;
    }
    return null;
  }

  Future<String?> _manufacturer() async {
    try {
      final result = await Process.run('getprop', ['ro.product.manufacturer']);
      final value = (result.stdout as String).trim();
      return value.isEmpty ? null : value;
    } on Object catch (e) {
      // getprop مش متاح على كل جهاز — مش سبب لتعطيل الزرار.
      debugPrint('تعذّرت قراءة اسم الشركة: $e');
      return null;
    }
  }

  /// يفتح شاشة التشغيل التلقائي، أو أقرب بديل. بيرجّع false لو كل
  /// المحاولات فشلت — وساعتها الواجهة بتشرح الخطوات بالنص.
  Future<bool> openAutostartSettings() async {
    if (!Platform.isAndroid) return false;

    final key = await vendor();
    for (final (package, activity)
        in _screens[key] ?? const <(String, String)>[]) {
      if (await _launch(package, activity)) return true;
    }

    // مافيش شاشة معروفة: نفتح إعدادات التطبيق العادية — على الأقل منها
    // يوصل لـ«البطارية» و«غير مقيّد».
    try {
      return await openAppSettings();
    } on Object catch (e) {
      debugPrint('تعذّر فتح إعدادات التطبيق: $e');
      return false;
    }
  }

  Future<bool> _launch(String package, String activity) async {
    final intent = AndroidIntent(
      action: 'android.intent.action.MAIN',
      package: package,
      componentName: activity,
    );
    try {
      // الشاشات دي بتختفي وتتغيّر بين نسخ النظام، فبنسأل الأول بدل ما
      // نرمي ActivityNotFoundException في وش المستخدم.
      if (await intent.canResolveActivity() ?? false) {
        await intent.launch();
        return true;
      }
    } on Object catch (e) {
      debugPrint('تعذّر فتح $activity: $e');
    }
    return false;
  }
}
