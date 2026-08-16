import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../notifications/reminder_scheduler.dart';
import '../state/appointments_controller.dart';
import '../state/providers.dart';
import 'appointments/appointments_screen.dart';
import 'chat/chat_screen.dart';
import 'permission_gate.dart';
import 'settings/settings_screen.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with WidgetsBindingObserver {
  int _index = 0;

  static const _screens = [
    ChatScreen(),
    AppointmentsScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // أزرار الإشعار: «تم» يقفل الموعد و«أجّل» يأخّر الرنّة ربع ساعة.
    final scheduler = ref.read(schedulerProvider);
    scheduler.onAction = _handleNotificationAction;
    // ولو التطبيق اتفتح أصلًا من ضغطة على إشعار وهو مقفول.
    scheduler.deliverLaunchAction();
  }

  Future<void> _handleNotificationAction(
    String appointmentId,
    String? actionId,
  ) async {
    final store = ref.read(appointmentStoreProvider);
    final appointment = await store.byId(appointmentId);
    if (appointment == null) return;

    switch (actionId) {
      case ReminderScheduler.actionDone:
        await store.update(appointment.copyWith(done: true));
      case ReminderScheduler.actionSnooze:
        await store.update(
          appointment.copyWith(
            snoozeUntil: DateTime.now().add(ReminderScheduler.snoozeBy),
          ),
        );
      default:
        // ضغطة على جسم الإشعار — التطبيق فتح على شاشة المواعيد وكفاية.
        if (mounted) setState(() => _index = 1);
    }

    // إعادة الجدولة عشان «أجّل» ياخد رنّته الجديدة و«تم» يلغي بتاعته.
    await ref.read(appointmentsProvider.notifier).refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // إعادة الجدولة عند كل رجوع للتطبيق. ده اللي بيغطّي حد الـ٦٤ إشعار على
    // آيفون (المواعيد اللي كانت بره النافذة بتدخل لما الأقرب يعدّي)،
    // والتذكيرات اللي رنّت خلاص، وتغيّر المنطقة الزمنية بعد سفر.
    if (state == AppLifecycleState.resumed) {
      ref.read(appointmentsProvider.notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final upcoming = ref.watch(upcomingAppointmentsProvider).length;

    return Scaffold(
      body: PermissionGate(
        child: IndexedStack(index: _index, children: _screens),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'السكرتير',
          ),
          NavigationDestination(
            icon: Badge.count(
              count: upcoming,
              isLabelVisible: upcoming > 0,
              child: const Icon(Icons.event_outlined),
            ),
            selectedIcon: const Icon(Icons.event),
            label: 'مواعيدي',
          ),
          const NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'الإعدادات',
          ),
        ],
      ),
    );
  }
}
