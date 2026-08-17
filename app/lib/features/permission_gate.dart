import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../state/providers.dart';

/// طلب أذونات الإشعارات أول ما التطبيق يفتح، وتحذير دايم لو اترفضت.
///
/// الإذن كان بيتطلب بس من زرار جوّه شاشة الإعدادات — وأول مستخدم حقيقي ما
/// دخلهاش: ثبّت التطبيق، سجّل موعد، والتذكير ما رنّ. أندرويد ١٣+ بيمنع
/// الإشعارات افتراضيًا لحد ما الإذن يتطلب، والرفض ده صامت تمامًا.
///
/// القاعدة: التطبيق اللي شغلته الأساسي إنه يرنّ لازم يتأكد إنه يقدر يرنّ
/// قبل ما يوهم المستخدم إن كل شي تمام.
class PermissionGate extends ConsumerStatefulWidget {
  const PermissionGate({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<PermissionGate> createState() => _PermissionGateState();
}

class _PermissionGateState extends ConsumerState<PermissionGate>
    with WidgetsBindingObserver {
  bool _notificationsGranted = true;
  bool _exactAllowed = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // بعد أول إطار عشان حوار النظام ما يسبقش رسم الشاشة.
    WidgetsBinding.instance.addPostFrameCallback((_) => _request());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // المستخدم ممكن يروح إعدادات الجهاز يفعّل الإذن ويرجع — التحذير لازم
    // يختفي من غير ما يعيد فتح التطبيق.
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _request() async {
    final scheduler = ref.read(schedulerProvider);
    await scheduler.requestPermissions();
    // المستخدم ممكن يقفل التطبيق والطلب لسه شغال — ref بعد dispose بترمي.
    if (!mounted) return;
    await _check();
  }

  Future<void> _check() async {
    if (!mounted) return;
    final scheduler = ref.read(schedulerProvider);
    final granted = await scheduler.hasPermission();
    final exact = await scheduler.exactAlarmAllowed();
    if (!mounted) return;
    setState(() {
      _notificationsGranted = granted;
      _exactAllowed = exact;
    });
  }

  Future<void> _fix() async {
    final scheduler = ref.read(schedulerProvider);
    if (!_notificationsGranted) {
      final granted = await scheduler.requestPermissions();
      // الرفض الدائم: حوار النظام ما بيظهرش تاني، فنفتح إعدادات التطبيق.
      if (!granted) await openAppSettings();
    } else if (!_exactAllowed) {
      await scheduler.requestPermissions();
    }
    await _check();
  }

  @override
  Widget build(BuildContext context) {
    final String? warning;
    if (!_notificationsGranted) {
      warning = 'الإشعارات مقفولة — التذكيرات ما راح ترنّ. اضغط للتفعيل';
    } else if (!_exactAllowed) {
      warning =
          'التنبيه في الوقت المضبوط مقفول — التذكير ممكن يتأخر. '
          'اضغط للتفعيل';
    } else {
      warning = null;
    }

    return Column(
      children: [
        if (warning != null)
          Material(
            color: Theme.of(context).colorScheme.errorContainer,
            child: SafeArea(
              bottom: false,
              child: InkWell(
                onTap: _fix,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.notifications_off_outlined,
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          warning,
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onErrorContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        Expanded(child: widget.child),
      ],
    );
  }
}
