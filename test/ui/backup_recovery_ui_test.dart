import 'package:dekon/src/application/application.dart';
import 'package:dekon/src/backup/backup.dart';
import 'package:dekon/src/sync/sync.dart';
import 'package:dekon/src/ui/barcode_scanner_dialog.dart';
import 'package:dekon/src/ui/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

void main() {
  testWidgets('Settings saves a backup and shows the saved path', (
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
      await _pumpUntilFound(
        tester,
        find.text('Saved 1 records to /tmp/dekon-backup.json'),
      );

      expect(
        find.text('Saved 1 records to /tmp/dekon-backup.json'),
        findsOneWidget,
      );
      expect(backupService.exportCalled, true);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await repository.close();
    }
  });

  testWidgets('Settings previews and restores a selected backup', (
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

  testWidgets('Settings persists cashier device role', (tester) async {
    final repository = await createTestRepository();
    try {
      await tester.pumpWidget(
        _reportsApp(repository, backupFiles: const _FakeBackupFiles()),
      );
      await _pumpWork(tester);
      await tester.tap(find.byKey(const Key('cashier-device-role')));
      await _pumpWork(tester);

      expect(await repository.deviceRole(), DeviceRole.cashierDevice);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await repository.close();
    }
  });

  testWidgets('Settings pairs cashier device and locks role', (tester) async {
    final repository = await createTestRepository();
    final payload = SyncPairingPayload(
      baseUrl: 'http://192.168.1.10:1234',
      serverDeviceId: '019e9239-1111-7000-8000-000000000001',
      pairingSecret: 'pairing-secret',
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
    );
    SyncPairingPayload? pairedPayload;
    try {
      await tester.pumpWidget(
        _reportsApp(
          repository,
          backupFiles: const _FakeBackupFiles(),
          scanBarcode: (_) async => payload.toQrJson(),
          pairWithMainDevice: (payload) async {
            pairedPayload = payload;
          },
        ),
      );
      await _pumpWork(tester);
      await tester.tap(find.byKey(const Key('cashier-device-role')));
      await _pumpUntilFound(tester, find.byKey(const Key('pair-main-device')));
      await tester.tap(find.byKey(const Key('pair-main-device')));
      await _pumpUntilFound(tester, find.text('Paired with Main Device.'));

      final settings = await repository.deviceRoleSettings();
      final cashierTile = tester.widget<RadioListTile<DeviceRole>>(
        find.byKey(const Key('cashier-device-role')),
      );

      expect(pairedPayload?.serverDeviceId, payload.serverDeviceId);
      expect(settings.role, DeviceRole.cashierDevice);
      expect(settings.locked, true);
      expect(cashierTile.enabled, false);
      expect(find.text('Paired. Device role is locked.'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await repository.close();
    }
  });

  testWidgets('Settings shows retry when backup storage access is denied', (
    tester,
  ) async {
    final repository = await createTestRepository();
    final backupService = _FakeBackupService(
      exportError: BackupException('Storage access was denied.'),
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
      await _pumpUntilFound(tester, find.byKey(const Key('retry-backup')));

      expect(
        find.text('Backup failed: Storage access was denied.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('retry-backup')), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await repository.close();
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
  BarcodeScanLauncher? scanBarcode,
  MainDevicePairer? pairWithMainDevice,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SettingsScreen(
        repository: repository,
        backupFiles: backupFiles,
        backupService: backupService,
        scanBarcode: scanBarcode ?? showBarcodeScannerDialog,
        pairWithMainDevice: pairWithMainDevice,
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
    this.exportError,
    this.previewResult,
    this.importResult,
  });

  final BackupExportResult? exportResult;
  final Object? exportError;
  final BackupPreview? previewResult;
  final BackupImportResult? importResult;
  var exportCalled = false;
  var importCalled = false;

  @override
  Future<BackupExportResult> exportToDirectory(String directoryPath) async {
    exportCalled = true;
    final error = exportError;
    if (error != null) throw error;
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
