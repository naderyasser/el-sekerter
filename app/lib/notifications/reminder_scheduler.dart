import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/config.dart';
import '../models/appointment.dart';

/// جدولة التذكيرات على الجهاز.
///
/// ده قلب التطبيق: التذكيرات محجوزة عند نظام التشغيل نفسه، فبترنّ حتى لو
/// التطبيق مقفول أو مفيش نت أو السيرفر واقع.
///
/// فروق المنصّتين:
///   • أندرويد — قناة بأقصى أهمية، وجدولة دقيقة لو الإذن متاح.
///   • آيفون — إشعار بمستوى timeSensitive عشان يخترق وضع التركيز. أبل بتحدّ
///     الإشعارات المجدولة بـ٦٤ لكل تطبيق وبترمي الزيادة بصمت، عشان كده بنجدول
///     أقرب [AppConfig.maxScheduledReminders] بس وبنعيد الجدولة كل ما حاجة
///     تتغيّر.
class ReminderScheduler {
  ReminderScheduler([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  bool _ready = false;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

  IOSFlutterLocalNotificationsPlugin? get _ios =>
      _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();

  /// تتنده مرة واحدة في main() قبل runApp.
  Future<void> initialize({
    void Function(NotificationResponse)? onTap,
  }) async {
    if (_ready) return;

    tzdata.initializeTimeZones();
    // zonedSchedule بتحسب على المنطقة المحلية، والافتراضي UTC. من غير السطر
    // ده كل التذكيرات هتزحف بفرق التوقيت.
    final zone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(zone.identifier));

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          // الأذونات بنطلبها صراحة في شاشة الإعداد عشان نقدر نشرح للمستخدم
          // قبل ما النظام يسأله.
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: onTap,
    );

    await _createAndroidChannel();
    _ready = true;
  }

  Future<void> _createAndroidChannel() async {
    await _android?.createNotificationChannel(
      const AndroidNotificationChannel(
        AppConfig.reminderChannelId,
        AppConfig.reminderChannelName,
        description: AppConfig.reminderChannelDescription,
        importance: Importance.max,
      ),
    );
  }

  /// يطلب أذونات الإشعارات. بيرجّع false لو المستخدم رفض.
  Future<bool> requestPermissions() async {
    if (Platform.isIOS) {
      final granted = await _ios?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }

    final granted = await _android?.requestNotificationsPermission() ?? false;
    // الجدولة الدقيقة إذن منفصل من أندرويد 13؛ من غيره التذكير ممكن يتأخر
    // شوية لكن مش بيقف، فمش بنعتبر رفضه فشل.
    await _android?.requestExactAlarmsPermission();
    return granted;
  }

  Future<bool> hasPermission() async {
    if (Platform.isIOS) {
      final options = await _ios?.checkPermissions();
      return options?.isAlertEnabled ?? false;
    }
    return await _android?.areNotificationsEnabled() ?? false;
  }

  /// يمسح كل التذكيرات ويجدول من أول وجديد.
  ///
  /// إعادة الجدولة الكاملة أبسط وأأمن من التتبّع التفاضلي: عدد المواعيد صغير،
  /// والحساب رخيص، والنتيجة إن حالة النظام دايمًا مطابقة لقاعدة البيانات.
  Future<void> rescheduleAll(List<Appointment> appointments) async {
    await _plugin.cancelAll();

    final now = DateTime.now();
    final due =
        appointments
            .where((a) => !a.done)
            // تذكير وقته عدّى مبينفعش يتجدول. الميعاد نفسه ممكن يكون لسه جاي
            // (لو اتسجّل قبله بشوية) وده مقبول — بيظهر في القايمة من غير رنّة.
            .where((a) => a.remindAt.isAfter(now))
            .toList()
          ..sort((a, b) => a.remindAt.compareTo(b.remindAt));

    for (final appointment in due.take(AppConfig.maxScheduledReminders)) {
      await _schedule(appointment);
    }

    if (due.length > AppConfig.maxScheduledReminders) {
      debugPrint(
        'اتجدول ${AppConfig.maxScheduledReminders} من ${due.length} تذكير — '
        'الباقي هيتجدول لما الأقرب يعدّي.',
      );
    }
  }

  Future<void> _schedule(Appointment appointment) async {
    await _plugin.zonedSchedule(
      id: _notificationId(appointment.id),
      title: appointment.title,
      body: _body(appointment),
      scheduledDate: tz.TZDateTime.from(appointment.remindAt, tz.local),
      payload: appointment.id,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: _repeatComponent(appointment.repeat),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          AppConfig.reminderChannelId,
          AppConfig.reminderChannelName,
          channelDescription: AppConfig.reminderChannelDescription,
          importance: Importance.max,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          // بيخلّي الإشعار يعدّي وضع التركيز. مستوى critical (اللي بيعدّي
          // الصامت) محتاج موافقة خاصة من أبل ومش متاحة لتطبيق زي ده.
          interruptionLevel: InterruptionLevel.timeSensitive,
        ),
      ),
    );
  }

  String _body(Appointment appointment) {
    final minutes = appointment.remindBeforeMinutes;
    if (minutes <= 0) return 'موعدك الحين.';
    if (minutes < 60) return 'باقي $minutes دقيقة على موعدك.';
    if (minutes % 60 == 0) {
      final hours = minutes ~/ 60;
      if (hours == 1) return 'باقي ساعة على موعدك.';
      if (hours == 2) return 'باقي ساعتين على موعدك.';
      if (hours < 24) return 'باقي $hours ساعات على موعدك.';
      final days = hours ~/ 24;
      if (days == 1) return 'موعدك بكرة.';
      return 'باقي $days أيام على موعدك.';
    }
    return 'موعدك قرّب.';
  }

  /// التكرار في flutter_local_notifications بيتعمل بمطابقة أجزاء التاريخ.
  /// الشهري والسنوي مش مدعومين بالمطابقة، فبيتعادوا إعادة جدولة لما التذكير
  /// يرنّ (شوف [rescheduleAll] اللي بيتنده عند فتح التطبيق).
  DateTimeComponents? _repeatComponent(Repeat repeat) => switch (repeat) {
    Repeat.none => null,
    Repeat.daily => DateTimeComponents.time,
    Repeat.weekly => DateTimeComponents.dayOfWeekAndTime,
    Repeat.monthly => DateTimeComponents.dayOfMonthAndTime,
    Repeat.yearly => DateTimeComponents.dateAndTime,
  };

  /// الـid عندنا نص والـAPI عايز int موجب في 32 بت.
  int _notificationId(String appointmentId) =>
      appointmentId.hashCode & 0x7fffffff;

  Future<void> cancel(String appointmentId) =>
      _plugin.cancel(id: _notificationId(appointmentId));
}
