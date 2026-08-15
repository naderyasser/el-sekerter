import 'package:flutter/foundation.dart';

enum Sender { user, secretary }

@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.sender,
    required this.text,
    required this.at,
    this.failed = false,
  });

  final int id;
  final Sender sender;
  final String text;
  final DateTime at;

  /// رسالة المستخدم اللي السيرفر مردش عليها. بتفضل في الشات بعلامة إعادة
  /// المحاولة بدل ما تختفي.
  final bool failed;

  ChatMessage copyWith({String? text, bool? failed}) => ChatMessage(
    id: id,
    sender: sender,
    text: text ?? this.text,
    at: at,
    failed: failed ?? this.failed,
  );

  Map<String, Object?> toRow() => {
    if (id > 0) 'id': id,
    'sender': sender.name,
    'text': text,
    'at_utc': at.toUtc().toIso8601String(),
    'failed': failed ? 1 : 0,
  };

  factory ChatMessage.fromRow(Map<String, Object?> row) => ChatMessage(
    id: row['id']! as int,
    sender: row['sender'] == 'user' ? Sender.user : Sender.secretary,
    text: row['text']! as String,
    at: DateTime.parse(row['at_utc']! as String).toLocal(),
    failed: (row['failed'] as int? ?? 0) == 1,
  );

  /// الشكل اللي السيرفر بيستقبله في `history` — لازم يطابق
  /// HistoryMessageSerializer في backend/secretary/serializers.py.
  Map<String, Object?> toApi() => {
    'role': sender == Sender.user ? 'user' : 'assistant',
    'content': text,
  };
}
