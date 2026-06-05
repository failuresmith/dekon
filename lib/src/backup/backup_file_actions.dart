import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

class BackupImportFile {
  const BackupImportFile({required this.name, required this.contents});

  final String name;
  final String contents;
}

class BackupFileActions {
  const BackupFileActions();

  static const _androidChannel = MethodChannel(
    'xyz.infinica.dekon/backup_files',
  );

  static const _backupType = XTypeGroup(
    label: 'Dekon backup',
    extensions: ['json'],
    mimeTypes: ['application/json'],
  );

  Future<BackupSaveResult?> saveExportedBackup({
    required String sourcePath,
    required String fileName,
  }) async {
    try {
      if (Platform.isAndroid) {
        return _saveAndroidBackup(sourcePath: sourcePath, fileName: fileName);
      }
      final location = await getSaveLocation(
        acceptedTypeGroups: const [_backupType],
        suggestedName: fileName,
        confirmButtonText: 'Save',
        canCreateDirectories: true,
      );
      if (location == null) return null;
      await XFile(
        sourcePath,
        mimeType: 'application/json',
      ).saveTo(location.path);
      return BackupSaveResult(
        path: location.path,
        fileName: p.basename(location.path),
      );
    } on PlatformException catch (error) {
      throw BackupStorageException(_platformErrorMessage(error));
    } on FileSystemException {
      throw BackupStorageException(
        'Storage access was denied. Choose a backup file and try again.',
      );
    }
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

  Future<BackupSaveResult?> _saveAndroidBackup({
    required String sourcePath,
    required String fileName,
  }) async {
    final result = await _androidChannel.invokeMapMethod<String, Object?>(
      'saveBackupFile',
      {
        'sourcePath': sourcePath,
        'fileName': fileName,
        'mimeType': 'application/json',
      },
    );
    if (result == null) return null;
    final savedFileName = result['fileName'] as String? ?? fileName;
    return BackupSaveResult(
      path: result['uri'] as String? ?? savedFileName,
      fileName: savedFileName,
    );
  }

  String _platformErrorMessage(PlatformException error) {
    if (error.code == 'storage_access_denied') {
      return 'Storage access was denied. Choose a backup file and try again.';
    }
    return 'Backup could not be saved.';
  }
}

class BackupSaveResult {
  const BackupSaveResult({required this.path, required this.fileName});

  final String path;
  final String fileName;
}

class BackupStorageException implements Exception {
  const BackupStorageException(this.message);

  final String message;

  @override
  String toString() => message;
}
