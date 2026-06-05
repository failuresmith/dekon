import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../application/application.dart';
import '../backup/backup.dart';
import '../sync/sync.dart';
import 'barcode_scanner_dialog.dart';

typedef MainDevicePairer = Future<void> Function(SyncPairingPayload payload);

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.repository,
    this.syncServer,
    this.backupService,
    this.backupFiles = const BackupFileActions(),
    this.scanBarcode = showBarcodeScannerDialog,
    this.pairWithMainDevice,
  });

  final DekonRepository repository;
  final LanSyncServer? syncServer;
  final BackupRunner? backupService;
  final BackupFileActions backupFiles;
  final BarcodeScanLauncher scanBarcode;
  final MainDevicePairer? pairWithMainDevice;

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
  var _pairingBusy = false;
  var _backupNeedsRetry = false;
  String? _serverError;
  String? _backupStatus;
  String? _pairingStatus;

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
            _deviceRolePanel(role, locked),
            const SizedBox(height: 12),
            _syncPanel(role, locked),
            const SizedBox(height: 12),
            _backupPanel(),
          ],
        );
      },
    );
  }

  Widget _deviceRolePanel(DeviceRole role, bool locked) {
    return _panel(
      title: 'Device Role',
      child: RadioGroup<DeviceRole>(
        groupValue: role,
        onChanged: locked ? (_) {} : _setRole,
        child: Column(
          children: [
            RadioListTile<DeviceRole>(
              key: const Key('main-device-role'),
              value: DeviceRole.mainDevice,
              selected: role == DeviceRole.mainDevice,
              enabled: !locked,
              title: const Text('Main Device'),
              subtitle: const Text('Stores and manages the shared data.'),
            ),
            RadioListTile<DeviceRole>(
              key: const Key('cashier-device-role'),
              value: DeviceRole.cashierDevice,
              selected: role == DeviceRole.cashierDevice,
              enabled: !locked,
              title: const Text('Cashier Device'),
              subtitle: const Text(
                'Connects to the main device and records sales.',
              ),
            ),
            if (role == DeviceRole.cashierDevice) ...[
              if (locked)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Text('Paired. Device role is locked.'),
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      key: const Key('pair-main-device'),
                      onPressed: _pairingBusy ? null : _pairCashierDevice,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: Text(
                        _pairingBusy ? 'Pairing' : 'Pair with Main Device',
                      ),
                    ),
                  ),
                ),
              if (_pairingStatus != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(_pairingStatus!),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _syncPanel(DeviceRole role, bool locked) {
    final server = widget.syncServer;
    if (server == null) return const SizedBox.shrink();
    if (role == DeviceRole.cashierDevice) {
      return _panel(
        title: 'LAN Sync',
        child: Text(
          locked
              ? 'Connected to a main device. This role cannot be changed.'
              : 'Pair this cashier device with the main device before use.',
        ),
      );
    }
    final running = server.isRunning;
    final qrData = server.pairingQrData;
    return _panel(
      title: 'LAN Sync',
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
              label: const Text('Stop LAN Sync'),
            ),
          ] else
            FilledButton.icon(
              key: const Key('start-sync-server'),
              onPressed: _serverBusy ? null : _startServer,
              icon: const Icon(Icons.sync),
              label: Text(_serverBusy ? 'Starting' : 'Start LAN Sync'),
            ),
        ],
      ),
    );
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

  Future<void> _setRole(DeviceRole? role) async {
    if (role == null) return;
    final previous = _role;
    setState(() => _role = role);
    try {
      await widget.repository.setDeviceRole(role);
      _roleFuture = Future.value(DeviceRoleSettings(role: role, locked: false));
    } catch (error) {
      setState(() => _role = previous);
      _message('Device role save failed: $error');
    }
  }

  Future<void> _pairCashierDevice() async {
    setState(() {
      _pairingBusy = true;
      _pairingStatus = null;
    });
    try {
      final scanned = await widget.scanBarcode(context);
      if (!mounted || scanned == null || scanned.trim().isEmpty) return;
      final payload = SyncPairingPayload.fromQrJson(scanned.trim());
      if (payload.expiresAt.isBefore(DateTime.now().toUtc())) {
        throw const FormatException('Pairing code has expired.');
      }
      await _pairWithMainDevice(payload);
      await widget.repository.lockDeviceRole(DeviceRole.cashierDevice);
      final settings = const DeviceRoleSettings(
        role: DeviceRole.cashierDevice,
        locked: true,
      );
      setState(() {
        _role = settings.role;
        _roleLocked = settings.locked;
        _roleFuture = Future.value(settings);
        _pairingStatus = 'Paired with Main Device.';
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _pairingStatus = 'Pairing failed: ${_safePairingError(error)}',
        );
      }
    } finally {
      if (mounted) setState(() => _pairingBusy = false);
    }
  }

  Future<void> _pairWithMainDevice(SyncPairingPayload payload) async {
    final injected = widget.pairWithMainDevice;
    if (injected != null) {
      await injected(payload);
      return;
    }
    final client = widget.repository.createLanSyncClient();
    try {
      await client.pairWithServer(payload, displayName: 'Cashier Device');
    } finally {
      client.close();
    }
  }

  String _safePairingError(Object error) {
    if (error is FormatException) return error.message;
    if (error is SyncClientException) return error.message;
    return 'Could not pair with the main device.';
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
    try {
      final directory = await widget.backupFiles.chooseExportDirectory();
      if (directory == null) return;
      final result = await _backupService.exportToDirectory(directory);
      _backupStatus = 'Saved ${result.eventCount} records to ${result.path}';
      _message('Backup saved to ${result.fileName}');
    } on BackupException catch (error) {
      _backupNeedsRetry = true;
      _backupStatus = 'Backup failed: ${error.message}';
    } catch (error) {
      _backupNeedsRetry = true;
      _backupStatus = 'Backup failed: $error';
    } finally {
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
