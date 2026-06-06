import 'dart:async';

import 'package:flutter/material.dart';

import '../application/application.dart';
import '../backup/backup.dart';
import '../sync/sync.dart';
import 'barcode_scanner_dialog.dart';
import 'cashier_pairing_panel.dart';
import 'cashier_sync_indicator.dart';
import 'cashier_sync_status.dart';
import 'device_onboarding_screen.dart';
import 'inventory_screen.dart';
import 'main_cashier_connection_indicator.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';
import 'transaction_screen.dart';
import 'ui_strings.dart';

enum MainTab { sell, restock, inventory, reports }

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.repository,
    this.scanBarcode = showBarcodeScannerDialog,
    this.backupService,
    this.backupFiles = const BackupFileActions(),
    this.pairWithMainDevice,
    this.pairWithMainDeviceAddress,
    this.syncServiceDiscovery = const NoopSyncServiceDiscovery(),
  });

  final DekonRepository repository;
  final BarcodeScanLauncher scanBarcode;
  final BackupRunner? backupService;
  final BackupFileActions backupFiles;
  final MainDevicePairer? pairWithMainDevice;
  final MainDeviceAddressPairer? pairWithMainDeviceAddress;
  final SyncServiceDiscovery syncServiceDiscovery;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  var _index = 0;
  var _onboardingCompletedLocally = false;
  late final _syncServer = widget.repository.createLanSyncServer(
    serviceDiscovery: widget.syncServiceDiscovery,
  );
  late Future<DeviceRoleSettings> _roleSettings = widget.repository
      .deviceRoleSettings();
  StreamSubscription<void>? _syncStateSubscription;
  var _startingSyncServer = false;
  var _cashierSyncStatus = CashierSyncStatus.disconnected;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncStateSubscription = widget.repository.syncStateChanged.listen((_) {
      if (mounted) _reloadRoleSettings(preserveOnboardingFlag: true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final syncStateSubscription = _syncStateSubscription;
    if (syncStateSubscription != null) {
      unawaited(syncStateSubscription.cancel());
    }
    unawaited(_syncServer.stop());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _syncServer.isRunning) {
      unawaited(_syncServer.refreshDiscoveryAdvertisement());
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DeviceRoleSettings>(
      future: _roleSettings,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Dekon')),
            body: Center(
              child: Text(context.strings.startupFailed(snapshot.error!)),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final settings = snapshot.requireData;
        final onboardingCompleted =
            settings.onboardingCompleted || _onboardingCompletedLocally;
        if (!onboardingCompleted) {
          return DeviceOnboardingScreen(
            repository: widget.repository,
            initialSettings: settings,
            scanBarcode: widget.scanBarcode,
            pairWithMainDevice: widget.pairWithMainDevice,
            pairWithMainDeviceAddress: widget.pairWithMainDeviceAddress,
            syncServiceDiscovery: widget.syncServiceDiscovery,
            onCompleted: _reloadRoleSettings,
          );
        }
        if (settings.cashierUnpairBackupRequired) {
          return CashierUnpairRecoveryScreen(
            repository: widget.repository,
            backupService: widget.backupService,
            backupFiles: widget.backupFiles,
            onReset: _returnToCashierPairing,
          );
        }
        if (settings.role == DeviceRole.mainDevice &&
            settings.mainSyncServerEnabled) {
          _ensureMainSyncServerStarted();
        }
        return _appScaffold(settings);
      },
    );
  }

  Widget _appScaffold(DeviceRoleSettings settings) {
    final items = _navigationItems(settings);
    final index = _index >= items.length ? items.length - 1 : _index;
    final selectedItem = items[index];
    return Scaffold(
      appBar: AppBar(
        title: Text(selectedItem.title),
        actions: [
          if (selectedItem.historyMode != null)
            _historyAction(selectedItem.historyMode!),
          _settingsAction(settings),
        ],
      ),
      body: IndexedStack(
        index: index,
        children: [
          for (final item in items)
            KeyedSubtree(key: ValueKey(item.tab), child: item.screen),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: [for (final item in items) item.destination],
      ),
    );
  }

  Widget _historyAction(TransactionMode mode) {
    final strings = context.strings;
    final isSell = mode == TransactionMode.sell;
    return IconButton(
      key: Key(isSell ? 'sell-history' : 'restock-history'),
      tooltip: isSell ? strings.saleHistory : strings.restockHistory,
      onPressed: () => showTransactionHistoryDialog(
        context: context,
        repository: widget.repository,
        mode: mode,
      ),
      icon: const Icon(Icons.history),
    );
  }

  Widget _settingsAction(DeviceRoleSettings settings) {
    final showCashierSyncIndicator =
        settings.role == DeviceRole.cashierDevice && settings.locked;
    final showMainCashierIndicator = settings.role == DeviceRole.mainDevice;
    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          key: const Key('open-settings'),
          tooltip: context.strings.settings,
          onPressed: _openSettings,
          icon: const Icon(Icons.settings),
        ),
        if (showCashierSyncIndicator)
          IgnorePointer(
            child: CashierSyncIndicator(
              repository: widget.repository,
              syncServiceDiscovery: widget.syncServiceDiscovery,
              onStatusChanged: _setCashierSyncStatus,
            ),
          ),
        if (showMainCashierIndicator)
          IgnorePointer(
            child: MainCashierConnectionIndicator(
              repository: widget.repository,
              isCashierConnected: _hasLiveCashierConnection,
            ),
          ),
      ],
    );
  }

  List<_NavigationItem> _navigationItems(DeviceRoleSettings settings) {
    final strings = context.strings;
    final role = settings.role;
    final isCashier = role == DeviceRole.cashierDevice;
    final items = [
      _NavigationItem(
        tab: MainTab.sell,
        title: strings.sell,
        screen: TransactionScreen(
          key: const ValueKey('sell-screen'),
          repository: widget.repository,
          mode: TransactionMode.sell,
          scanBarcode: widget.scanBarcode,
          cashierSyncStatus: isCashier && settings.locked
              ? _cashierSyncStatus
              : null,
        ),
        historyMode: TransactionMode.sell,
        destination: const NavigationDestination(
          icon: Icon(Icons.point_of_sale_outlined),
          selectedIcon: Icon(Icons.point_of_sale),
          label: '',
        ),
      ),
    ];
    items[0] = items[0].copyWithDestinationLabel(strings.sell);
    if (!isCashier) {
      items.add(
        _NavigationItem(
          tab: MainTab.restock,
          title: strings.restock,
          screen: TransactionScreen(
            key: const ValueKey('restock-screen'),
            repository: widget.repository,
            mode: TransactionMode.buy,
            scanBarcode: widget.scanBarcode,
          ),
          historyMode: TransactionMode.buy,
          destination: NavigationDestination(
            icon: const Icon(Icons.add_business_outlined),
            selectedIcon: const Icon(Icons.add_business),
            label: strings.restock,
          ),
        ),
      );
    }
    if (role == DeviceRole.mainDevice || settings.locked) {
      items.add(
        _NavigationItem(
          tab: MainTab.inventory,
          title: strings.inventory,
          screen: InventoryScreen(
            key: const ValueKey('inventory-screen'),
            repository: widget.repository,
            scanBarcode: widget.scanBarcode,
            readOnly: isCashier,
          ),
          destination: NavigationDestination(
            icon: const Icon(Icons.inventory_2_outlined),
            selectedIcon: const Icon(Icons.inventory_2),
            label: strings.inventory,
          ),
        ),
      );
    }
    if (isCashier) return items;
    final reportScope = role == DeviceRole.cashierDevice
        ? ReportScope.localDevice
        : ReportScope.allDevices;
    items.add(
      _NavigationItem(
        tab: MainTab.reports,
        title: reportScope == ReportScope.localDevice
            ? strings.thisDeviceReports
            : strings.reports,
        screen: ReportsScreen(
          key: const ValueKey('reports-screen'),
          repository: widget.repository,
          scope: reportScope,
        ),
        destination: NavigationDestination(
          icon: const Icon(Icons.bar_chart_outlined),
          selectedIcon: const Icon(Icons.bar_chart),
          label: strings.reports,
        ),
      ),
    );
    return items;
  }

  void _reloadRoleSettings({bool preserveOnboardingFlag = false}) {
    setState(() {
      _onboardingCompletedLocally = preserveOnboardingFlag
          ? _onboardingCompletedLocally
          : true;
      _roleSettings = widget.repository.deviceRoleSettings();
    });
  }

  void _returnToCashierPairing() {
    setState(() {
      _index = 0;
      _cashierSyncStatus = CashierSyncStatus.disconnected;
      _onboardingCompletedLocally = false;
      _roleSettings = widget.repository.deviceRoleSettings();
    });
  }

  void _setCashierSyncStatus(CashierSyncStatus status) {
    if (!mounted || _cashierSyncStatus == status) return;
    setState(() => _cashierSyncStatus = status);
  }

  Future<bool> _hasLiveCashierConnection() async {
    if (!_syncServer.isRunning) return false;
    final peers = await widget.repository.createSyncStore().trustedPeers();
    return peers.any((peer) => _syncServer.isCashierConnected(peer.deviceId));
  }

  void _ensureMainSyncServerStarted() {
    if (_syncServer.isRunning || _startingSyncServer) return;
    _startingSyncServer = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _startingSyncServer = false;
        return;
      }
      try {
        await _syncServer.start(enablePairing: false);
      } catch (_) {
        // Device Sync surfaces the manual retry path and user-facing error.
      } finally {
        _startingSyncServer = false;
      }
    });
  }

  Future<void> _openSettings() {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          appBar: AppBar(title: Text(context.strings.settings)),
          body: SettingsScreen(
            repository: widget.repository,
            syncServer: _syncServer,
            backupService: widget.backupService,
            backupFiles: widget.backupFiles,
            scanBarcode: widget.scanBarcode,
            pairWithMainDevice: widget.pairWithMainDevice,
            pairWithMainDeviceAddress: widget.pairWithMainDeviceAddress,
            syncServiceDiscovery: widget.syncServiceDiscovery,
          ),
        ),
      ),
    );
  }
}

class CashierUnpairRecoveryScreen extends StatefulWidget {
  const CashierUnpairRecoveryScreen({
    super.key,
    required this.repository,
    this.backupService,
    this.backupFiles = const BackupFileActions(),
    required this.onReset,
  });

  final DekonRepository repository;
  final BackupRunner? backupService;
  final BackupFileActions backupFiles;
  final VoidCallback onReset;

  @override
  State<CashierUnpairRecoveryScreen> createState() =>
      _CashierUnpairRecoveryScreenState();
}

class _CashierUnpairRecoveryScreenState
    extends State<CashierUnpairRecoveryScreen> {
  var _busy = false;
  var _startedAutomatically = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _startedAutomatically) return;
      _startedAutomatically = true;
      unawaited(_backupAndReset());
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Scaffold(
      appBar: AppBar(title: Text(strings.cashierUnpairedTitle)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            strings.cashierUnpairedTitle,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(strings.cashierUnpairedHelp),
          if (_status != null) ...[
            const SizedBox(height: 12),
            Text(_status!, key: const Key('cashier-unpair-status')),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            key: const Key('cashier-unpair-backup-reset'),
            onPressed: _busy ? null : _backupAndReset,
            icon: const Icon(Icons.save_alt),
            label: Text(
              _busy ? strings.working : strings.backupSaleHistoryAndReset,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _backupAndReset() async {
    final strings = context.strings;
    setState(() {
      _busy = true;
      _status = strings.backingUpSaleHistory;
    });
    BackupExportDraft? draft;
    final backupService =
        widget.backupService ?? widget.repository.createBackupService();
    try {
      draft = await backupService.prepareExport();
      final savedFile = await widget.backupFiles.saveExportedBackup(
        sourcePath: draft.path,
        fileName: draft.fileName,
      );
      if (savedFile == null) {
        if (mounted) {
          setState(() => _status = strings.backupRequiredBeforeReset);
        }
        return;
      }
      await widget.repository.resetCashierAfterUnpairBackup();
      if (!mounted) return;
      setState(() => _status = strings.cashierResetReadyToPair);
      widget.onReset();
    } catch (_) {
      if (mounted) setState(() => _status = strings.backupRequiredBeforeReset);
    } finally {
      if (draft != null) await backupService.discardPreparedExport(draft);
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _NavigationItem {
  const _NavigationItem({
    required this.tab,
    required this.title,
    required this.screen,
    required this.destination,
    this.historyMode,
  });

  final MainTab tab;
  final String title;
  final Widget screen;
  final NavigationDestination destination;
  final TransactionMode? historyMode;

  _NavigationItem copyWithDestinationLabel(String label) {
    return _NavigationItem(
      tab: tab,
      title: title,
      screen: screen,
      historyMode: historyMode,
      destination: NavigationDestination(
        icon: destination.icon,
        selectedIcon: destination.selectedIcon,
        label: label,
      ),
    );
  }
}
