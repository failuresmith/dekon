package xyz.infinica.dekon

import android.app.Activity
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.IOException

class MainActivity : FlutterActivity() {
    private var pendingBackupSave: PendingBackupSave? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BACKUP_FILES_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveBackupFile" -> saveBackupFile(call, result)
                else -> result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == SAVE_BACKUP_REQUEST_CODE) {
            handleBackupSaveResult(resultCode, data)
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun saveBackupFile(call: MethodCall, result: MethodChannel.Result) {
        if (pendingBackupSave != null) {
            result.error("save_in_progress", "A backup save is already in progress.", null)
            return
        }

        val sourcePath = call.argument<String>("sourcePath")
        val fileName = call.argument<String>("fileName")
        val mimeType = call.argument<String>("mimeType") ?: "application/json"
        if (sourcePath.isNullOrBlank() || fileName.isNullOrBlank()) {
            result.error("invalid_arguments", "Backup save arguments are missing.", null)
            return
        }
        if (!File(sourcePath).isFile) {
            result.error("invalid_source", "Backup file is missing.", null)
            return
        }

        pendingBackupSave = PendingBackupSave(
            sourcePath = sourcePath,
            fileName = fileName,
            result = result,
        )

        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = mimeType
            putExtra(Intent.EXTRA_TITLE, fileName)
            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        }
        try {
            startActivityForResult(intent, SAVE_BACKUP_REQUEST_CODE)
        } catch (error: Exception) {
            pendingBackupSave = null
            result.error("storage_access_denied", "Could not open backup save location.", null)
        }
    }

    private fun handleBackupSaveResult(resultCode: Int, data: Intent?) {
        val save = pendingBackupSave ?: return
        pendingBackupSave = null

        if (resultCode != Activity.RESULT_OK) {
            save.result.success(null)
            return
        }

        val uri: Uri? = data?.data
        if (uri == null) {
            save.result.error("storage_access_denied", "Backup save location was unavailable.", null)
            return
        }

        try {
            contentResolver.openOutputStream(uri, "wt")?.use { output ->
                FileInputStream(save.sourcePath).use { input ->
                    input.copyTo(output)
                }
            } ?: throw IOException("Could not open backup save location.")
            save.result.success(mapOf("uri" to uri.toString(), "fileName" to save.fileName))
        } catch (error: SecurityException) {
            save.result.error("storage_access_denied", "Storage access was denied.", null)
        } catch (error: IOException) {
            save.result.error("storage_access_denied", "Backup could not be written.", null)
        }
    }

    private data class PendingBackupSave(
        val sourcePath: String,
        val fileName: String,
        val result: MethodChannel.Result,
    )

    private companion object {
        const val BACKUP_FILES_CHANNEL = "xyz.infinica.dekon/backup_files"
        const val SAVE_BACKUP_REQUEST_CODE = 9101
    }
}
