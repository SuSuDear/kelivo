import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../../utils/app_directories.dart';
import '../../models/chat_message.dart';
import '../../models/conversation.dart';

class SqliteChatStorage {
  SqliteChatStorage._(this.database)
      : conversations = SqliteJsonStore<Conversation>(
          database,
          'conversations',
          (value) => value.toJson(),
          (value) => Conversation.fromJson(
            Map<String, dynamic>.from(value as Map),
          ),
        ),
        messages = SqliteJsonStore<ChatMessage>(
          database,
          'messages',
          (value) => value.toJson(),
          (value) => ChatMessage.fromJson(
            Map<String, dynamic>.from(value as Map),
          ),
        ),
        toolEvents = SqliteJsonStore<dynamic>(
          database,
          'tool_events',
          (value) => value,
          (value) => value,
        );

  final Database database;
  final SqliteJsonStore<Conversation> conversations;
  final SqliteJsonStore<ChatMessage> messages;
  final SqliteJsonStore<dynamic> toolEvents;

  static Future<SqliteChatStorage> open() async {
    final appDataDir = await AppDirectories.getAppDataDirectory();
    final database = await openDatabase(
      p.join(appDataDir.path, 'chat.sqlite3'),
      version: 1,
      onCreate: (db, version) async {
        for (final table in const ['conversations', 'messages', 'tool_events']) {
          await db.execute(
            'CREATE TABLE $table (key TEXT PRIMARY KEY NOT NULL, payload TEXT NOT NULL)',
          );
        }
      },
    );
    final storage = SqliteChatStorage._(database);
    await Future.wait([
      storage.conversations.load(),
      storage.messages.load(),
      storage.toolEvents.load(),
    ]);
    return storage;
  }

  Future<void> putMessageAndConversation(
    ChatMessage message,
    Conversation conversation,
  ) async {
    await messages.flush(message.id);
    await conversations.flush(conversation.id);
    await database.transaction((txn) async {
      await messages.insertWith(txn, message.id, message);
      await conversations.insertWith(txn, conversation.id, conversation);
    });
    messages.markCommitted(message.id, message);
    conversations.markCommitted(conversation.id, conversation);
  }

  Future<void> deleteMessageAndUpdateConversation({
    required String messageId,
    required Conversation? conversation,
    required Iterable<String> toolEventKeys,
  }) async {
    await messages.flush(messageId);
    if (conversation != null) await conversations.flush(conversation.id);
    for (final key in toolEventKeys) {
      await toolEvents.flush(key);
    }
    await database.transaction((txn) async {
      if (conversation != null) {
        await conversations.insertWith(txn, conversation.id, conversation);
      }
      await txn.delete('messages', where: 'key = ?', whereArgs: [messageId]);
      for (final key in toolEventKeys) {
        await txn.delete('tool_events', where: 'key = ?', whereArgs: [key]);
      }
    });
    if (conversation != null) {
      conversations.markCommitted(conversation.id, conversation);
    }
    messages.removeCached(messageId);
    for (final key in toolEventKeys) {
      toolEvents.removeCached(key);
    }
  }

  Future<void> deleteConversation({
    required String conversationId,
    required Iterable<String> messageIds,
    required Iterable<String> toolEventKeys,
  }) async {
    await conversations.flush(conversationId);
    for (final id in messageIds) {
      await messages.flush(id);
    }
    for (final key in toolEventKeys) {
      await toolEvents.flush(key);
    }
    await database.transaction((txn) async {
      for (final key in toolEventKeys) {
        await txn.delete('tool_events', where: 'key = ?', whereArgs: [key]);
      }
      for (final id in messageIds) {
        await txn.delete('messages', where: 'key = ?', whereArgs: [id]);
      }
      await txn.delete(
        'conversations',
        where: 'key = ?',
        whereArgs: [conversationId],
      );
    });
    conversations.removeCached(conversationId);
    for (final id in messageIds) {
      messages.removeCached(id);
    }
    for (final key in toolEventKeys) {
      toolEvents.removeCached(key);
    }
  }

  Future<void> clearAll() async {
    await Future.wait([
      conversations.flushAll(),
      messages.flushAll(),
      toolEvents.flushAll(),
    ]);
    await database.transaction((txn) async {
      await txn.delete('tool_events');
      await txn.delete('messages');
      await txn.delete('conversations');
    });
    conversations.clearCached();
    messages.clearCached();
    toolEvents.clearCached();
    await compactIfEmpty();
  }

  Future<bool> isEmpty() async {
    final counts = await Future.wait<int>([
      _countRows('conversations'),
      _countRows('messages'),
      _countRows('tool_events'),
    ]);
    return counts.every((count) => count == 0);
  }

  Future<int> _countRows(String table) async {
    final rows = await database.rawQuery('SELECT COUNT(*) AS c FROM $table');
    final value = rows.first['c'];
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<void> compactIfEmpty() async {
    if (!await isEmpty()) return;
    try {
      await Future.wait([
        conversations.flushAll(),
        messages.flushAll(),
        toolEvents.flushAll(),
      ]);
      await database.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
      await database.execute('VACUUM');
      await database.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (error, stackTrace) {
      debugPrint('[SqliteChatStorage] compactIfEmpty failed: $error');
      debugPrint('$stackTrace');
    }
  }
}

class SqliteJsonStore<T> {
  SqliteJsonStore(this._database, this._table, this._encode, this._decode);

  final Database _database;
  final String _table;
  final dynamic Function(T value) _encode;
  final T Function(dynamic value) _decode;
  final Map<String, T> _cache = <String, T>{};
  final Map<String, T> _committed = <String, T>{};
  final Map<String, Future<void>> _writes = <String, Future<void>>{};

  Iterable<T> get values => _cache.values;
  Iterable<String> get keys => _cache.keys;
  bool get isEmpty => _cache.isEmpty;

  T? get(String key) => _cache[key];
  void putCached(String key, T value) => _cache[key] = value;
  void markCommitted(String key, T value) {
    _cache[key] = value;
    _committed[key] = value;
  }
  void removeCached(String key) {
    _cache.remove(key);
    _committed.remove(key);
  }
  void clearCached() {
    _cache.clear();
    _committed.clear();
  }
  bool containsKey(String key) => _cache.containsKey(key);

  Future<void> load() async {
    final rows = await _database.query(_table);
    final loaded = <String, T>{};
    for (final row in rows) {
      final key = row['key'] as String;
      final payload = jsonDecode(row['payload'] as String);
      loaded[key] = _decode(payload);
    }
    _cache
      ..clear()
      ..addAll(loaded);
    _committed
      ..clear()
      ..addAll(loaded);
  }

  Future<void> insertWith(
    DatabaseExecutor executor,
    String key,
    T value,
  ) async {
    await executor.insert(
      _table,
      {'key': key, 'payload': jsonEncode(_encode(value))},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> put(String key, T value) {
    final previous = _writes[key] ?? Future<void>.value();
    final next = previous.catchError((Object error, StackTrace stackTrace) {
      debugPrint('[SqliteJsonStore/$_table] previous write failed: $error');
    }).then((_) async {
      try {
        await insertWith(_database, key, value);
        markCommitted(key, value);
      } catch (error, stackTrace) {
        final committed = _committed[key];
        if (committed == null) {
          _cache.remove(key);
        } else {
          _cache[key] = committed;
        }
        debugPrint('[SqliteJsonStore/$_table] write failed: $error');
        debugPrint('$stackTrace');
        rethrow;
      }
    });
    _writes[key] = next;
    return next.whenComplete(() {
      if (identical(_writes[key], next)) _writes.remove(key);
    });
  }

  Future<void> flush(String key) async {
    await (_writes[key] ?? Future<void>.value());
  }

  Future<void> flushAll() async {
    await Future.wait(_writes.values.toList(), eagerError: true);
  }

  Future<void> delete(String key) async {
    await flush(key);
    await _database.delete(_table, where: 'key = ?', whereArgs: [key]);
    _cache.remove(key);
    _committed.remove(key);
  }

  Future<void> clear() async {
    await flushAll();
    await _database.delete(_table);
    _cache.clear();
    _committed.clear();
  }
}
