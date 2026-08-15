import 'package:sqflite/sqflite.dart';

import '../models/chat_message.dart';

/// أرشيف الشات المحلي.
class ChatStore {
  ChatStore(this._db);

  final Database _db;

  /// آخر [limit] رسالة بترتيب زمني تصاعدي (الأقدم الأول) عشان تتعرض على طول.
  Future<List<ChatMessage>> recent({int limit = 200}) async {
    final rows = await _db.query(
      'chat_messages',
      orderBy: 'id DESC',
      limit: limit,
    );
    return rows.reversed.map(ChatMessage.fromRow).toList(growable: false);
  }

  Future<ChatMessage> add(ChatMessage message) async {
    final id = await _db.insert('chat_messages', message.toRow());
    return ChatMessage(
      id: id,
      sender: message.sender,
      text: message.text,
      at: message.at,
      failed: message.failed,
    );
  }

  Future<void> setFailed(int id, {required bool failed}) async {
    await _db.update(
      'chat_messages',
      {'failed': failed ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> clear() => _db.delete('chat_messages');
}
