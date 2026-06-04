import 'package:file_selector/file_selector.dart';

class BackupImportFile {
  const BackupImportFile({required this.name, required this.contents});

  final String name;
  final String contents;
}

class BackupFileActions {
  const BackupFileActions();

  static const _backupType = XTypeGroup(
    label: 'Dekon backup',
    extensions: ['json'],
    mimeTypes: ['application/json'],
  );

  Future<String?> chooseExportDirectory() {
    return getDirectoryPath(
      confirmButtonText: 'Use Folder',
      canCreateDirectories: true,
    );
  }

  Future<BackupImportFile?> chooseImportFile() async {
    final file = await openFile(
      acceptedTypeGroups: const [_backupType],
      confirmButtonText: 'Restore',
    );
    if (file == null) return null;
    return BackupImportFile(
      name: file.name,
      contents: await file.readAsString(),
    );
  }
}
