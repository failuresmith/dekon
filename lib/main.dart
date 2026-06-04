import 'package:flutter/material.dart';

import 'src/app_config.dart';
import 'src/application/application.dart';
import 'src/ui/app_shell.dart';
import 'src/ui/barcode_scanner_dialog.dart';

typedef RepositoryFactory = Future<DekonRepository> Function();

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key, this.repositoryFactory, this.scanBarcode});

  final RepositoryFactory? repositoryFactory;
  final BarcodeScanLauncher? scanBarcode;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F766E)),
        useMaterial3: true,
      ),
      home: _RepositoryLoader(
        repositoryFactory: repositoryFactory ?? DekonRepository.open,
        scanBarcode: scanBarcode ?? showBarcodeScannerDialog,
      ),
    );
  }
}

class _RepositoryLoader extends StatefulWidget {
  const _RepositoryLoader({
    required this.repositoryFactory,
    required this.scanBarcode,
  });

  final RepositoryFactory repositoryFactory;
  final BarcodeScanLauncher scanBarcode;

  @override
  State<_RepositoryLoader> createState() => _RepositoryLoaderState();
}

class _RepositoryLoaderState extends State<_RepositoryLoader> {
  late final Future<DekonRepository> _repository = widget.repositoryFactory();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DekonRepository>(
      future: _repository,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text(AppConfig.appName)),
            body: Center(child: Text('Startup failed: ${snapshot.error}')),
          );
        }
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return AppShell(
          repository: snapshot.requireData,
          scanBarcode: widget.scanBarcode,
        );
      },
    );
  }
}
