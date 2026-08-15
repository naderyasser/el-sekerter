import 'package:flutter/foundation.dart';

import 'appointment.dart';

/// أمر جاي من السيرفر ينفّذه التطبيق محليًا.
///
/// الأنواع مطابقة لـ ACTION_TYPES في backend/secretary/tools.py.
enum ActionType {
  create,
  update,
  delete,
  complete,
  unknown;

  static ActionType parse(String? value) => ActionType.values.firstWhere(
    (a) => a.name == value,
    // سيرفر أحدث ممكن يبعت نوع التطبيق ميعرفهوش — بنتجاهله بدل ما نقع.
    orElse: () => ActionType.unknown,
  );
}

@immutable
class ServerAction {
  const ServerAction({
    required this.type,
    this.id,
    this.title,
    this.at,
    this.remindBeforeMinutes,
    this.repeat,
    this.notes,
  });

  final ActionType type;

  /// معرّف الميعاد. موجود في update/delete/complete، وفاضي في create.
  final String? id;

  /// في التعديل، null معناها «سيبه زي ما هو».
  final String? title;
  final DateTime? at;
  final int? remindBeforeMinutes;
  final Repeat? repeat;
  final String? notes;

  factory ServerAction.fromJson(Map<String, Object?> json) {
    final rawAt = json['at'] as String?;
    return ServerAction(
      type: ActionType.parse(json['type'] as String?),
      id: json['id'] as String?,
      title: json['title'] as String?,
      // السيرفر بيتحقق من الصيغة قبل ما يبعتها، بس بنتحوّط هنا برضه: تاريخ
      // بايظ يفضّل يتتجاهل على إنه يوقّع التطبيق.
      at: rawAt == null ? null : DateTime.tryParse(rawAt)?.toLocal(),
      remindBeforeMinutes: json['remind_before_minutes'] as int?,
      repeat: json['repeat'] == null
          ? null
          : Repeat.parse(json['repeat'] as String?),
      notes: json['notes'] as String?,
    );
  }

  /// هل الأمر ده كامل بحيث ينفّذ؟
  bool get isApplicable => switch (type) {
    ActionType.create => title != null && at != null,
    ActionType.update => id != null,
    ActionType.delete || ActionType.complete => id != null,
    ActionType.unknown => false,
  };
}

/// رد السيرفر الكامل.
@immutable
class ChatResponse {
  const ChatResponse({required this.reply, required this.actions});

  final String reply;
  final List<ServerAction> actions;

  factory ChatResponse.fromJson(Map<String, Object?> json) => ChatResponse(
    reply: (json['reply'] as String?)?.trim() ?? '',
    actions: ((json['actions'] as List?) ?? const [])
        .whereType<Map>()
        .map((a) => ServerAction.fromJson(a.cast<String, Object?>()))
        .where((a) => a.isApplicable)
        .toList(growable: false),
  );
}
