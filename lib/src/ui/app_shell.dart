import 'dart:async';

import 'package:flutter/material.dart';

import '../application/application.dart';
import 'add_product_screen.dart';
import 'barcode_scanner_dialog.dart';
import 'cashier_pairing_panel.dart';
import 'device_onboarding_screen.dart';
import 'inventory_screen.dart';
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
        return _appScaffold();
      },
    );
  }

  Widget _appScaffold() {
    final screens = [
      TransactionScreen(
        repository: widget.repository,
        mode: TransactionMode.sell,
        scanBarcode: widget.scanBarcode,
      ),
      TransactionScreen(
        repository: widget.repository,
        mode: TransactionMode.buy,
        scanBarcode: widget.scanBarcode,
      ),
      AddProductScreen(repository: widget.repository),
      InventoryScreen(repository: widget.repository),
      ReportsScreen(repository: widget.repository),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dekon'),
        actions: [
          IconButton(
            key: const Key('open-settings'),
            tooltip: 'Settings',
            onPressed: _openSettings,
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: screens[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.point_of_sale), label: 'Sell'),
          NavigationDestination(icon: Icon(Icons.add_business), label: 'Buy'),
          NavigationDestination(icon: Icon(Icons.add_box), label: 'Add'),
          NavigationDestination(
            icon: Icon(Icons.inventory_2),
            label: 'Inventory',
          ),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Reports'),
        ],
      ),
    );
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
