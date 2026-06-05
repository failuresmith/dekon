import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../application/application.dart';
import '../backup/backup.dart';
import '../sync/sync.dart';
import 'barcode_scanner_dialog.dart';
import 'cashier_pairing_panel.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.repository,
    this.syncServer,
    this.backupService,
    this.backupFiles = const BackupFileActions(),
    this.scanBarcode = showBarcodeScannerDialog,
    this.pairWithMainDevice,
    this.pairWithMainDeviceAddress,
  });

  final DekonRepository repository;
  final LanSyncServer? syncServer;
  final BackupRunner? backupService;
  final BackupFileActions backupFiles;
  final BarcodeScanLauncher scanBarcode;
  final MainDevicePairer? pairWithMainDevice;
  final MainDeviceAddressPairer? pairWithMainDeviceAddress;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Future<DeviceRoleSettings> _roleFuture = widget.repository
      .deviceRoleSettings();
  DeviceRole? _role;
  bool? _roleLocked;
  var _serverBusy = false;
  var _backupBusy = false;
  var _backupNeedsRetry = false;
  String? _serverError;
  String? _backupStatus;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DeviceRoleSettings>(
      future: _roleFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Settings failed: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final settings = snapshot.requireData;
        final role = _role ?? settings.role;
        final locked = _roleLocked ?? settings.locked;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Settings', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 12),
            _syncPanel(settings, role, locked),
            const SizedBox(height: 12),
            _backupPanel(),
          ],
        );
      },
    );
  }

  Widget _syncPanel(DeviceRoleSettings settings, DeviceRole role, bool locked) {
    final server = widget.syncServer;
    if (server == null) return const SizedBox.shrink();
    if (role == DeviceRole.cashierDevice) {
      return _panel(
        title: 'Main Device Connection',
        child: locked
            ? Text(_cashierConnectionText(settings.deviceDisplayName))
            : CashierPairingPanel(
                repository: widget.repository,
                scanBarcode: widget.scanBarcode,
                pairWithMainDevice: widget.pairWithMainDevice,
                pairWithMainDeviceAddress: widget.pairWithMainDeviceAddress,
                onPaired: _refreshRoleSettings,
              ),
      );
    }
    final running = server.isRunning;
    final qrData = server.pairingQrData;
    return _panel(
      title: 'Cashier Devices',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_serverError != null) Text(_serverError!),
          if (running) ...[
            SelectableText(
              server.serverUrl ?? 'Starting',
              key: const Key('sync-server-url'),
            ),
            if (qrData != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: QrImageView(
                  key: const Key('sync-pairing-qr'),
                  data: qrData,
                  version: QrVersions.auto,
                  size: 160,
                  backgroundColor: Colors.white,
                ),
              ),
            FilledButton.icon(
              key: const Key('stop-sync-server'),
              onPressed: _serverBusy ? null : _stopServer,
              icon: const Icon(Icons.stop),
              label: const Text('Stop Connecting'),
            ),
          ] else
            FilledButton.icon(
              key: const Key('start-sync-server'),
              onPressed: _serverBusy ? null : _startServer,
              icon: const Icon(Icons.sync),
              label: Text(_serverBusy ? 'Starting' : 'Connect Cashier Device'),
            ),
        ],
      ),
    );
  }

  String _cashierConnectionText(String? displayName) {
    final trimmed = displayName?.trim();
    if (trimmed == null ||
        trimmed.isEmpty ||
        trimmed == 'This device' ||
        trimmed == 'Dekon phone') {
      return 'Connected to Main device.';
    }
    return 'Connected to Main device as $trimmed';
  }

  Widget _backupPanel() {
    return _panel(
      title: 'Backup and Recovery',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_backupStatus != null) Text(_backupStatus!),
          if (_backupNeedsRetry) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('retry-backup'),
              onPressed: _backupBusy ? null : _saveBackup,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry Backup'),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                key: const Key('save-backup'),
                onPressed: _backupBusy ? null : _saveBackup,
                icon: const Icon(Icons.save_alt),
                label: Text(_backupBusy ? 'Working' : 'Save Backup'),
              ),
              OutlinedButton.icon(
                key: const Key('restore-backup'),
                onPressed: _backupBusy ? null : _restoreBackup,
                icon: const Icon(Icons.restore),
                label: const Text('Restore Backup'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _panel({required String title, required Widget child}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }

  void _refreshRoleSettings() {
    setState(() {
      _role = DeviceRole.cashierDevice;
      _roleLocked = true;
      _roleFuture = widget.repository.deviceRoleSettings();
    });
  }

  Future<void> _startServer() async {
    setState(() {
      _serverBusy = true;
      _serverError = null;
    });
    try {
      await widget.syncServer!.start();
    } catch (error) {
      _serverError = 'LAN sync failed: $error';
    } finally {
      if (mounted) setState(() => _serverBusy = false);
    }
  }

  Future<void> _stopServer() async {
    setState(() {
      _serverBusy = true;
      _serverError = null;
    });
    try {
      await widget.syncServer!.stop();
    } catch (error) {
      _serverError = 'LAN sync stop failed: $error';
    } finally {
      if (mounted) setState(() => _serverBusy = false);
    }
  }

  Future<void> _saveBackup() async {
    setState(() {
      _backupBusy = true;
      _backupNeedsRetry = false;
      _backupStatus = null;
    });
    BackupExportDraft? draft;
    try {
      draft = await _backupService.prepareExport();
      final savedFile = await widget.backupFiles.saveExportedBackup(
        sourcePath: draft.path,
        fileName: draft.fileName,
      );
      if (savedFile == null) return;
      final result = draft.savedAs(
        path: savedFile.path,
        fileName: savedFile.fileName,
      );
      _backupStatus = 'Saved ${result.eventCount} records to ${result.path}';
      _message('Backup saved to ${result.fileName}');
    } on BackupException catch (error) {
      _backupNeedsRetry = true;
      _backupStatus = 'Backup failed: ${error.message}';
    } on BackupStorageException catch (error) {
      _backupNeedsRetry = true;
      _backupStatus = 'Backup failed: ${error.message}';
    } catch (error) {
      _backupNeedsRetry = true;
      _backupStatus = 'Backup failed: $error';
    } finally {
      if (draft != null) await _backupService.discardPreparedExport(draft);
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  Future<void> _restoreBackup() async {
    setState(() {
      _backupBusy = true;
      _backupNeedsRetry = false;
      _backupStatus = null;
    });
    try {
      final file = await widget.backupFiles.chooseImportFile();
      if (file == null) return;
      final preview = await _backupService.preview(file.contents);
      if (!mounted || await _confirmRestore(file, preview) != true) return;
      final result = await _backupService.importBackup(file.contents);
      _backupStatus =
          'Restored ${result.acceptedCount} records'
          '${result.duplicateCount == 0 ? '' : ', skipped ${result.duplicateCount}'}';
      _message('Backup restored');
    } catch (error) {
      _backupStatus = 'Restore failed: $error';
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  BackupRunner get _backupService {
    return widget.backupService ?? widget.repository.createBackupService();
  }

  Future<bool?> _confirmRestore(BackupImportFile file, BackupPreview preview) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore backup?'),
        content: Text(
          '${file.name}\n'
          '${preview.eventCount} records\n'
          'Made ${preview.exportedAt.toLocal()}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-restore-backup'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}
