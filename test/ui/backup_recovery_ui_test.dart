import 'dart:io';

import 'package:dekon/src/app_config.dart';
import 'package:dekon/src/application/application.dart';
import 'package:dekon/src/backup/backup.dart';
import 'package:dekon/src/sync/sync.dart';
import 'package:dekon/src/ui/barcode_scanner_dialog.dart';
import 'package:dekon/src/ui/cashier_pairing_panel.dart';
import 'package:dekon/src/ui/settings_screen.dart';
import 'package:dekon/src/ui/ui_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';

import '../helpers/test_app.dart';

void main() {
  testWidgets('Backup and Restore saves a backup with safe copy', (
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
      await tester.tap(find.byKey(const Key('settings-backup-restore-tile')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save-backup')));
      await _pumpUntilFound(
        tester,
        find.text('Backup saved successfully: dekon-backup.json'),
      );

      expect(
        find.text('Backup saved successfully: dekon-backup.json'),
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
      appVersion: '0.1.4+5s',
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
      await tester.tap(find.byKey(const Key('settings-backup-restore-tile')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('restore-backup')));
      await _pumpUntilFound(tester, find.text('Restore backup?'));

      expect(find.text('Restore backup?'), findsOneWidget);
      expect(find.textContaining('1 records'), findsOneWidget);

      await tester.tap(find.byKey(const Key('confirm-restore-backup')));
      await _pumpUntilFound(tester, find.byKey(const Key('backup-status')));

      final status = tester.widget<Text>(
        find.byKey(const Key('backup-status')),
      );
      expect(status.data, 'Backup restored successfully');
      expect(backupService.importCalled, true);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await target.close();
    }
  });

  testWidgets('Settings opens minimal About screen with Dekon link', (
    tester,
  ) async {
    final repository = await createTestRepository();
    try {
      await tester.pumpWidget(
        _reportsApp(repository, backupFiles: const _FakeBackupFiles()),
      );
      await _pumpWork(tester);

      await tester.tap(find.byKey(const Key('settings-about-tile')));
      await tester.pumpAndSettle();

      expect(find.text('About'), findsOneWidget);
      expect(find.byKey(const Key('about-link')), findsOneWidget);
      expect(find.text('https://ble.ir/dekon'), findsOneWidget);
      expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
      expect(find.byKey(const Key('about-version')), findsOneWidget);
      expect(find.text('Version ${AppConfig.appVersion}'), findsOneWidget);
      expect(find.text('Device Sync'), findsNothing);
      expect(find.text('Backup and Restore'), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await repository.close();
    }
  });

  testWidgets('Device Sync hides QR and local address until pairing starts', (
    tester,
  ) async {
    final repository = await createTestRepository();
    final syncServer = _FakeLanSyncServer(repository);
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
      expect(find.byKey(const Key('sync-pairing-qr')), findsNothing);
      expect(find.byKey(const Key('sync-server-url')), findsNothing);
      expect(find.byKey(const Key('save-backup')), findsNothing);

      await tester.tap(find.byKey(const Key('settings-device-sync-tile')));
      await tester.pumpAndSettle();

      expect(find.text('Connect Another Device'), findsOneWidget);
      expect(find.byKey(const Key('sync-pairing-qr')), findsNothing);

      await tester.tap(
        find.byKey(const Key('device-sync-start-pairing-button')),
      );
      await _pumpUntilFound(tester, find.byKey(const Key('sync-pairing-qr')));

      expect(find.byKey(const Key('sync-pairing-qr')), findsOneWidget);
      expect(find.text('Stop Pairing'), findsOneWidget);
      expect(find.byKey(const Key('sync-server-url')), findsNothing);

      await tester.tap(find.text('Technical details'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sync-server-url')), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await syncServer.stop();
      await repository.close();
    }
  });

  testWidgets('Device Sync opens peer messages modal on demand', (
    tester,
  ) async {
    final repository = await createTestRepository();
    final syncServer = repository.createLanSyncServer();
    try {
      await syncServer.handler(
        Request('GET', Uri.parse('http://localhost/health')),
      );
      await syncServer.handler(
        Request('GET', Uri.parse('http://localhost/device')),
      );
      await tester.pumpWidget(
        _reportsApp(
          repository,
          backupFiles: const _FakeBackupFiles(),
          syncServer: syncServer,
        ),
      );
      await _pumpWork(tester);

      expect(find.text('Peer messages'), findsNothing);

      await tester.tap(find.byKey(const Key('settings-device-sync-tile')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sync-peer-messages-button')), findsNothing);

      await tester.tap(find.text('Technical details'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sync-peer-messages-button')));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Peer messages'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('clear-sync-peer-messages')), findsOneWidget);
      expect(find.text('Sent'), findsOneWidget);
      expect(find.text('Received'), findsOneWidget);
      expect(find.text('Health check (1)'), findsOneWidget);
      expect(find.text('Device info (1)'), findsOneWidget);
      expect(find.textContaining('Sent 200 GET /health'), findsOneWidget);
      expect(find.textContaining('Sent 200 GET /device'), findsOneWidget);
      expect(find.text('No sent peer messages yet.'), findsNothing);

      await tester.tap(
        find.byKey(const Key('sync-peer-messages-received-tab')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Health check (1)'), findsOneWidget);
      expect(find.text('Device info (1)'), findsOneWidget);
      expect(find.textContaining('Received GET /health'), findsOneWidget);
      expect(find.textContaining('Received GET /device'), findsOneWidget);
      expect(find.text('No received peer messages yet.'), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await syncServer.stop();
      await repository.close();
    }
  });

  testWidgets('Settings lets main device validate scanned QR and locks role', (
    tester,
  ) async {
    final repository = await createTestRepository();
    await repository.setDeviceRole(DeviceRole.cashierDevice);
    final syncServer = repository.createLanSyncServer();
    final payload = SyncPairingPayload(
      baseUrl: 'http://192.168.1.10:1234',
      serverDeviceId: '019e9239-1111-7000-8000-000000000001',
      pairingSecret: 'pairing-secret',
      expiresAt: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
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
            await repository.createSyncStore().updateLocalDeviceDisplayName(
              'Cashier-1',
            );
          },
        ),
      );
      await _pumpWork(tester);
      await tester.tap(find.byKey(const Key('settings-device-sync-tile')));
      await tester.pumpAndSettle();
      await _pumpUntilFound(tester, find.byKey(const Key('pair-main-device')));
      await tester.tap(find.byKey(const Key('pair-main-device')));
      await _pumpUntilFound(tester, find.text('Paired with Main Device.'));

      final settings = await repository.deviceRoleSettings();

      expect(pairedPayload?.serverDeviceId, payload.serverDeviceId);
      expect(find.textContaining('Pairing failed'), findsNothing);
      expect(settings.role, DeviceRole.cashierDevice);
      expect(settings.locked, true);
      expect(settings.onboardingCompleted, true);
      expect(find.text('Paired with Main device as Cashier-1'), findsOneWidget);
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
            await repository.createSyncStore().updateLocalDeviceDisplayName(
              'Cashier-1',
            );
          },
        ),
      );
      await _pumpWork(tester);
      await tester.tap(find.byKey(const Key('settings-device-sync-tile')));
      await tester.pumpAndSettle();
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
      expect(find.text('Paired with Main device as Cashier-1'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await syncServer.stop();
      await repository.close();
    }
  });

  testWidgets('Unpaired cashier backs up and returns to pairing only', (
    tester,
  ) async {
    final repository = await createEnglishTestRepository();
    await repository.lockDeviceRole(DeviceRole.cashierDevice);
    await repository.markCashierUnpairBackupRequired();
    final markedSettings = await repository.deviceRoleSettings();
    expect(markedSettings.onboardingCompleted, true);
    expect(markedSettings.cashierUnpairBackupRequired, true);
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
        testApp(
          repository,
          backupService: backupService,
          backupFiles: const _FakeBackupFiles(
            saveResult: BackupSaveResult(
              path: '/storage/emulated/0/Download/dekon-backup.json',
              fileName: 'dekon-backup.json',
            ),
          ),
        ),
      );
      await _pumpUntil(tester, () async {
        final settings = await repository.deviceRoleSettings();
        return settings.role == DeviceRole.cashierDevice &&
            !settings.locked &&
            !settings.onboardingCompleted &&
            !settings.cashierUnpairBackupRequired;
      });
      await _pumpUntilFound(tester, find.byKey(const Key('pair-main-device')));

      final settings = await repository.deviceRoleSettings();
      final status = tester.any(find.byKey(const Key('cashier-unpair-status')))
          ? tester
                .widget<Text>(find.byKey(const Key('cashier-unpair-status')))
                .data
          : 'no status';

      expect(settings.role, DeviceRole.cashierDevice);
      expect(settings.locked, false, reason: status);
      expect(settings.onboardingCompleted, false);
      expect(settings.cashierUnpairBackupRequired, false);
      expect(find.byKey(const Key('pair-main-device')), findsOneWidget);
      expect(find.byKey(const Key('pair-main-device-manual')), findsOneWidget);
      expect(find.byKey(const Key('sell-screen')), findsNothing);
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
      await tester.tap(find.byKey(const Key('settings-backup-restore-tile')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save-backup')));
      await _pumpUntilFound(tester, find.byKey(const Key('retry-backup')));

      expect(
        find.text(
          'Could not save the backup.\nChoose another folder or check that the selected location is writable.',
        ),
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

Future<void> _pumpUntil(
  WidgetTester tester,
  Future<bool> Function() condition,
) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (await condition()) return;
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
  return _TestLanguageHost(
    child: MaterialApp(
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
    ),
  );
}

class _TestLanguageHost extends StatefulWidget {
  const _TestLanguageHost({required this.child});

  final Widget child;

  @override
  State<_TestLanguageHost> createState() => _TestLanguageHostState();
}

class _TestLanguageHostState extends State<_TestLanguageHost> {
  late final AppLanguageController _languageController = AppLanguageController(
    initialLanguage: AppLanguage.english,
    initialMoneyUnit: MoneyUnit.rial,
    saveLanguage: (_) async {},
    saveMoneyUnit: (_) async {},
  );

  @override
  void dispose() {
    _languageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppLanguageScope(
      controller: _languageController,
      child: widget.child,
    );
  }
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

class _FakeLanSyncServer extends LanSyncServer {
  _FakeLanSyncServer(DekonRepository repository)
    : super(store: repository.createSyncStore());

  var _running = false;

  @override
  bool get isRunning => _running;

  @override
  String? get serverUrl => _running ? 'http://192.168.1.10:40739' : null;

  @override
  String? get pairingQrData => _running
      ? SyncPairingPayload(
          baseUrl: serverUrl!,
          serverDeviceId: store.localDeviceId,
          pairingSecret: 'pairing-secret',
          expiresAt: DateTime.utc(2026, 6, 5, 12),
        ).toQrJson()
      : null;

  @override
  Future<void> start({
    InternetAddress? address,
    int port = 0,
    Duration pairingTtl = const Duration(minutes: 10),
    bool enablePairing = true,
  }) async {
    _running = true;
  }

  @override
  Future<void> stop() async {
    _running = false;
  }
}
