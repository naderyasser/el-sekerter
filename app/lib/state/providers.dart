import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../data/appointment_store.dart';
import '../data/chat_store.dart';
import '../data/database.dart';
import '../data/settings_store.dart';
import '../device/action_runner.dart';
import '../device/calendar_service.dart';
import '../device/contacts_service.dart';
import '../device/messaging_service.dart';
import '../notifications/reminder_scheduler.dart';
import '../voice/speech_service.dart';

/// الخدمات اللي عمرها ما بتتغيّر خلال حياة التطبيق.
///
/// قاعدة البيانات والمجدول بيتفتحوا في main() قبل runApp، فبنحقنهم هنا
/// بـoverride بدل ما نعمل تهيئة كسولة جوّه الشاشات.
final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('لازم يتحقن في main()'),
);

final schedulerProvider = Provider<ReminderScheduler>(
  (ref) => throw UnimplementedError('لازم يتحقن في main()'),
);

final settingsStoreProvider = Provider<SettingsStore>((ref) => SettingsStore());

final appointmentStoreProvider = Provider<AppointmentStore>(
  (ref) => AppointmentStore(ref.watch(databaseProvider).db),
);

final chatStoreProvider = Provider<ChatStore>(
  (ref) => ChatStore(ref.watch(databaseProvider).db),
);

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(ref.watch(settingsStoreProvider)),
);

final speechServiceProvider = Provider<SpeechService>((ref) => SpeechService());

final contactsServiceProvider = Provider<ContactsService>(
  (ref) => ContactsService(),
);

final messagingServiceProvider = Provider<MessagingService>(
  (ref) => MessagingService(),
);

final calendarServiceProvider = Provider<CalendarService>(
  (ref) => CalendarService(),
);

final actionRunnerProvider = Provider<DeviceActionRunner>(
  (ref) => DeviceActionRunner(
    ref.watch(contactsServiceProvider),
    ref.watch(messagingServiceProvider),
  ),
);

/// هل التطبيق متظبّط (فيه توكن)؟ بيحدد لو نعرض شاشة الإعداد الأول.
final isConfiguredProvider = FutureProvider<bool>(
  (ref) => ref.watch(settingsStoreProvider).isConfigured(),
);
