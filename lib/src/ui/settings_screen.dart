import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../application/application.dart';
import '../backup/backup.dart';
import '../sync/sync.dart';
import 'barcode_scanner_dialog.dart';
import 'cashier_pairing_panel.dart';
import 'ui_strings.dart';

class SettingsScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SettingsSectionTile(
          key: const Key('settings-device-sync-tile'),
          title: UiStrings.deviceSync,
          subtitle: 'Manage connected cashier devices',
          icon: Icons.sync_alt,
          onTap: () => _openDeviceSync(context),
        ),
        const SizedBox(height: 12),
        _SettingsSectionTile(
          key: const Key('settings-backup-restore-tile'),
          title: UiStrings.backupAndRestore,
          subtitle: 'Save or restore store data',
          icon: Icons.backup_outlined,
          onTap: () => _openBackupRestore(context),
        ),
      ],
    );
  }

  Future<void> _openDeviceSync(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => DeviceSyncScreen(
          repository: repository,
          syncServer: syncServer,
          scanBarcode: scanBarcode,
          pairWithMainDevice: pairWithMainDevice,
          pairWithMainDeviceAddress: pairWithMainDeviceAddress,
        ),
      ),
    );
  }

  Future<void> _openBackupRestore(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => BackupRestoreScreen(
          repository: repository,
          backupService: backupService,
          backupFiles: backupFiles,
        ),
      ),
    );
  }
}

class DeviceSyncScreen extends StatefulWidget {
  const DeviceSyncScreen({
    super.key,
    required this.repository,
    this.syncServer,
    this.scanBarcode = showBarcodeScannerDialog,
    this.pairWithMainDevice,
    this.pairWithMainDeviceAddress,
  });

  final DekonRepository repository;
  final LanSyncServer? syncServer;
  final BarcodeScanLauncher scanBarcode;
  final MainDevicePairer? pairWithMainDevice;
  final MainDeviceAddressPairer? pairWithMainDeviceAddress;

  @override
  State<DeviceSyncScreen> createState() => _DeviceSyncScreenState();
}

class _DeviceSyncScreenState extends State<DeviceSyncScreen> {
  late Future<DeviceRoleSettings> _roleFuture = widget.repository
      .deviceRoleSettings();
  late Future<List<CashierReportFilter>> _cashiersFuture = widget.repository
      .cashierReportFilters();
  DeviceRole? _role;
  bool? _roleLocked;
  var _serverBusy = false;
  String? _serverError;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(UiStrings.deviceSync)),
      body: FutureBuilder<DeviceRoleSettings>(
        future: _roleFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Device Sync could not load.'));
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
              if (role == DeviceRole.cashierDevice)
                _cashierDeviceContent(settings, locked)
              else
                _mainDeviceContent(),
            ],
          );
        },
      ),
    );
  }

  Widget _mainDeviceContent() {
    final server = widget.syncServer;
    if (server == null) {
      return const Text('Device Sync is unavailable on this device.');
    }
    final running = server.isRunning;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Main Device', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        const Text('This device stores the inventory database.'),
        const SizedBox(height: 20),
        FutureBuilder<List<CashierReportFilter>>(
          future: _cashiersFuture,
          builder: (context, snapshot) {
            final cashiers = snapshot.data ?? const <CashierReportFilter>[];
            return _connectedCashiers(cashiers);
          },
        ),
        const SizedBox(height: 16),
        if (_serverError != null) ...[
          _InlineStatus(
            icon: Icons.warning_amber,
            text: _serverError!,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 12),
        ],
        if (running) _activePairing(server) else _startPairingButton(),
        const SizedBox(height: 12),
        _technicalDetails(server),
      ],
    );
  }

  Widget _connectedCashiers(List<CashierReportFilter> cashiers) {
    final count = cashiers.length;
    final countLabel = count == 1
        ? '1 device connected'
        : '$count devices connected';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Connected Cashier Devices',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(countLabel, key: const Key('connected-cashier-count')),
        if (cashiers.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final cashier in cashiers)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.phone_android),
              title: Text(cashier.label),
              subtitle: const Text('Trusted cashier device'),
            ),
        ],
      ],
    );
  }

  Widget _startPairingButton() {
    return FilledButton.icon(
      key: const Key('device-sync-start-pairing-button'),
      onPressed: _serverBusy ? null : _startServer,
      icon: const Icon(Icons.qr_code_2),
      label: Text(
        _serverBusy ? 'Starting pairing' : UiStrings.connectAnotherDevice,
      ),
    );
  }

  Widget _activePairing(LanSyncServer server) {
    final qrData = server.pairingQrData;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Scan this QR code from the cashier device.'),
        if (qrData != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: QrImageView(
                key: const Key('sync-pairing-qr'),
                data: qrData,
                version: QrVersions.auto,
                size: 180,
                backgroundColor: Colors.white,
              ),
            ),
          ),
        FilledButton.icon(
          key: const Key('device-sync-stop-pairing-button'),
          onPressed: _serverBusy ? null : _stopServer,
          icon: const Icon(Icons.stop),
          label: const Text(UiStrings.stopPairing),
        ),
      ],
    );
  }

  Widget _technicalDetails(LanSyncServer server) {
    return ExpansionTile(
      key: const Key('device-sync-technical-details'),
      tilePadding: EdgeInsets.zero,
      title: const Text(UiStrings.technicalDetails),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SelectableText(
            server.serverUrl == null
                ? 'Start pairing to create a local address.'
                : 'Local address\n${server.serverUrl}',
            key: const Key('sync-server-url'),
          ),
        ),
      ],
    );
  }

  Widget _cashierDeviceContent(DeviceRoleSettings settings, bool locked) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Cashier Device', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        locked
            ? Text(_cashierConnectionText(settings.deviceDisplayName))
            : CashierPairingPanel(
                repository: widget.repository,
                scanBarcode: widget.scanBarcode,
                pairWithMainDevice: widget.pairWithMainDevice,
                pairWithMainDeviceAddress: widget.pairWithMainDeviceAddress,
                onPaired: _refreshRoleSettings,
              ),
      ],
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
    } catch (_) {
      _serverError =
          'Could not start pairing. Check that this device is connected to Wi-Fi.';
    } finally {
      if (mounted) {
        setState(() {
          _serverBusy = false;
          _cashiersFuture = widget.repository.cashierReportFilters();
        });
      }
    }
  }

  Future<void> _stopServer() async {
    setState(() {
      _serverBusy = true;
      _serverError = null;
    });
    try {
      await widget.syncServer!.stop();
    } catch (_) {
      _serverError = 'Could not stop pairing. Try again.';
    } finally {
      if (mounted) setState(() => _serverBusy = false);
    }
  }
}

class BackupRestoreScreen extends StatefulWidget {
  const BackupRestoreScreen({
    super.key,
    required this.repository,
    this.backupService,
    this.backupFiles = const BackupFileActions(),
  });

  final DekonRepository repository;
  final BackupRunner? backupService;
  final BackupFileActions backupFiles;

  @override
  State<BackupRestoreScreen> createState() => _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends State<BackupRestoreScreen> {
  var _backupBusy = false;
  var _backupNeedsRetry = false;
  DateTime? _lastSuccessfulBackupAt;
  String? _backupStatus;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(UiStrings.backupAndRestore)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Save a backup file so your store data can be recovered if this device is lost or replaced.',
          ),
          const SizedBox(height: 20),
          Text(
            'Last successful backup',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(_lastBackupText, key: const Key('last-successful-backup')),
          if (_backupStatus != null) ...[
            const SizedBox(height: 16),
            Text(_backupStatus!, key: const Key('backup-status')),
          ],
          if (_backupNeedsRetry) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('retry-backup'),
              onPressed: _backupBusy ? null : _saveBackup,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry Backup'),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            key: const Key('save-backup'),
            onPressed: _backupBusy ? null : _saveBackup,
            icon: const Icon(Icons.save_alt),
            label: Text(_backupBusy ? 'Working' : UiStrings.saveBackup),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('restore-backup'),
            onPressed: _backupBusy ? null : _restoreBackup,
            icon: const Icon(Icons.restore),
            label: const Text(UiStrings.restoreBackup),
          ),
        ],
      ),
    );
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
      draft.savedAs(path: savedFile.path, fileName: savedFile.fileName);
      _lastSuccessfulBackupAt = DateTime.now();
      _backupStatus =
          '${UiStrings.backupSavedSuccessfully}: ${savedFile.fileName}';
      _message(UiStrings.backupSavedSuccessfully);
    } on BackupException {
      _markBackupFailed();
    } on BackupStorageException {
      _markBackupFailed();
    } catch (_) {
      _markBackupFailed();
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
      final result = await _importBackup(file.contents);
      _backupStatus = result.duplicateCount == 0
          ? UiStrings.backupRestoredSuccessfully
          : '${UiStrings.backupRestoredSuccessfully}. Skipped ${result.duplicateCount} duplicate records.';
      _message(UiStrings.backupRestoredSuccessfully);
    } on BackupException catch (error) {
      _backupStatus = 'Could not restore the backup.\n${error.message}';
    } catch (_) {
      _backupStatus =
          'Could not restore the backup.\nChoose a valid Dekon backup file and try again.';
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  Future<BackupImportResult> _importBackup(String contents) {
    final injected = widget.backupService;
    if (injected != null) return injected.importBackup(contents);
    return widget.repository.restoreBackup(contents);
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
          'Current store data may be replaced by the selected backup file.\n\n'
          '${file.name}\n'
          '${preview.eventCount} records\n'
          'Made ${_timestamp(preview.exportedAt)}',
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

  String get _lastBackupText {
    final lastBackup = _lastSuccessfulBackupAt;
    if (lastBackup == null) return 'No backup saved in this session';
    return _timestamp(lastBackup);
  }

  void _markBackupFailed() {
    _backupNeedsRetry = true;
    _backupStatus =
        'Could not save the backup.\nChoose another folder or check that the selected location is writable.';
  }

  String _timestamp(DateTime dateTime) {
    return dateTime.toLocal().toString().split('.').first;
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

class _SettingsSectionTile extends StatelessWidget {
  const _SettingsSectionTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        minVerticalPadding: 12,
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _InlineStatus extends StatelessWidget {
  const _InlineStatus({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: TextStyle(color: color)),
        ),
      ],
    );
  }
}
