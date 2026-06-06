import 'package:dekon/main.dart';
import 'package:dekon/src/application/application.dart';
import 'package:dekon/src/persistence/persistence.dart';
import 'package:dekon/src/ui/barcode_scanner_dialog.dart';
import 'package:dekon/src/ui/cashier_pairing_panel.dart';
import 'package:flutter/widgets.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<DekonRepository> createTestRepository({
  bool onboarded = false,
  DeviceRole role = DeviceRole.mainDevice,
}) async {
  sqfliteFfiInit();
  final db = await CoreDatabase.open(
    path: inMemoryDatabasePath,
    factory: databaseFactoryFfiNoIsolate,
    singleInstance: false,
  );
  final repository = await DekonRepository.open(database: db);
  if (onboarded) {
    await repository.completeDeviceOnboarding(role);
  }
  return repository;
}

Future<DekonRepository> createEnglishTestRepository({
  bool onboarded = false,
  DeviceRole role = DeviceRole.mainDevice,
}) async {
  final repository = await createTestRepository(
    onboarded: onboarded,
    role: role,
  );
  await repository.setAppLanguage(AppLanguage.english);
  return repository;
}

Widget testApp(
  DekonRepository repository, {
  BarcodeScanLauncher? scanBarcode,
  MainDevicePairer? pairWithMainDevice,
  MainDeviceAddressPairer? pairWithMainDeviceAddress,
}) {
  return MainApp(
    repositoryFactory: () async => repository,
    scanBarcode: scanBarcode,
    pairWithMainDevice: pairWithMainDevice,
    pairWithMainDeviceAddress: pairWithMainDeviceAddress,
  );
}
