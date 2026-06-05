import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../application/application.dart';
import '../backup/backup.dart';
import '../platform/external_link_actions.dart';
import '../sync/sync.dart';
import 'barcode_scanner_dialog.dart';
import 'cashier_pairing_panel.dart';
import 'sync_peer_messages_dialog.dart';
import 'ui_strings.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.repository,
    this.syncServer,
    this.backupService,
    this.backupFiles = const BackupFileActions(),
    this.openExternalLink = openExternalHttpsLink,
    this.scanBarcode = showBarcodeScannerDialog,
    this.pairWithMainDevice,
    this.pairWithMainDeviceAddress,
  });

  final DekonRepository repository;
  final LanSyncServer? syncServer;
  final BackupRunner? backupService;
  final BackupFileActions backupFiles;
  final ExternalLinkLauncher openExternalLink;
  final BarcodeScanLauncher scanBarcode;
  final MainDevicePairer? pairWithMainDevice;
  final MainDeviceAddressPairer? pairWithMainDeviceAddress;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final languageController = AppLanguageScope.controllerOf(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SettingsSectionTile(
          key: const Key('settings-language-tile'),
          title: strings.languageLabel,
          subtitle: strings.languageSubtitle(languageController.language),
          icon: Icons.language,
          onTap: () => _openLanguage(context),
        ),
        const SizedBox(height: 12),
        _SettingsSectionTile(
          key: const Key('settings-device-sync-tile'),
          title: strings.deviceSync,
          subtitle: strings.settingsDeviceSyncSubtitle,
          icon: Icons.sync_alt,
          onTap: () => _openDeviceSync(context),
        ),
        const SizedBox(height: 12),
        _SettingsSectionTile(
          key: const Key('settings-backup-restore-tile'),
          title: strings.backupAndRestore,
          subtitle: strings.settingsBackupRestoreSubtitle,
          icon: Icons.backup_outlined,
          onTap: () => _openBackupRestore(context),
        ),
        const SizedBox(height: 12),
        _SettingsSectionTile(
          key: const Key('settings-about-tile'),
          title: strings.about,
          icon: Icons.info_outline,
          onTap: () => _openAbout(context),
        ),
      ],
    );
  }

  Future<void> _openLanguage(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (context) => const LanguageScreen()),
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

  Future<void> _openAbout(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => AboutScreen(openExternalLink: openExternalLink),
      ),
    );
  }
}

class LanguageScreen extends StatefulWidget {
  const LanguageScreen({super.key});

  @override
  State<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends State<LanguageScreen> {
  var _saving = false;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final controller = AppLanguageScope.controllerOf(context);
    return Scaffold(
      appBar: AppBar(title: Text(strings.languageLabel)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(strings.chooseLanguage),
          const SizedBox(height: 8),
          for (final language in AppLanguage.values)
            ListTile(
              key: Key('language-option-${language.storageValue}'),
              title: Text(strings.languageChoiceLabel(language)),
              leading: Icon(
                controller.language == language
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              selected: controller.language == language,
              enabled: !_saving,
              onTap: _saving ? null : () => _setLanguage(language),
            ),
        ],
      ),
    );
  }

  Future<void> _setLanguage(AppLanguage? language) async {
    if (language == null) return;
    final strings = context.strings;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await AppLanguageScope.controllerOf(context).setLanguage(language);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(context.strings.languageSaved)),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(strings.languageSaveFailed)),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key, this.openExternalLink = openExternalHttpsLink});

  static final _aboutUri = Uri.parse('https://ble.ir/dekon');

  final ExternalLinkLauncher openExternalLink;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Scaffold(
      appBar: AppBar(title: Text(strings.about)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const Key('about-link'),
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                padding: EdgeInsets.zero,
              ),
              onPressed: () {
                _openLink(context);
              },
              child: Text(strings.aboutUrl),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openLink(BuildContext context) async {
    try {
      await openExternalLink(_aboutUri);
    } on ExternalLinkException {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.strings.aboutLinkError)));
    }
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
      appBar: AppBar(title: Text(context.strings.deviceSync)),
      body: FutureBuilder<DeviceRoleSettings>(
        future: _roleFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text(context.strings.deviceSyncCouldNotLoad));
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
      return Text(context.strings.deviceSyncUnavailable);
    }
    final running = server.isRunning;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.strings.mainDevice,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(context.strings.thisDeviceStoresInventoryDatabase),
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
    final strings = context.strings;
    final countLabel = strings.connectedDeviceCount(count);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.connectedCashierDevices,
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
              subtitle: Text(strings.trustedCashierDevice),
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
        _serverBusy
            ? context.strings.startingPairing
            : context.strings.connectAnotherDevice,
      ),
    );
  }

  Widget _activePairing(LanSyncServer server) {
    final qrData = server.pairingQrData;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(context.strings.scanQrFromCashier),
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
          label: Text(context.strings.stopPairing),
        ),
      ],
    );
  }

  Widget _technicalDetails(LanSyncServer server) {
    return ExpansionTile(
      key: const Key('device-sync-technical-details'),
      tilePadding: EdgeInsets.zero,
      title: Text(context.strings.technicalDetails),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SelectableText(
            server.serverUrl == null
                ? context.strings.startPairingToCreateLocalAddress
                : context.strings.localAddress(server.serverUrl!),
            key: const Key('sync-server-url'),
          ),
        ),
        const SizedBox(height: 12),
        _peerMessagesButton(),
      ],
    );
  }

  Widget _cashierTechnicalDetails() {
    return ExpansionTile(
      key: const Key('cashier-sync-technical-details'),
      tilePadding: EdgeInsets.zero,
      title: Text(context.strings.technicalDetails),
      children: [_peerMessagesButton()],
    );
  }

  Widget _peerMessagesButton() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: OutlinedButton.icon(
          key: const Key('sync-peer-messages-button'),
          onPressed: () {
            showSyncPeerMessagesDialog(
              context: context,
              repository: widget.repository,
            );
          },
          icon: const Icon(Icons.bug_report_outlined),
          label: Text(context.strings.peerMessages),
        ),
      ),
    );
  }

  Widget _cashierDeviceContent(DeviceRoleSettings settings, bool locked) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.strings.cashierDevice,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        locked
            ? Text(
                context.strings.cashierConnectionText(
                  settings.deviceDisplayName,
                ),
              )
            : CashierPairingPanel(
                repository: widget.repository,
                scanBarcode: widget.scanBarcode,
                pairWithMainDevice: widget.pairWithMainDevice,
                pairWithMainDeviceAddress: widget.pairWithMainDeviceAddress,
                onPaired: _refreshRoleSettings,
              ),
        const SizedBox(height: 16),
        _cashierTechnicalDetails(),
      ],
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
    final strings = context.strings;
    setState(() {
      _serverBusy = true;
      _serverError = null;
    });
    try {
      await widget.syncServer!.start();
    } catch (_) {
      _serverError = strings.couldNotStartPairing;
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
    final strings = context.strings;
    setState(() {
      _serverBusy = true;
      _serverError = null;
    });
    try {
      await widget.syncServer!.stop();
    } catch (_) {
      _serverError = strings.couldNotStopPairing;
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
      appBar: AppBar(title: Text(context.strings.backupAndRestore)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(context.strings.backupHelp),
          const SizedBox(height: 20),
          Text(
            context.strings.lastSuccessfulBackup,
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
              label: Text(context.strings.retryBackup),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            key: const Key('save-backup'),
            onPressed: _backupBusy ? null : _saveBackup,
            icon: const Icon(Icons.save_alt),
            label: Text(
              _backupBusy
                  ? context.strings.working
                  : context.strings.saveBackup,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('restore-backup'),
            onPressed: _backupBusy ? null : _restoreBackup,
            icon: const Icon(Icons.restore),
            label: Text(context.strings.restoreBackup),
          ),
        ],
      ),
    );
  }

  Future<void> _saveBackup() async {
    final strings = context.strings;
    final messenger = ScaffoldMessenger.of(context);
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
          '${strings.backupSavedSuccessfully}: ${savedFile.fileName}';
      _message(messenger, strings.backupSavedSuccessfully);
    } on BackupException {
      _markBackupFailed(strings);
    } on BackupStorageException {
      _markBackupFailed(strings);
    } catch (_) {
      _markBackupFailed(strings);
    } finally {
      if (draft != null) await _backupService.discardPreparedExport(draft);
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  Future<void> _restoreBackup() async {
    final strings = context.strings;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _backupBusy = true;
      _backupNeedsRetry = false;
      _backupStatus = null;
    });
    try {
      final file = await widget.backupFiles.chooseImportFile();
      if (file == null) return;
      final preview = await _backupService.preview(file.contents);
      if (!mounted) return;
      final confirmed = await _confirmRestore(file, preview, strings);
      if (confirmed != true) return;
      final result = await _importBackup(file.contents);
      _backupStatus = result.duplicateCount == 0
          ? strings.backupRestoredSuccessfully
          : strings.backupRestoredWithSkippedDuplicates(result.duplicateCount);
      _message(messenger, strings.backupRestoredSuccessfully);
    } on BackupException catch (error) {
      _backupStatus = strings.couldNotRestoreBackup(error.message);
    } catch (_) {
      _backupStatus = strings.couldNotRestoreBackup(
        strings.chooseValidBackupFile,
      );
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

  Future<bool?> _confirmRestore(
    BackupImportFile file,
    BackupPreview preview,
    UiStrings strings,
  ) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.restoreBackupQuestion),
        content: Text(
          strings.restoreBackupPreview(
            fileName: file.name,
            recordCount: preview.eventCount,
            exportedAt: _timestamp(preview.exportedAt),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            key: const Key('confirm-restore-backup'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(strings.restore),
          ),
        ],
      ),
    );
  }

  String get _lastBackupText {
    final lastBackup = _lastSuccessfulBackupAt;
    if (lastBackup == null) return context.strings.noBackupSavedInThisSession;
    return _timestamp(lastBackup);
  }

  void _markBackupFailed(UiStrings strings) {
    _backupNeedsRetry = true;
    _backupStatus = strings.couldNotSaveBackup;
  }

  String _timestamp(DateTime dateTime) {
    return dateTime.toLocal().toString().split('.').first;
  }

  void _message(ScaffoldMessengerState messenger, String text) {
    messenger.showSnackBar(SnackBar(content: Text(text)));
  }
}

class _SettingsSectionTile extends StatelessWidget {
  const _SettingsSectionTile({
    super.key,
    required this.title,
    required this.icon,
    required this.onTap,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
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
        subtitle: subtitle == null ? null : Text(subtitle!),
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
