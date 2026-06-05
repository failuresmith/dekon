import 'package:dekon/src/application/application.dart';
import 'package:dekon/src/backup/backup.dart';
import 'package:dekon/src/sync/sync.dart';
import 'package:dekon/src/ui/barcode_scanner_dialog.dart';
import 'package:dekon/src/ui/cashier_pairing_panel.dart';
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
          backupFiles: const _FakeBackupFiles(
            saveResult: BackupSaveResult(
              path: '/storage/emulated/0/Download/dekon-backup.json',
              fileName: 'dekon-backup.json',
            ),
          ),
          backupService: backupService,
        ),
      );
      await _pumpWork(tester);
      await tester.tap(find.byKey(const Key('save-backup')));
      await _pumpUntilFound(
        tester,
        find.text(
          'Saved 1 records to /storage/emulated/0/Download/dekon-backup.json',
        ),
      );

      expect(
        find.text(
          'Saved 1 records to /storage/emulated/0/Download/dekon-backup.json',
        ),
        findsOneWidget,
      );
      expect(backupService.prepareCalled, true);
      expect(backupService.discardCalled, true);
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

  testWidgets('Settings hides device role and shows connect cashier action', (
    tester,
  ) async {
    final repository = await createTestRepository();
    final syncServer = repository.createLanSyncServer();
    try {
      await tester.pumpWidget(
        _reportsApp(
          repository,
          backupFiles: const _FakeBackupFiles(),
          syncServer: syncServer,
        ),
      );
      await _pumpWork(tester);

      expect(find.text('Device Role'), findsNothing);
      expect(find.byKey(const Key('cashier-device-role')), findsNothing);
      expect(find.text('Connect Cashier Device'), findsOneWidget);
      expect(find.text('Start LAN Sync'), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await syncServer.stop();
      await repository.close();
    }
  });

  testWidgets('Settings pairs cashier device and locks role', (tester) async {
    final repository = await createTestRepository();
    await repository.setDeviceRole(DeviceRole.cashierDevice);
    final syncServer = repository.createLanSyncServer();
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
          syncServer: syncServer,
          scanBarcode: (_) async => payload.toQrJson(),
          pairWithMainDevice: (payload) async {
            pairedPayload = payload;
          },
        ),
      );
      await _pumpWork(tester);
      await _pumpUntilFound(tester, find.byKey(const Key('pair-main-device')));
      await tester.tap(find.byKey(const Key('pair-main-device')));
      await _pumpUntilFound(tester, find.text('Paired with Main Device.'));

      final settings = await repository.deviceRoleSettings();

      expect(pairedPayload?.serverDeviceId, payload.serverDeviceId);
      expect(settings.role, DeviceRole.cashierDevice);
      expect(settings.locked, true);
      expect(settings.onboardingCompleted, true);
      expect(
        find.text('Connected to a main device. This role cannot be changed.'),
        findsOneWidget,
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await syncServer.stop();
      await repository.close();
    }
  });

  testWidgets('Settings pairs cashier device by manual IP entry', (
    tester,
  ) async {
    final repository = await createTestRepository();
    await repository.setDeviceRole(DeviceRole.cashierDevice);
    final syncServer = repository.createLanSyncServer();
    String? pairedAddress;
    try {
      await tester.pumpWidget(
        _reportsApp(
          repository,
          backupFiles: const _FakeBackupFiles(),
          syncServer: syncServer,
          pairWithMainDeviceAddress: (address) async {
            pairedAddress = address;
          },
        ),
      );
      await _pumpUntilFound(
        tester,
        find.byKey(const Key('pair-main-device-manual')),
      );
      await tester.tap(find.byKey(const Key('pair-main-device-manual')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('manual-main-device-address')),
        '192.168.1.10:1234',
      );
      await tester.tap(find.byKey(const Key('confirm-manual-main-device')));
      await _pumpUntilFound(tester, find.text('Paired with Main Device.'));

      final settings = await repository.deviceRoleSettings();
      expect(pairedAddress, '192.168.1.10:1234');
      expect(settings.role, DeviceRole.cashierDevice);
      expect(settings.locked, true);
      expect(settings.onboardingCompleted, true);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await syncServer.stop();
      await repository.close();
    }
  });

  testWidgets('Settings shows retry when backup storage access is denied', (
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
          backupFiles: const _FakeBackupFiles(
            saveError: BackupStorageException('Storage access was denied.'),
          ),
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
      expect(backupService.discardCalled, true);
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
  LanSyncServer? syncServer,
  BarcodeScanLauncher? scanBarcode,
  MainDevicePairer? pairWithMainDevice,
  MainDeviceAddressPairer? pairWithMainDeviceAddress,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SettingsScreen(
        repository: repository,
        syncServer: syncServer,
        backupFiles: backupFiles,
        backupService: backupService,
        scanBarcode: scanBarcode ?? showBarcodeScannerDialog,
        pairWithMainDevice: pairWithMainDevice,
        pairWithMainDeviceAddress: pairWithMainDeviceAddress,
      ),
    ),
  );
}

class _FakeBackupFiles extends BackupFileActions {
  const _FakeBackupFiles({this.saveResult, this.saveError, this.importFile});

  final BackupSaveResult? saveResult;
  final Object? saveError;
  final BackupImportFile? importFile;

  @override
  Future<BackupSaveResult?> saveExportedBackup({
    required String sourcePath,
    required String fileName,
  }) async {
    final error = saveError;
    if (error != null) throw error;
    return saveResult;
  }

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
  var prepareCalled = false;
  var discardCalled = false;
  var importCalled = false;

  @override
  Future<BackupExportResult> exportToDirectory(String directoryPath) async {
    exportCalled = true;
    return exportResult!;
  }

  @override
  Future<BackupExportDraft> prepareExport() async {
    prepareCalled = true;
    final result = exportResult!;
    return BackupExportDraft(
      path: result.path,
      fileName: result.fileName,
      eventCount: result.eventCount,
      exportedAt: result.exportedAt,
      cleanupDirectoryPath: '/tmp/dekon-backup-draft',
    );
  }

  @override
  Future<void> discardPreparedExport(BackupExportDraft draft) async {
    discardCalled = true;
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
