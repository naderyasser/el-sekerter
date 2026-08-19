import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/arabic.dart';
import '../../models/appointment.dart';
import '../../state/appointments_controller.dart';
import '../../state/providers.dart';

class AppointmentsScreen extends ConsumerWidget {
  const AppointmentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appointments = ref.watch(appointmentsProvider);
    final upcoming = ref.watch(upcomingAppointmentsProvider);
    final past = ref.watch(pastAppointmentsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('مواعيدي')),
      body: appointments.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('ما قدرت أقرأ المواعيد.\n$e')),
        data: (_) {
          if (upcoming.isEmpty && past.isEmpty) return const _EmptyState();

          final unscheduled = ref.watch(schedulerProvider).unscheduledCount;

          return RefreshIndicator(
            onRefresh: () => ref.read(appointmentsProvider.notifier).refresh(),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                if (unscheduled > 0) _TooManyBanner(count: unscheduled),
                if (upcoming.isNotEmpty) ...[
                  const _SectionHeader('الجاية'),
                  for (final appointment in upcoming)
                    _AppointmentTile(appointment: appointment),
                ],
                if (past.isNotEmpty) ...[
                  const _SectionHeader('اللي فات'),
                  for (final appointment in past)
                    _AppointmentTile(appointment: appointment, dimmed: true),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// تحذير لما عدد التنبيهات يعدّي سقف النظام.
///
/// الحالة دي كانت بتعدّي في صمت: الموعد يتحفظ ويتعرض في القايمة عادي
/// و**ما يرنّش أبدًا**. صاحب العمل يشوفه قدامه فيطمّن — وده أسوأ فشل ممكن.
class _TooManyBanner extends StatelessWidget {
  const _TooManyBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.notifications_paused_outlined,
            color: scheme.onErrorContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'مواعيدك أكثر من اللي النظام يقدر ينبّه عليه مرة وحدة، '
              'فـ$count تنبيه من الأبعد ما اتجدولش. بيتجدولوا تلقائيًا '
              'كل ما القريب يعدّي — بس افتح التطبيق بين فترة وفترة.',
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
    child: Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _AppointmentTile extends ConsumerWidget {
  const _AppointmentTile({required this.appointment, this.dimmed = false});

  final Appointment appointment;
  final bool dimmed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final controller = ref.read(appointmentsProvider.notifier);

    return Dismissible(
      key: ValueKey(appointment.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: scheme.errorContainer,
        alignment: AlignmentDirectional.centerEnd,
        padding: const EdgeInsetsDirectional.only(end: 24),
        child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
      ),
      onDismissed: (_) {
        controller.delete(appointment);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('انحذف «${appointment.title}»'),
              action: SnackBarAction(
                label: 'تراجع',
                onPressed: () => controller.restore(appointment),
              ),
            ),
          );
      },
      child: ListTile(
        leading: IconButton(
          tooltip: appointment.done ? 'رجّعه غير منجز' : 'علّمه منجز',
          icon: Icon(
            appointment.done
                ? Icons.check_circle
                : Icons.radio_button_unchecked,
            color: appointment.done ? scheme.primary : scheme.outline,
          ),
          onPressed: () => controller.toggleDone(appointment),
        ),
        title: Text(
          appointment.title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            decoration: appointment.done ? TextDecoration.lineThrough : null,
            color: dimmed ? scheme.onSurfaceVariant : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(ArabicDate.dayAndTime(appointment.at)),
            if (appointment.notes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  appointment.notes,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              ArabicDate.relative(appointment.at),
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            if (appointment.repeat != Repeat.none)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.repeat, size: 12, color: scheme.outline),
                    const SizedBox(width: 3),
                    Text(
                      appointment.repeat.arabicLabel,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
          ],
        ),
        onTap: () => _showDetails(context, appointment),
      ),
    );
  }

  void _showDetails(BuildContext context, Appointment appointment) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              appointment.title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            _DetailRow(
              icon: Icons.event,
              text: ArabicDate.fullDate(appointment.at),
            ),
            _DetailRow(
              icon: Icons.schedule,
              text: ArabicDate.time(appointment.at),
            ),
            _DetailRow(
              icon: Icons.notifications_outlined,
              text: ArabicDate.reminderLead(appointment.remindBeforeMinutes),
            ),
            if (appointment.repeat != Repeat.none)
              _DetailRow(
                icon: Icons.repeat,
                text: appointment.repeat.arabicLabel,
              ),
            if (appointment.notes.isNotEmpty)
              _DetailRow(icon: Icons.notes, text: appointment.notes),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.event_available_outlined,
              size: 56,
              color: scheme.primary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              'ما فيه مواعيد بعد',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'روح للسكرتير وقل له أول موعد.',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
