import 'dart:convert';
import 'dart:io';

import 'package:dekon/src/application/application.dart';
import 'package:dekon/src/app_config.dart';
import 'package:dekon/src/backup/backup.dart';
import 'package:dekon/src/domain/events/events.dart';
import 'package:dekon/src/persistence/persistence.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/test_app.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('exports event backup with metadata and no temp file left', () async {
    final repository = await createTestRepository();
    final directory = await Directory.systemTemp.createTemp('dekon_backup_');
    try {
      await repository.createProduct(name: 'Coffee', barcode: 'COF-1');

      final result = await repository.createBackupService().exportToDirectory(
        directory.path,
      );
      final file = File(result.path);
      final decoded = jsonDecode(await file.readAsString()) as Map;

      expect(result.eventCount, 1);
      expect(file.existsSync(), true);
      expect(
        directory.listSync().where((entry) => entry.path.endsWith('.tmp')),
        isEmpty,
      );
      expect(decoded['format'], 'dekon.event_backup');
      expect(decoded['application_id'], AppConfig.applicationId);
      expect(decoded['database_schema_version'], CoreDatabase.schemaVersion);
      expect(decoded['event_count'], 1);
      expect(decoded['events'], hasLength(1));
    } finally {
      await repository.close();
      await directory.delete(recursive: true);
    }
  });

  test('imports backup into a new database and skips duplicates', () async {
    final source = await createTestRepository();
    final target = await createTestRepository();
    final directory = await Directory.systemTemp.createTemp('dekon_backup_');
    try {
      final product = await source.createProduct(
        name: 'Tea',
        barcode: 'TEA-RESTORE',
        salePriceMinor: 250,
      );
      await source.recordPurchase([
        TransactionLineDraft(product: product, quantity: 4),
      ]);
      final export = await source.createBackupService().exportToDirectory(
        directory.path,
      );
      final contents = await File(export.path).readAsString();

      final first = await target.createBackupService().importBackup(contents);
      final second = await target.createBackupService().importBackup(contents);
      final restored = await target.productByBarcodeOrSku('TEA-RESTORE');

      expect(first.acceptedCount, 2);
      expect(first.duplicateCount, 0);
      expect(second.acceptedCount, 0);
      expect(second.duplicateCount, 2);
      expect(restored?.name, 'Tea');
      expect(restored?.quantity, 4);
    } finally {
      await source.close();
      await target.close();
      await directory.delete(recursive: true);
    }
  });

  test('validates backup before mutating local state', () async {
    final repository = await createTestRepository();
    try {
      await expectLater(
        repository.createBackupService().importBackup('not-json'),
        throwsA(isA<BackupException>()),
      );

      expect((await repository.reportSummary()).unsyncedEventCount, 0);
    } finally {
      await repository.close();
    }
  });

  test('rejects backups from newer event schema versions', () async {
    final repository = await createTestRepository();
    try {
      final backup = jsonEncode({
        'format': 'dekon.event_backup',
        'format_version': 1,
        'application_id': AppConfig.applicationId,
        'app_name': AppConfig.appName,
        'app_version': AppConfig.appVersion,
        'database_schema_version': CoreDatabase.schemaVersion,
        'event_schema_version': EventSchema.currentVersion + 1,
        'exported_at': DateTime.utc(2026, 6, 4).toIso8601String(),
        'event_count': 0,
        'events': [],
      });

      await expectLater(
        repository.createBackupService().importBackup(backup),
        throwsA(isA<BackupException>()),
      );
    } finally {
      await repository.close();
    }
  });

  test('rolls back restore when projected data conflicts', () async {
    final source = await createTestRepository();
    final target = await createTestRepository();
    final directory = await Directory.systemTemp.createTemp('dekon_backup_');
    try {
      await source.createProduct(name: 'Source Tea', barcode: 'DUP-1');
      await target.createProduct(name: 'Target Tea', barcode: 'DUP-1');
      final before = (await target.reportSummary()).unsyncedEventCount;
      final export = await source.createBackupService().exportToDirectory(
        directory.path,
      );

      await expectLater(
        target.createBackupService().importBackup(
          await File(export.path).readAsString(),
        ),
        throwsA(isA<BackupException>()),
      );

      final after = (await target.reportSummary()).unsyncedEventCount;
      expect(after, before);
      expect((await target.products()).single.name, 'Target Tea');
    } finally {
      await source.close();
      await target.close();
      await directory.delete(recursive: true);
    }
  });
}
