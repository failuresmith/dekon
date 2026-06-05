import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../app_config.dart';
import '../domain/events/events.dart';
import '../persistence/persistence.dart';
import '../sync/sync_protocol.dart';

const _backupFormat = 'dekon.event_backup';
const _backupFormatVersion = 1;

abstract interface class BackupRunner {
  Future<BackupExportResult> exportToDirectory(String directoryPath);
  Future<BackupPreview> preview(String contents);
  Future<BackupImportResult> importBackup(String contents);
}

class BackupService implements BackupRunner {
  BackupService({
    required Database database,
    EventStore? eventStore,
    DomainProjector? projector,
    DateTime Function()? now,
  }) : _db = database,
       _eventStore = eventStore ?? EventStore(database),
       _projector = projector ?? DomainProjector(database),
       _now = now ?? DateTime.now;

  final Database _db;
  final EventStore _eventStore;
  final DomainProjector _projector;
  final DateTime Function() _now;

  @override
  Future<BackupExportResult> exportToDirectory(String directoryPath) async {
    final directory = Directory(directoryPath);
    if (!await directory.exists()) {
      throw BackupException('Backup folder does not exist.');
    }
    final exportedAt = _now().toUtc();
    final eventCount = await _eventStore.count();
    final fileName = _fileName(exportedAt);
    final target = File(p.join(directory.path, fileName));
    final temp = File(p.join(directory.path, '.$fileName.tmp'));
    if (await target.exists()) {
      throw BackupException('Backup file already exists.');
    }

    IOSink? sink;
    var written = 0;
    try {
      sink = temp.openWrite();
      _writeHeader(sink, exportedAt, eventCount);
      SyncCursor? cursor;
      var first = true;
      while (written < eventCount) {
        final events = await _eventStore.fetchEventsAfter(
          hlc: cursor?.hlc,
          eventId: cursor?.eventId,
          limit: (eventCount - written).clamp(1, 500).toInt(),
        );
        if (events.isEmpty) break;
        for (final event in events) {
          if (!first) sink.write(',');
          sink.write(jsonEncode(EventCodec.toJson(event)));
          first = false;
          written++;
          cursor = SyncCursor.fromEvent(event);
          if (written >= eventCount) break;
        }
      }
      sink.write(']}');
      await sink.flush();
      await sink.close();
      sink = null;
      await temp.rename(target.path);
      return BackupExportResult(
        path: target.path,
        fileName: fileName,
        eventCount: written,
        exportedAt: exportedAt,
      );
    } on FileSystemException {
      await sink?.close();
      await _deleteTempFile(temp);
      throw BackupException(
        'Storage access was denied. Choose a backup folder and try again.',
      );
    } on Object catch (error) {
      await sink?.close();
      await _deleteTempFile(temp);
      if (error is BackupException) rethrow;
      throw BackupException('Backup could not be saved.');
    }
  }

  @override
  Future<BackupPreview> preview(String contents) async {
    return _parse(contents).preview;
  }

  @override
  Future<BackupImportResult> importBackup(String contents) async {
    final parsed = _parse(contents);
    final accepted = <String>[];
    final duplicate = <String>[];
    final unsupported = <String>[];

    try {
      await _db.transaction((txn) async {
        for (final event in parsed.events) {
          final write = await _eventStore.appendInTransaction(txn, event);
          switch (write.status) {
            case EventWriteStatus.accepted:
              accepted.add(event.eventId);
              if (_isProjectable(event)) {
                await _projector.applyInTransaction(txn, event);
              }
            case EventWriteStatus.duplicate:
              duplicate.add(event.eventId);
            case EventWriteStatus.unsupported:
              unsupported.add(event.eventId);
          }
        }
      });
    } on Object {
      throw BackupException('Backup could not be restored.');
    }

    return BackupImportResult(
      acceptedCount: accepted.length,
      duplicateCount: duplicate.length,
      unsupportedCount: unsupported.length,
      preview: parsed.preview,
    );
  }

  void _writeHeader(IOSink sink, DateTime exportedAt, int eventCount) {
    final metadata = <String, Object?>{
      'format': _backupFormat,
      'format_version': _backupFormatVersion,
      'application_id': AppConfig.applicationId,
      'app_name': AppConfig.appName,
      'app_version': AppConfig.appVersion,
      'database_schema_version': CoreDatabase.schemaVersion,
      'event_schema_version': EventSchema.currentVersion,
      'exported_at': exportedAt.toIso8601String(),
      'event_count': eventCount,
    };
    final encoded = jsonEncode(metadata);
    sink.write('${encoded.substring(0, encoded.length - 1)},"events":[');
  }

  _ParsedBackup _parse(String contents) {
    try {
      final decoded = jsonDecode(contents);
      if (decoded is! Map) throw BackupException('Backup file is not valid.');
      final map = <String, Object?>{
        for (final entry in decoded.entries)
          if (entry.key is String) entry.key as String: entry.value as Object?,
      };
      _validateMetadata(map);
      final rawEvents = map['events'];
      if (rawEvents is! List) {
        throw BackupException('Backup file has no records.');
      }
      final eventCount = _int(map, 'event_count');
      if (rawEvents.length != eventCount) {
        throw BackupException('Backup record count does not match.');
      }
      final events = <EventEnvelope>[];
      for (final raw in rawEvents) {
        try {
          final event = EventCodec.fromJson(raw);
          EventValidator.validateForStorage(event);
          events.add(event);
        } on Object {
          throw BackupException('Backup contains a damaged record.');
        }
      }
      return _ParsedBackup(
        preview: BackupPreview(
          exportedAt: DateTime.parse(_string(map, 'exported_at')),
          eventCount: eventCount,
          appVersion: _string(map, 'app_version'),
        ),
        events: events,
      );
    } on BackupException {
      rethrow;
    } on Object {
      throw BackupException('Backup file is not valid.');
    }
  }

  void _validateMetadata(Map<String, Object?> map) {
    if (_string(map, 'format') != _backupFormat) {
      throw BackupException('This is not a Dekon backup file.');
    }
    if (_int(map, 'format_version') != _backupFormatVersion) {
      throw BackupException('This backup format is not supported.');
    }
    if (_string(map, 'application_id') != AppConfig.applicationId) {
      throw BackupException('This backup belongs to another app.');
    }
    if (_int(map, 'database_schema_version') > CoreDatabase.schemaVersion) {
      throw BackupException('This backup was made by a newer Dekon version.');
    }
    if (_int(map, 'event_schema_version') > EventSchema.currentVersion) {
      throw BackupException('This backup was made by a newer Dekon version.');
    }
    DateTime.parse(_string(map, 'exported_at'));
  }

  bool _isProjectable(EventEnvelope event) {
    return EventSchema.isSupported(event.schemaVersion) &&
        EventTypes.supported.contains(event.type);
  }

  String _fileName(DateTime exportedAt) {
    final stamp = exportedAt
        .toIso8601String()
        .replaceAll('-', '')
        .replaceAll(':', '')
        .split('.')
        .first;
    return 'dekon-backup-$stamp.json';
  }

  Future<void> _deleteTempFile(File temp) async {
    try {
      if (await temp.exists()) await temp.delete();
    } on FileSystemException {
      // Keep the original backup failure visible to the user.
    }
  }

  String _string(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is String && value.trim().isNotEmpty) return value;
    throw BackupException('Backup file is missing $key.');
  }

  int _int(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is int && value >= 0) return value;
    throw BackupException('Backup file is missing $key.');
  }
}

class BackupPreview {
  const BackupPreview({
    required this.exportedAt,
    required this.eventCount,
    required this.appVersion,
  });

  final DateTime exportedAt;
  final int eventCount;
  final String appVersion;
}

class BackupExportResult {
  const BackupExportResult({
    required this.path,
    required this.fileName,
    required this.eventCount,
    required this.exportedAt,
  });

  final String path;
  final String fileName;
  final int eventCount;
  final DateTime exportedAt;
}

class BackupImportResult {
  const BackupImportResult({
    required this.acceptedCount,
    required this.duplicateCount,
    required this.unsupportedCount,
    required this.preview,
  });

  final int acceptedCount;
  final int duplicateCount;
  final int unsupportedCount;
  final BackupPreview preview;
}

class BackupException implements Exception {
  BackupException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _ParsedBackup {
  const _ParsedBackup({required this.preview, required this.events});

  final BackupPreview preview;
  final List<EventEnvelope> events;
}
