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
  await scheduler.initialize();

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
