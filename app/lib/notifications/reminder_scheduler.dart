import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
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

  /// معرّفات أزرار الإشعار. بتوصل في NotificationResponse.actionId.
  static const String actionDone = 'done';
  static const String actionSnooze = 'snooze';

  /// كام دقيقة يتأجّل التذكير لما يضغط «أجّل».
  static const Duration snoozeBy = Duration(minutes: 15);

  /// معرّفات إشعارات ملخص الصبح بعيدة عن نطاق التذكيرات العادية.
  static const int _summaryIdBase = 1900000000;

  /// ساعة ملخص الصبح.
  static const int _summaryHour = 6;
  static const int _summaryMinute = 45;

  /// بيتنده لما المستخدم يضغط على التذكير أو أحد أزراره.
  /// (معرّف الموعد، معرّف الزرار أو null للضغط على جسم الإشعار).
  void Function(String appointmentId, String? actionId)? onAction;

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  IOSFlutterLocalNotificationsPlugin? get _ios => _plugin
      .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin
      >();

  /// تتنده مرة واحدة في main() قبل runApp.
  Future<void> initialize({void Function(NotificationResponse)? onTap}) async {
    if (_ready) return;

    tzdata.initializeTimeZones();
    // zonedSchedule بتحسب على المنطقة المحلية، والافتراضي UTC. من غير السطر
    // ده كل التذكيرات هتزحف بفرق التوقيت.
    final zone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(zone.identifier));

    await _plugin.initialize(
      // مش const لأن فئات آيفون بتتبني وقت التشغيل.
      settings: InitializationSettings(
        android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          // الأذونات بنطلبها صراحة في شاشة الإعداد عشان نقدر نشرح للمستخدم
          // قبل ما النظام يسأله.
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
          // آيفون بيعرّف أزرار الإشعار بفئات وقت التهيئة، مش مع كل إشعار.
          notificationCategories: [
            DarwinNotificationCategory(
              'sekerter_reminder',
              actions: [
                DarwinNotificationAction.plain(actionDone, 'تم'),
                DarwinNotificationAction.plain(actionSnooze, 'أجّل ربع ساعة'),
              ],
            ),
          ],
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        onTap?.call(response);
        onAction?.call(payload, response.actionId);
      },
    );

    await _createAndroidChannel();
    _ready = true;
  }

  /// لو التطبيق اتفتح من ضغطة على إشعار وهو كان مقفول خالص، الضغطة دي
  /// ما بتوصلش للـcallback العادي — بتتسلّم هنا مرة واحدة عند التشغيل.
  Future<void> deliverLaunchAction() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    final response = details?.notificationResponse;
    final payload = response?.payload;
    if (details?.didNotificationLaunchApp != true ||
        payload == null ||
        payload.isEmpty) {
      return;
    }
    onAction?.call(payload, response?.actionId);
  }

  Future<void> _createAndroidChannel() async {
    // القناة القديمة كانت بصوت الإشعارات العادي — بيتكتم مع الصامت وعدم
    // الإزعاج. إعدادات القناة بتتجمّد بعد الإنشاء، فالتغيير محتاج قناة
    // جديدة ومسح القديمة عشان ما يظهرش اتنين في إعدادات النظام.
    await _android?.deleteNotificationChannel(
      channelId: AppConfig.legacyReminderChannelId,
    );
    await _android?.createNotificationChannel(
      const AndroidNotificationChannel(
        AppConfig.reminderChannelId,
        AppConfig.reminderChannelName,
        description: AppConfig.reminderChannelDescription,
        importance: Importance.max,
        // الصوت يطلع من قناة المنبّه: بيرنّ حتى والجوال صامت أو على وضع
        // عدم الإزعاج (المنبّهات مستثناة منه افتراضيًا). ده وعد التطبيق
        // الأساسي: «التنبيه يوصلك حتى والجوال صامت».
        audioAttributesUsage: AudioAttributesUsage.alarm,
      ),
    );
  }

  /// يطلب أذونات الإشعارات. بيرجّع false لو المستخدم رفض.
  ///
  /// لازم تتنده من أول شاشة، مش من زرار في الإعدادات: أندرويد ١٣+ بيمنع
  /// الإشعارات افتراضيًا لحد ما الإذن يتطلب، وأول مستخدم حقيقي ثبّت
  /// التطبيق وسجّل موعد والتذكير ما رنّ — لأن محدش طلب الإذن أصلًا.
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
    // الجدولة الدقيقة إذن منفصل من أندرويد ١٢. طلبه بيفتح صفحة إعدادات
    // النظام، فما نزعجش المستخدم بيها لو هي أصلًا متاحة.
    if (!await exactAlarmAllowed()) {
      await _android?.requestExactAlarmsPermission();
    }
    return granted;
  }

  /// هل النظام سامح بجدولة دقيقة؟ من غيرها التذكير بيتأخر أو ما يرنّش —
  /// بعض الأجهزة (شاومي وسامسونج خصوصًا) متشددة في ده.
  Future<bool> exactAlarmAllowed() async {
    if (!Platform.isAndroid) return true;
    return await _android?.canScheduleExactNotifications() ?? false;
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

    // الجدولة الدقيقة إذن منفصل من أندرويد ١٢، وبعض الأجهزة بتسحبه من ورا
    // المستخدم. الحزمة **بترمي استثناء** لو اتطلبت جدولة دقيقة من غيره —
    // وقبل التصليح ده كان بيوقّع rescheduleAll كلها بعد cancelAll: كل
    // التذكيرات تتمسح ولا واحد يتجدول، في صمت كامل. تذكير بيتأخر دقايق
    // (غير دقيق) أهون بكتير من تذكير مش موجود أصلًا.
    final exact = await exactAlarmAllowed();
    final mode = exact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;

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
      await _schedule(appointment, mode);
    }

    if (due.length > AppConfig.maxScheduledReminders) {
      debugPrint(
        'اتجدول ${AppConfig.maxScheduledReminders} من ${due.length} تذكير — '
        'الباقي هيتجدول لما الأقرب يعدّي.',
      );
    }

    await _scheduleMorningSummaries(appointments, now, mode);
  }

  /// ملخص الصبح: أي يوم في الأسبوع الجاي فيه مواعيد، بياخد إشعار الساعة
  /// ٦:٤٥ الصبح بعددها وأساميها — عشان اليوم يبدأ والجدول في دماغه.
  ///
  /// بيتجدول لأيام فيها مواعيد بس، فأقصى إضافة ٧ إشعارات فوق حد الـ٥٠ —
  /// لسه تحت حد الآيفون (٦٤).
  Future<void> _scheduleMorningSummaries(
    List<Appointment> appointments,
    DateTime now,
    AndroidScheduleMode mode,
  ) async {
    // الحساب كله بمنطقة الجدولة (tz.local) مش بتوقيت نظام التشغيل — على
    // الجهاز هما نفس الشي، لكن الخلط بينهم يزحّف الساعة لو اختلفوا.
    final localNow = tz.TZDateTime.from(now, tz.local);

    for (var offset = 0; offset < 7; offset++) {
      final fireAt = tz.TZDateTime(
        tz.local,
        localNow.year,
        localNow.month,
        localNow.day + offset,
        _summaryHour,
        _summaryMinute,
      );
      if (!fireAt.isAfter(localNow)) continue;

      final todays = appointments.where((a) => !a.done).where((a) {
        final atLocal = tz.TZDateTime.from(a.at, tz.local);
        return atLocal.year == fireAt.year &&
            atLocal.month == fireAt.month &&
            atLocal.day == fireAt.day;
      }).toList()..sort((a, b) => a.at.compareTo(b.at));
      if (todays.isEmpty) continue;

      final names = todays.take(3).map((a) => a.title).join('، ');
      final extra = todays.length > 3 ? ' وغيرهم' : '';

      await _withFallback(
        mode,
        (m) => _plugin.zonedSchedule(
          id: _summaryIdBase + offset,
          title: todays.length == 1
              ? 'عندك موعد اليوم'
              : 'عندك ${todays.length} مواعيد اليوم',
          body: '$names$extra',
          scheduledDate: fireAt,
          androidScheduleMode: m,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              AppConfig.reminderChannelId,
              AppConfig.reminderChannelName,
              channelDescription: AppConfig.reminderChannelDescription,
              importance: Importance.defaultImportance,
              priority: Priority.defaultPriority,
            ),
            iOS: DarwinNotificationDetails(
              presentAlert: true,
              presentSound: false,
            ),
          ),
        ),
      );
    }
  }

  Future<void> _schedule(
    Appointment appointment, [
    AndroidScheduleMode mode = AndroidScheduleMode.exactAllowWhileIdle,
  ]) => _withFallback(mode, (m) => _scheduleWith(appointment, m));

  /// يجدول ويتصرف في رفض «الجدولة الدقيقة» بدل ما يرمي.
  ///
  /// فحص الإذن ممكن يقول إن الدقيقة متاحة والنظام يرفضها لحظة التنفيذ
  /// (بيحصل على أجهزة شاومي وأمثالها) — نعيد بغير دقيقة بدل ما نضيّع
  /// التذكير. وأي عطل تاني في إشعار واحد بيتسجّل ويعدّي عشان ما يطيّحش
  /// باقي التذكيرات — قبل كده كان بيوقّع rescheduleAll بعد cancelAll:
  /// كل التذكيرات تتمسح ولا واحد يتجدول، في صمت كامل.
  Future<void> _withFallback(
    AndroidScheduleMode mode,
    Future<void> Function(AndroidScheduleMode mode) schedule,
  ) async {
    try {
      await schedule(mode);
    } on PlatformException catch (e) {
      if (e.code == 'exact_alarms_not_permitted' &&
          mode == AndroidScheduleMode.exactAllowWhileIdle) {
        await _withFallback(
          AndroidScheduleMode.inexactAllowWhileIdle,
          schedule,
        );
        return;
      }
      debugPrint('تعذّرت جدولة إشعار: ${e.code}');
    }
  }

  Future<void> _scheduleWith(
    Appointment appointment,
    AndroidScheduleMode mode,
  ) async {
    await _plugin.zonedSchedule(
      id: _notificationId(appointment.id),
      title: appointment.title,
      body: _body(appointment),
      scheduledDate: tz.TZDateTime.from(appointment.remindAt, tz.local),
      payload: appointment.id,
      androidScheduleMode: mode,
      matchDateTimeComponents: _repeatComponent(appointment.repeat),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          AppConfig.reminderChannelId,
          AppConfig.reminderChannelName,
          channelDescription: AppConfig.reminderChannelDescription,
          importance: Importance.max,
          priority: Priority.high,
          // فئة منبّه + ملء الشاشة + صوت المنبّه: التذكير يبان ويرنّ زي
          // منبّه حقيقي حتى والشاشة مقفولة أو الجوال صامت.
          category: AndroidNotificationCategory.alarm,
          fullScreenIntent: true,
          audioAttributesUsage: AudioAttributesUsage.alarm,
          // «تم» و«أجّل» من الإشعار نفسه — من غير ما يفتح التطبيق.
          // showsUserInterface بيوصّل الضغطة للتطبيق وهو صاحي، وده أضمن
          // طريق من معالج الخلفية اللي بيتقتل على أجهزة كتير.
          actions: [
            AndroidNotificationAction(
              actionDone,
              'تم',
              showsUserInterface: true,
            ),
            AndroidNotificationAction(
              actionSnooze,
              'أجّل ربع ساعة',
              showsUserInterface: true,
            ),
          ],
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          // بيخلّي الإشعار يعدّي وضع التركيز. مستوى critical (اللي بيعدّي
          // الصامت) محتاج موافقة خاصة من أبل ومش متاحة لتطبيق زي ده.
          interruptionLevel: InterruptionLevel.timeSensitive,
          // الفئة اللي فيها أزرار «تم» و«أجّل» — معرّفة في initialize.
          categoryIdentifier: 'sekerter_reminder',
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
