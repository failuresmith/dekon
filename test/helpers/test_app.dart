import 'package:dekon/main.dart';
import 'package:dekon/src/application/application.dart';
import 'package:dekon/src/persistence/persistence.dart';
import 'package:flutter/widgets.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<DekonRepository> createTestRepository() async {
  sqfliteFfiInit();
  final db = await CoreDatabase.open(
    path: inMemoryDatabasePath,
    factory: databaseFactoryFfiNoIsolate,
  );
  return DekonRepository.open(database: db);
}

Widget testApp(DekonRepository repository) {
  return MainApp(repositoryFactory: () async => repository);
}
