import 'package:flutter/material.dart';

import 'src/app_config.dart';
import 'src/application/application.dart';
import 'src/backup/backup.dart';
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
    this.backupFiles = const BackupFileActions(),
    this.pairWithMainDevice,
    this.pairWithMainDeviceAddress,
  });

  final RepositoryFactory? repositoryFactory;
  final BarcodeScanLauncher? scanBarcode;
  final BackupFileActions backupFiles;
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
          final strings = UiStrings.forLanguage(AppLanguage.defaultLanguage);
          return MaterialApp(
            title: AppConfig.appName,
            theme: _theme(),
            builder: (context, child) => Directionality(
              textDirection: strings.textDirection,
              child: child ?? const SizedBox.shrink(),
            ),
            home: Scaffold(
              appBar: AppBar(title: const Text(AppConfig.appName)),
              body: Center(child: Text(strings.startupFailed(snapshot.error!))),
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
              theme: _theme(language: strings.language),
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
                backupFiles: widget.backupFiles,
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
    final moneyUnit = await repository.appMoneyUnit();
    final languageController = AppLanguageController(
      initialLanguage: language,
      initialMoneyUnit: moneyUnit,
      saveLanguage: repository.setAppLanguage,
      saveMoneyUnit: repository.setAppMoneyUnit,
    );
    return _AppStartup(
      repository: repository,
      languageController: languageController,
    );
  }

  ThemeData _theme({AppLanguage language = AppLanguage.defaultLanguage}) {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F766E)),
      fontFamily: language == AppLanguage.farsi ? 'Vazirmatn' : null,
      fontFamilyFallback: const ['Vazirmatn', 'Noto Sans Arabic', 'Roboto'],
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
