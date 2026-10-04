package com.example.personal_decision_assistant

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.app.Activity
import java.io.File
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import androidx.core.app.NotificationManagerCompat

class MainActivity: FlutterActivity() {
    private var permissionResult: MethodChannel.Result? = null
    private var reminderChannel: MethodChannel? = null
    private var backupResult: MethodChannel.Result? = null
    private var backupSource: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "personal_decision_assistant/backup_files").setMethodCallHandler { call, result ->
            if (backupResult != null) {
                result.error("busy", "A file operation is already open", null)
            } else when (call.method) {
                "save" -> {
                    val path = call.argument<String>("path")
                    val name = call.argument<String>("name")
                    if (path == null || name == null) {
                        result.error("invalid_arguments", "Missing file path or name", null)
                    } else {
                        backupSource = path
                        backupResult = result
                        startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "application/octet-stream"
                            putExtra(Intent.EXTRA_TITLE, name)
                        }, 82)
                    }
                }
                "open" -> {
                    backupResult = result
                    startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "*/*"
                    }, 83)
                }
                else -> result.notImplemented()
            }
        }
        reminderChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "personal_decision_assistant/review_reminders")
        reminderChannel?.setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestPermission" -> {
                        if (Build.VERSION.SDK_INT < 33 ||
                            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
                            result.success(true)
                        } else {
                            permissionResult = result
                            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 81)
                        }
                    }
                    "schedule" -> {
                        val id = call.argument<String>("id")
                        val at = call.argument<Long>("at")
                        if (id == null || at == null) {
                            result.error("invalid_arguments", "Missing reminder id or date", null)
                        } else {
                            val allowed = Build.VERSION.SDK_INT < 33 ||
                                checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
                            val enabled = allowed && NotificationManagerCompat.from(this).areNotificationsEnabled()
                            if (enabled) ReviewAlarm.schedule(this, id, at)
                            result.success(enabled)
                        }
                    }
                    "cancel" -> {
                        val id = call.argument<String>("id")
                        if (id == null) result.error("invalid_arguments", "Missing reminder id", null)
                        else {
                            ReviewAlarm.cancel(this, id)
                            result.success(null)
                        }
                    }
                    "openedFromReminder" -> result.success(
                        intent?.getBooleanExtra("open_records", false)?.also {
                            intent?.removeExtra("open_records")
                        } ?: false)
                    else -> result.notImplemented()
                }
            }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.getBooleanExtra("open_records", false)) {
            reminderChannel?.invokeMethod("openRecords", null)
            intent.removeExtra("open_records")
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 82 && requestCode != 83) return
        val result = backupResult ?: return
        backupResult = null
        try {
            val uri = if (resultCode == Activity.RESULT_OK) data?.data else null
            if (uri == null) {
                result.success(if (requestCode == 82) false else null)
            } else if (requestCode == 82) {
                val source = File(backupSource ?: error("Missing source"))
                contentResolver.openOutputStream(uri)?.use { output ->
                    source.inputStream().use { it.copyTo(output) }
                } ?: error("Cannot open destination")
                result.success(true)
            } else {
                val target = File.createTempFile("import-backup-", ".pdbak", cacheDir)
                try {
                    contentResolver.openInputStream(uri)?.use { input ->
                        target.outputStream().use { output ->
                            val buffer = ByteArray(8192)
                            var total = 0L
                            while (true) {
                                val read = input.read(buffer)
                                if (read < 0) break
                                total += read
                                if (total > 20L * 1024 * 1024) error("Backup exceeds 20 MB")
                                output.write(buffer, 0, read)
                            }
                        }
                    } ?: error("Cannot open backup")
                    result.success(target.absolutePath)
                } catch (error: Exception) {
                    target.delete()
                    throw error
                }
            }
        } catch (error: Exception) {
            result.error("file_error", error.message ?: "File operation failed", null)
        } finally {
            backupSource = null
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>,
                                            grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 81) {
            permissionResult?.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
            permissionResult = null
        }
    }
}
