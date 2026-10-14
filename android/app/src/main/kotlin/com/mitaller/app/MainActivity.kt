package com.mitaller.app

import android.content.ContentValues
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

/// Canal "georges_garage/media": guarda el PDF del ticket en Descargas
/// y la imagen en la galería usando MediaStore (Android 10+).
/// Sin esto, en Android moderno no se puede escribir directo a las
/// carpetas compartidas por el modo de almacenamiento por alcance.
/// También guarda/lista/borra los respaldos automáticos en
/// Descargas/MiTaller/.
class MainActivity : FlutterActivity() {
    private val channel = "georges_garage/media"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "listBackups" -> {
                            result.success(listBackupFiles())
                            return@setMethodCallHandler
                        }
                        "deleteBackup" -> {
                            val delName = call.argument<String>("name")
                                ?: throw Exception(
                                    "Falta el nombre del archivo")
                            deleteBackupFile(delName)
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        else -> {}
                    }
                    val name = call.argument<String>("name")
                        ?: throw Exception("Falta el nombre del archivo")
                    val bytes = call.argument<ByteArray>("bytes")
                        ?: throw Exception("Faltan los datos del archivo")
                    when (call.method) {
                        "savePdf" -> {
                            saveFile(
                                name, bytes, "application/pdf",
                                Environment.DIRECTORY_DOWNLOADS, true)
                            result.success(null)
                        }
                        "saveImage" -> {
                            saveFile(
                                name, bytes, "image/png",
                                Environment.DIRECTORY_PICTURES, false)
                            result.success(null)
                        }
                        "saveBackup" -> {
                            saveBackupFile(name, bytes)
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("SAVE_FAILED", e.message, null)
                }
            }
    }

    private fun saveFile(
        name: String,
        bytes: ByteArray,
        mime: String,
        dir: String,
        isPdf: Boolean
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val collection = if (isPdf) {
                MediaStore.Downloads.EXTERNAL_CONTENT_URI
            } else {
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            }
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                put(MediaStore.MediaColumns.MIME_TYPE, mime)
                put(MediaStore.MediaColumns.RELATIVE_PATH,
                    "$dir/GeorgesGarage")
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val resolver = contentResolver
            val uri = resolver.insert(collection, values)
                ?: throw Exception("El sistema no permitió crear el archivo")
            resolver.openOutputStream(uri)?.use { it.write(bytes) }
                ?: throw Exception("No se pudo escribir el archivo")
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
        } else {
            // Android 9 o anterior: escritura directa (requiere permiso
            // WRITE_EXTERNAL_STORAGE declarado en el manifiesto).
            @Suppress("DEPRECATION")
            val publicDir =
                Environment.getExternalStoragePublicDirectory(dir)
            if (!publicDir.exists()) publicDir.mkdirs()
            @Suppress("DEPRECATION")
            val file = File(publicDir, name)
            FileOutputStream(file).use { it.write(bytes) }
            MediaScannerConnection.scanFile(
                this, arrayOf(file.absolutePath), arrayOf(mime), null)
        }
    }

    /// Guarda el JSON de respaldo en Descargas/MiTaller/ (Android 10+).
    private fun saveBackupFile(name: String, bytes: ByteArray) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                put(MediaStore.MediaColumns.MIME_TYPE, "application/json")
                put(MediaStore.MediaColumns.RELATIVE_PATH,
                    "${Environment.DIRECTORY_DOWNLOADS}/MiTaller")
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val resolver = contentResolver
            val uri = resolver.insert(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw Exception("El sistema no permitió crear el archivo")
            resolver.openOutputStream(uri)?.use { it.write(bytes) }
                ?: throw Exception("No se pudo escribir el archivo")
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
        } else {
            @Suppress("DEPRECATION")
            val publicDir = File(
                Environment.getExternalStoragePublicDirectory(
                    Environment.DIRECTORY_DOWNLOADS), "MiTaller")
            if (!publicDir.exists()) publicDir.mkdirs()
            @Suppress("DEPRECATION")
            val file = File(publicDir, name)
            FileOutputStream(file).use { it.write(bytes) }
            MediaScannerConnection.scanFile(
                this, arrayOf(file.absolutePath),
                arrayOf("application/json"), null)
        }
    }

    /// Lista los nombres de respaldos en Descargas/MiTaller/.
    private fun listBackupFiles(): List<String> {
        val names = mutableListOf<String>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = contentResolver
            val cursor = resolver.query(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                arrayOf(MediaStore.MediaColumns.DISPLAY_NAME),
                "${MediaStore.MediaColumns.RELATIVE_PATH}=? AND " +
                    "${MediaStore.MediaColumns.DISPLAY_NAME} LIKE ?",
                arrayOf("Download/MiTaller/", "mitaller-respaldo-%"),
                "${MediaStore.MediaColumns.DISPLAY_NAME} ASC")
            cursor?.use {
                val idx =
                    it.getColumnIndex(MediaStore.MediaColumns.DISPLAY_NAME)
                while (it.moveToNext()) {
                    names.add(it.getString(idx))
                }
            }
        } else {
            @Suppress("DEPRECATION")
            val publicDir = File(
                Environment.getExternalStoragePublicDirectory(
                    Environment.DIRECTORY_DOWNLOADS), "MiTaller")
            publicDir.listFiles { f ->
                f.name.startsWith("mitaller-respaldo-") &&
                    f.name.endsWith(".json")
            }?.forEach { names.add(it.name) }
        }
        return names.sorted()
    }

    /// Borra un respaldo de Descargas/MiTaller/ por nombre.
    private fun deleteBackupFile(name: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = contentResolver
            val cursor = resolver.query(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                arrayOf(MediaStore.MediaColumns._ID),
                "${MediaStore.MediaColumns.RELATIVE_PATH}=? AND " +
                    "${MediaStore.MediaColumns.DISPLAY_NAME}=?",
                arrayOf("Download/MiTaller/", name),
                null)
            cursor?.use {
                val idx = it.getColumnIndex(MediaStore.MediaColumns._ID)
                while (it.moveToNext()) {
                    val id = it.getLong(idx)
                    val uri = android.net.Uri.withAppendedPath(
                        MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                        id.toString())
                    resolver.delete(uri, null, null)
                }
            }
        } else {
            @Suppress("DEPRECATION")
            val file = File(
                File(Environment.getExternalStoragePublicDirectory(
                    Environment.DIRECTORY_DOWNLOADS), "MiTaller"), name)
            if (file.exists()) file.delete()
        }
    }
}
