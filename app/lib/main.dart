import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'data/database.dart';
import 'notifications/reminder_scheduler.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // الثلاثة دول لازم يخلصوا قبل أول إطار: أسماء الشهور بالعربي، قاعدة
  // البيانات المحلية، والمناطق الزمنية اللي الجدولة بتحسب عليها.
  await initializeDateFormatting('ar');
  final database = await AppDatabase.open();
  final scheduler = ReminderScheduler();
  // تهيئة الإشعارات ممكن ترمي (مثلًا مورد أيقونة ناقص من الـAPK) —
  // ولو رمت هنا التطبيق **ما يفتحش أبدًا**: الاستثناء بيحصل قبل runApp
  // فالمستخدم يفضل على شاشة الفتح للأبد. حصل فعلًا مع أيقونة شريط
  // الحالة. التذكيرات بدون تهيئة ما تشتغلش، لكن التطبيق يفتح ويقدر
  // يعرض مواعيده — وشريط تحذير الأذونات بيبان لأن hasPermission ترجع
  // false. تطبيق نصّه شغّال أحسن من شاشة ميتة.
  try {
    await scheduler.initialize();
  } on Object catch (e, stack) {
    debugPrint('فشلت تهيئة الإشعارات: $e');
    debugPrintStack(stackTrace: stack);
  }

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(database),
        schedulerProvider.overrideWithValue(scheduler),
      ],
      child: const SekerterApp(),
    ),
  );
}
