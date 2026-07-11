import 'dart:convert';

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
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys=ON');
      },
      onOpen: (db) async {
        await db.execute('PRAGMA journal_mode=WAL');
        await db.execute('PRAGMA synchronous=NORMAL');
      },
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
}

class SqliteJsonStore<T> {
  SqliteJsonStore(this._database, this._table, this._encode, this._decode);

  final Database _database;
  final String _table;
  final dynamic Function(T value) _encode;
  final T Function(dynamic value) _decode;
  final Map<String, T> _cache = <String, T>{};
  final Map<String, Future<void>> _writes = <String, Future<void>>{};

  Iterable<T> get values => _cache.values;
  Iterable<String> get keys => _cache.keys;
  bool get isEmpty => _cache.isEmpty;

  T? get(String key) => _cache[key];
  void putCached(String key, T value) => _cache[key] = value;
  bool containsKey(String key) => _cache.containsKey(key);

  Future<void> load() async {
    final rows = await _database.query(_table);
    _cache.clear();
    for (final row in rows) {
      final key = row['key'] as String;
      final payload = jsonDecode(row['payload'] as String);
      _cache[key] = _decode(payload);
    }
  }

  Future<void> put(String key, T value) {
    _cache[key] = value;
    final previous = _writes[key] ?? Future<void>.value();
    final next = previous.then((_) async {
      await _database.insert(
        _table,
        {'key': key, 'payload': jsonEncode(_encode(value))},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    _writes[key] = next;
    return next.whenComplete(() {
      if (identical(_writes[key], next)) _writes.remove(key);
    });
  }

  Future<void> delete(String key) async {
    _cache.remove(key);
    await (_writes[key] ?? Future<void>.value());
    await _database.delete(_table, where: 'key = ?', whereArgs: [key]);
  }

  Future<void> clear() async {
    _cache.clear();
    await _database.delete(_table);
  }
}
