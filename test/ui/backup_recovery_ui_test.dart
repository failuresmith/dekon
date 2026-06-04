import 'package:dekon/src/application/application.dart';
import 'package:dekon/src/backup/backup.dart';
import 'package:dekon/src/ui/reports_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

void main() {
  testWidgets('Reports saves a backup through simple backup action', (
    tester,
  ) async {
    final repository = await createTestRepository();
    final backupService = _FakeBackupService(
      exportResult: BackupExportResult(
        path: '/tmp/dekon-backup.json',
        fileName: 'dekon-backup.json',
        eventCount: 1,
        exportedAt: DateTime.utc(2026, 6, 4),
      ),
    );
    try {
      await tester.pumpWidget(
        _reportsApp(
          repository,
          backupFiles: const _FakeBackupFiles(exportDirectory: '/tmp'),
          backupService: backupService,
        ),
      );
      await _pumpWork(tester);
      await tester.tap(find.byKey(const Key('save-backup')));
      await _pumpUntilFound(tester, find.text('Saved 1 records'));

      expect(find.text('Saved 1 records'), findsOneWidget);
      expect(backupService.exportCalled, true);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await repository.close();
    }
  });

  testWidgets('Reports previews and restores a selected backup', (
    tester,
  ) async {
    final target = await createTestRepository();
    final preview = BackupPreview(
      exportedAt: DateTime.utc(2026, 6, 4),
      eventCount: 1,
      appVersion: '0.1.0+1',
    );
    final backupService = _FakeBackupService(
      previewResult: preview,
      importResult: BackupImportResult(
        acceptedCount: 1,
        duplicateCount: 0,
        unsupportedCount: 0,
        preview: preview,
      ),
    );
    try {
      await tester.pumpWidget(
        _reportsApp(
          target,
          backupFiles: const _FakeBackupFiles(
            importFile: BackupImportFile(name: 'backup.json', contents: '{}'),
          ),
          backupService: backupService,
        ),
      );
      await _pumpWork(tester);
      await tester.tap(find.byKey(const Key('restore-backup')));
      await _pumpUntilFound(tester, find.text('Restore backup?'));

      expect(find.text('Restore backup?'), findsOneWidget);
      expect(find.textContaining('1 records'), findsOneWidget);

      await tester.tap(find.byKey(const Key('confirm-restore-backup')));
      await _pumpUntilFound(tester, find.text('Restored 1 records'));

      expect(find.text('Restored 1 records'), findsOneWidget);
      expect(backupService.importCalled, true);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await target.close();
    }
  });
}

Future<void> _pumpWork(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (tester.any(finder)) return;
  }
}

Widget _reportsApp(
  DekonRepository repository, {
  required BackupFileActions backupFiles,
  BackupRunner? backupService,
}) {
  return MaterialApp(
    home: Scaffold(
      body: ReportsScreen(
        repository: repository,
        backupFiles: backupFiles,
        backupService: backupService,
      ),
    ),
  );
}

class _FakeBackupFiles extends BackupFileActions {
  const _FakeBackupFiles({this.exportDirectory, this.importFile});

  final String? exportDirectory;
  final BackupImportFile? importFile;

  @override
  Future<String?> chooseExportDirectory() async => exportDirectory;

  @override
  Future<BackupImportFile?> chooseImportFile() async => importFile;
}

class _FakeBackupService implements BackupRunner {
  _FakeBackupService({
    this.exportResult,
    this.previewResult,
    this.importResult,
  });

  final BackupExportResult? exportResult;
  final BackupPreview? previewResult;
  final BackupImportResult? importResult;
  var exportCalled = false;
  var importCalled = false;

  @override
  Future<BackupExportResult> exportToDirectory(String directoryPath) async {
    exportCalled = true;
    return exportResult!;
  }

  @override
  Future<BackupPreview> preview(String contents) async {
    return previewResult!;
  }

  @override
  Future<BackupImportResult> importBackup(String contents) async {
    importCalled = true;
    return importResult!;
  }
}
