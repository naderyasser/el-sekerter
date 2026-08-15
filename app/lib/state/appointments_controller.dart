import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/appointment.dart';
import 'providers.dart';

/// المواعيد المحفوظة + إعادة الجدولة بعد أي تغيير.
///
/// كل تعديل بيعدي من هنا عشان الإشعارات المجدولة تفضل مطابقة لقاعدة البيانات؛
/// ميعاد بيتغيّر من غير إعادة جدولة معناه تذكير بيرنّ في وقت غلط.
class AppointmentsController extends AsyncNotifier<List<Appointment>> {
  @override
  Future<List<Appointment>> build() => _loadAndReschedule();

  Future<List<Appointment>> _loadAndReschedule() async {
    final appointments = await ref.read(appointmentStoreProvider).all();
    await ref.read(schedulerProvider).rescheduleAll(appointments);
    return appointments;
  }

  Future<void> refresh() async {
    state = AsyncValue.data(await _loadAndReschedule());
  }

  Future<void> toggleDone(Appointment appointment) async {
    await ref
        .read(appointmentStoreProvider)
        .update(appointment.copyWith(done: !appointment.done));
    await refresh();
  }

  Future<void> delete(Appointment appointment) async {
    await ref.read(appointmentStoreProvider).delete(appointment.id);
    await refresh();
  }

  /// بيرجّع الميعاد اللي اتمسح عشان زرار «تراجع» يقدر يرجّعه.
  Future<void> restore(Appointment appointment) async {
    await ref.read(appointmentStoreProvider).insert(appointment);
    await refresh();
  }
}

final appointmentsProvider =
    AsyncNotifierProvider<AppointmentsController, List<Appointment>>(
      AppointmentsController.new,
    );

/// المواعيد الجاية بس — دي اللي بتظهر في التبويب الرئيسي.
final upcomingAppointmentsProvider = Provider<List<Appointment>>((ref) {
  final all = ref.watch(appointmentsProvider).value ?? const [];
  final now = DateTime.now();
  return all.where((a) => !a.done && a.at.isAfter(now)).toList(growable: false);
});

/// اللي عدّى أو خلص — بيتعرض في قسم منفصل تحت.
final pastAppointmentsProvider = Provider<List<Appointment>>((ref) {
  final all = ref.watch(appointmentsProvider).value ?? const [];
  final now = DateTime.now();
  return all.where((a) => a.done || !a.at.isAfter(now)).toList(growable: false)
    ..sort((a, b) => b.at.compareTo(a.at));
});
