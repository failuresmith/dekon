import 'package:flutter/material.dart';

import '../application/application.dart';
import 'barcode_scanner_dialog.dart';
import 'reports_screen.dart';
import 'transaction_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.repository,
    this.scanBarcode = showBarcodeScannerDialog,
  });

  final DekonRepository repository;
  final BarcodeScanLauncher scanBarcode;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  var _index = 0;

  @override
  Widget build(BuildContext context) {
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
      ReportsScreen(repository: widget.repository),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Dekon')),
      body: screens[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.point_of_sale), label: 'Sell'),
          NavigationDestination(icon: Icon(Icons.add_business), label: 'Buy'),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Reports'),
        ],
      ),
    );
  }
}
