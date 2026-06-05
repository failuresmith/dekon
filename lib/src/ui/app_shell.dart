import 'dart:async';

import 'package:flutter/material.dart';

import '../application/application.dart';
import 'barcode_scanner_dialog.dart';
import 'cashier_pairing_panel.dart';
import 'cashier_sync_indicator.dart';
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
    this.pairWithMainDevice,
    this.pairWithMainDeviceAddress,
  });

  final DekonRepository repository;
  final BarcodeScanLauncher scanBarcode;
  final MainDevicePairer? pairWithMainDevice;
  final MainDeviceAddressPairer? pairWithMainDeviceAddress;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  var _index = 0;
  var _onboardingCompletedLocally = false;
  late final _syncServer = widget.repository.createLanSyncServer();
  late Future<DeviceRoleSettings> _roleSettings = widget.repository
      .deviceRoleSettings();

  @override
  void dispose() {
    unawaited(_syncServer.stop());
    super.dispose();
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
            onCompleted: _reloadRoleSettings,
          );
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
            child: CashierSyncIndicator(repository: widget.repository),
          ),
        if (showMainCashierIndicator)
          IgnorePointer(
            child: MainCashierConnectionIndicator(
              repository: widget.repository,
            ),
          ),
      ],
    );
  }

  List<_NavigationItem> _navigationItems(DeviceRoleSettings settings) {
    final strings = context.strings;
    final role = settings.role;
    final items = [
      _NavigationItem(
        tab: MainTab.sell,
        title: strings.sell,
        screen: TransactionScreen(
          key: const ValueKey('sell-screen'),
          repository: widget.repository,
          mode: TransactionMode.sell,
          scanBarcode: widget.scanBarcode,
        ),
        historyMode: TransactionMode.sell,
        destination: const NavigationDestination(
          icon: Icon(Icons.point_of_sale_outlined),
          selectedIcon: Icon(Icons.point_of_sale),
          label: '',
        ),
      ),
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
        destination: const NavigationDestination(
          icon: Icon(Icons.add_business_outlined),
          selectedIcon: Icon(Icons.add_business),
          label: '',
        ),
      ),
    ];
    items[0] = items[0].copyWithDestinationLabel(strings.sell);
    items[1] = items[1].copyWithDestinationLabel(strings.restock);
    if (role == DeviceRole.mainDevice || settings.locked) {
      items.add(
        _NavigationItem(
          tab: MainTab.inventory,
          title: strings.inventory,
          screen: InventoryScreen(
            key: const ValueKey('inventory-screen'),
            repository: widget.repository,
            scanBarcode: widget.scanBarcode,
          ),
          destination: NavigationDestination(
            icon: const Icon(Icons.inventory_2_outlined),
            selectedIcon: const Icon(Icons.inventory_2),
            label: strings.inventory,
          ),
        ),
      );
    }
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

  void _reloadRoleSettings() {
    setState(() {
      _onboardingCompletedLocally = true;
      _roleSettings = widget.repository.deviceRoleSettings();
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
            scanBarcode: widget.scanBarcode,
            pairWithMainDevice: widget.pairWithMainDevice,
            pairWithMainDeviceAddress: widget.pairWithMainDeviceAddress,
          ),
        ),
      ),
    );
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
