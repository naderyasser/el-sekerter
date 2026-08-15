import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';

/// إعداد الاتصال بالسيرفر + أذونات الإشعارات.
///
/// نفس الشاشة بتتعرض كخطوة إعداد أول مرة، وكصفحة إعدادات بعد كده.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key, this.isSetup = false});

  /// أول تشغيل: مفيش زرار رجوع، والحفظ بيدخّل على التطبيق.
  final bool isSetup;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _url = TextEditingController();
  final _token = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _obscureToken = true;
  bool? _notificationsGranted;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final settings = ref.read(settingsStoreProvider);
    _url.text = await settings.apiBaseUrl();
    _token.text = await settings.apiToken() ?? '';
    final granted = await ref.read(schedulerProvider).hasPermission();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _notificationsGranted = granted;
    });
  }

  Future<void> _requestNotifications() async {
    final granted = await ref.read(schedulerProvider).requestPermissions();
    if (!mounted) return;
    setState(() => _notificationsGranted = granted);
    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'الإشعارات مرفوضة. بدونها ما راح ترنّ التذكيرات — فعّلها من '
            'إعدادات الجهاز.',
          ),
        ),
      );
    }
  }

  Future<void> _save() async {
    final url = _url.text.trim();
    final token = _token.text.trim();

    if (url.isEmpty || token.isEmpty) {
      _snack('املا عنوان السيرفر والتوكن.');
      return;
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      _snack('عنوان السيرفر لازم يبدأ بـ http:// أو https://');
      return;
    }

    setState(() => _saving = true);

    // نتأكد إن العنوان والتوكن شغّالين قبل ما نحفظهم — أحسن من إن المستخدم
    // يكتشف الغلط أول ما يرسل رسالة.
    final reachable = await ref.read(apiClientProvider).ping(url, token);
    if (!mounted) return;

    if (!reachable) {
      setState(() => _saving = false);
      _snack('ما قدرت أوصل للسيرفر على العنوان هذا. راجعه.');
      return;
    }

    final settings = ref.read(settingsStoreProvider);
    await settings.setApiBaseUrl(url);
    await settings.setApiToken(token);
    ref.invalidate(isConfiguredProvider);

    if (!mounted) return;
    setState(() => _saving = false);

    if (widget.isSetup) return; // الشاشة الرئيسية بتظهر لوحدها
    _snack('انحفظ.');
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isSetup ? 'الإعداد' : 'الإعدادات'),
        automaticallyImplyLeading: !widget.isSetup,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (widget.isSetup) ...[
            Text(
              'وصّل التطبيق بسيرفرك',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'تلقى العنوان والتوكن في ملف backend/.env على سيرفرك.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
          ],
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(
              labelText: 'عنوان السيرفر',
              hintText: 'https://sekerter.example.com',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _token,
            obscureText: _obscureToken,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText: 'التوكن',
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureToken ? Icons.visibility : Icons.visibility_off,
                ),
                onPressed: () => setState(() => _obscureToken = !_obscureToken),
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(widget.isSetup ? 'تحقّق وابدأ' : 'احفظ'),
          ),
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              _notificationsGranted ?? false
                  ? Icons.notifications_active
                  : Icons.notifications_off_outlined,
              color: _notificationsGranted ?? false
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.error,
            ),
            title: const Text('إذن الإشعارات'),
            subtitle: Text(
              _notificationsGranted ?? false
                  ? 'مسموح — التذكيرات بترنّ.'
                  : 'مرفوض — التذكيرات ما راح ترنّ.',
            ),
            trailing: (_notificationsGranted ?? false)
                ? null
                : TextButton(
                    onPressed: _requestNotifications,
                    child: const Text('اسمح'),
                  ),
          ),
        ],
      ),
    );
  }
}
