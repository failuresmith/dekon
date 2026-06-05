import 'package:flutter/material.dart';

import 'src/app_config.dart';
import 'src/application/application.dart';
import 'src/ui/app_shell.dart';
import 'src/ui/barcode_scanner_dialog.dart';
import 'src/ui/cashier_pairing_panel.dart';
import 'src/ui/ui_strings.dart';

typedef RepositoryFactory = Future<DekonRepository> Function();

void main() {
  runApp(const MainApp());
}

class MainApp extends StatefulWidget {
  const MainApp({
    super.key,
    this.repositoryFactory,
    this.scanBarcode,
    this.pairWithMainDevice,
    this.pairWithMainDeviceAddress,
  });

  final RepositoryFactory? repositoryFactory;
  final BarcodeScanLauncher? scanBarcode;
  final MainDevicePairer? pairWithMainDevice;
  final MainDeviceAddressPairer? pairWithMainDeviceAddress;

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  late final Future<_AppStartup> _startup = _openStartup();
  _AppStartup? _startupData;

  @override
  void dispose() {
    _startupData?.languageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AppStartup>(
      future: _startup,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return MaterialApp(
            title: AppConfig.appName,
            theme: _theme(),
            home: Scaffold(
              appBar: AppBar(title: const Text(AppConfig.appName)),
              body: Center(
                child: Text(
                  UiStrings.forLanguage(
                    AppLanguage.english,
                  ).startupFailed(snapshot.error!),
                ),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return MaterialApp(
            title: AppConfig.appName,
            theme: _theme(),
            home: const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        final startup = _startupData ??= snapshot.requireData;
        return AnimatedBuilder(
          animation: startup.languageController,
          builder: (context, _) {
            final strings = startup.languageController.strings;
            return MaterialApp(
              title: AppConfig.appName,
              theme: _theme(),
              builder: (context, child) => AppLanguageScope(
                controller: startup.languageController,
                child: Directionality(
                  textDirection: strings.textDirection,
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
              home: AppShell(
                repository: startup.repository,
                scanBarcode: widget.scanBarcode ?? showBarcodeScannerDialog,
                pairWithMainDevice: widget.pairWithMainDevice,
                pairWithMainDeviceAddress: widget.pairWithMainDeviceAddress,
              ),
            );
          },
        );
      },
    );
  }

  Future<_AppStartup> _openStartup() async {
    final repository =
        await (widget.repositoryFactory ?? DekonRepository.open)();
    final language = await repository.appLanguage();
    final languageController = AppLanguageController(
      initialLanguage: language,
      saveLanguage: repository.setAppLanguage,
    );
    return _AppStartup(
      repository: repository,
      languageController: languageController,
    );
  }

  ThemeData _theme() {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F766E)),
      useMaterial3: true,
    );
  }
}

class _AppStartup {
  const _AppStartup({
    required this.repository,
    required this.languageController,
  });

  final DekonRepository repository;
  final AppLanguageController languageController;
}
