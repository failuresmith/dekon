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
            body: Center(child: Text('Startup failed: ${snapshot.error}')),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dekon'),
        actions: [_settingsAction(settings)],
      ),
      body: items[index].screen,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: [for (final item in items) item.destination],
      ),
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
          tooltip: 'Settings',
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
    final role = settings.role;
    final items = [
      _NavigationItem(
        screen: TransactionScreen(
          repository: widget.repository,
          mode: TransactionMode.sell,
          scanBarcode: widget.scanBarcode,
        ),
        destination: const NavigationDestination(
          icon: Icon(Icons.point_of_sale),
          label: 'Sell',
        ),
      ),
      _NavigationItem(
        screen: TransactionScreen(
          repository: widget.repository,
          mode: TransactionMode.buy,
          scanBarcode: widget.scanBarcode,
        ),
        destination: const NavigationDestination(
          icon: Icon(Icons.add_business),
          label: 'Buy',
        ),
      ),
    ];
    if (role == DeviceRole.mainDevice || settings.locked) {
      items.add(
        _NavigationItem(
          screen: InventoryScreen(repository: widget.repository),
          destination: const NavigationDestination(
            icon: Icon(Icons.inventory_2),
            label: 'Inventory',
          ),
        ),
      );
    }
    items.add(
      _NavigationItem(
        screen: ReportsScreen(
          repository: widget.repository,
          scope: role == DeviceRole.cashierDevice
              ? ReportScope.localDevice
              : ReportScope.allDevices,
        ),
        destination: const NavigationDestination(
          icon: Icon(Icons.bar_chart),
          label: 'Reports',
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
          appBar: AppBar(title: const Text('Settings')),
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
  const _NavigationItem({required this.screen, required this.destination});

  final Widget screen;
  final NavigationDestination destination;
}
