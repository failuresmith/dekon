import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../persistence/core_database.dart';

class AppDatabasePath {
  static const fileName = 'dekon.sqlite';

  static Future<String> resolve() async {
    final directory = await getApplicationDocumentsDirectory();
    return p.join(directory.path, fileName);
  }

  static Future<Database> openCoreDatabase() async {
    return CoreDatabase.open(path: await resolve());
  }
}
