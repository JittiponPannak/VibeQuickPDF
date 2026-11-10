package com.jittiponpannak.vibe_quick_pdf

import android.Manifest
import android.app.Activity
import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.OpenableColumns
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.jittiponpannak.vibe_quick_pdf/storage"
        private const val REQUEST_PICK_PDF = 4001
        private const val REQUEST_STORAGE_PERMISSION = 4002
        private const val DOCUMENTS_SUBFOLDER = "VibeQuickPDF"
    }

    private var pendingPickResult: MethodChannel.Result? = null
    private var pendingSaveResult: MethodChannel.Result? = null
    private var pendingSaveArgs: Triple<String, String, ByteArray>? = null
    private val ioExecutor = Executors.newSingleThreadExecutor()

    override fun onDestroy() {
        ioExecutor.shutdown()
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
                when (call.method) {
                    "saveToDocuments" -> handleSaveToDocuments(call, result)
                    "pickPdfFile" -> handlePickPdfFile(result)
                    "findMatchingRegisteredPath" -> handleFindMatchingRegisteredPath(call, result)
                    "inspectUri" -> handleInspectUri(call, result)
                    "openUri" -> handleOpenUri(call, result)
                    "copyUriToTempFile" -> handleCopyUriToTempFile(call, result)
                    "deleteUri" -> handleDeleteUri(call, result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun handleSaveToDocuments(call: MethodCall, result: MethodChannel.Result) {
        val fileName = call.argument<String>("fileName") ?: "Document"
        val extension = (call.argument<String>("extension") ?: "pdf").removePrefix(".")
        val bytes = call.argument<ByteArray>("bytes")
        if (bytes == null) {
            result.error("INVALID_ARGS", "Missing bytes", null)
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                val saved = saveViaMediaStore(fileName, extension, bytes)
                result.success(saved)
            } catch (e: Exception) {
                result.error("SAVE_FAILED", e.message ?: "Failed to save file", null)
            }
        } else {
            val granted = ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.WRITE_EXTERNAL_STORAGE
            ) == PackageManager.PERMISSION_GRANTED

            if (granted) {
                try {
                    val saved = saveToLegacyDocuments(fileName, extension, bytes)
                    result.success(saved)
                } catch (e: Exception) {
                    result.error("SAVE_FAILED", e.message ?: "Failed to save file", null)
                }
            } else {
                if (pendingSaveResult != null) {
                    result.error("BUSY", "Another save request is in progress", null)
                    return
                }
                pendingSaveResult = result
                pendingSaveArgs = Triple(fileName, extension, bytes)
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
                    REQUEST_STORAGE_PERMISSION
                )
            }
        }
    }

    private fun saveViaMediaStore(
        fileName: String,
        extension: String,
        bytes: ByteArray
    ): Map<String, Any> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            throw IllegalStateException("MediaStore RELATIVE_PATH requires Android 10+")
        }

        val relativePath = "${Environment.DIRECTORY_DOCUMENTS}/$DOCUMENTS_SUBFOLDER"
        val mimeType = if (extension.equals("zip", ignoreCase = true)) {
            "application/zip"
        } else {
            "application/pdf"
        }

        val collection = MediaStore.Files.getContentUri("external")
        val targetName = findUniqueMediaStoreName(collection, relativePath, fileName, extension)

        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, targetName)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
            put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }

        val uri = contentResolver.insert(collection, values)
            ?: throw IllegalStateException("Could not create MediaStore entry")

        try {
            contentResolver.openOutputStream(uri)?.use { out ->
                out.write(bytes)
                out.flush()
            } ?: throw IllegalStateException("Could not open output stream")

            val doneValues = ContentValues().apply {
                put(MediaStore.MediaColumns.IS_PENDING, 0)
            }
            contentResolver.update(uri, doneValues, null, null)
        } catch (e: Exception) {
            try {
                contentResolver.delete(uri, null, null)
            } catch (_: Exception) {}
            throw e
        }

        val meta = queryUriMetadata(uri)
        return mapOf(
            "path" to uri.toString(),
            "name" to (meta?.get("name") ?: targetName),
            "size" to (meta?.get("size") ?: bytes.size.toLong()),
            "createdAt" to (meta?.get("createdAt") ?: System.currentTimeMillis())
        )
    }

    private fun findUniqueMediaStoreName(
        collection: Uri,
        relativePath: String,
        baseName: String,
        extension: String
    ): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return "$baseName.$extension"
        }
        var candidate = "$baseName.$extension"
        var counter = 1
        while (mediaStoreFileExists(collection, relativePath, candidate) && counter < 10000) {
            candidate = "${baseName}_$counter.$extension"
            counter++
        }
        return candidate
    }

    private fun mediaStoreFileExists(
        collection: Uri,
        relativePath: String,
        displayName: String
    ): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
        val projection = arrayOf(MediaStore.MediaColumns._ID)
        val selection =
            "${MediaStore.MediaColumns.RELATIVE_PATH} LIKE ? AND ${MediaStore.MediaColumns.DISPLAY_NAME} = ?"
        val selectionArgs = arrayOf("$relativePath%", displayName)
        contentResolver.query(collection, projection, selection, selectionArgs, null)?.use { cursor ->
            return cursor.moveToFirst()
        }
        return false
    }

    @Suppress("DEPRECATION")
    private fun saveToLegacyDocuments(
        fileName: String,
        extension: String,
        bytes: ByteArray
    ): Map<String, Any> {
        val docsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS)
        val targetDir = File(docsDir, DOCUMENTS_SUBFOLDER)
        if (!targetDir.exists()) {
            targetDir.mkdirs()
        }

        var outFile = File(targetDir, "$fileName.$extension")
        var counter = 1
        while (outFile.exists() && counter < 10000) {
            outFile = File(targetDir, "${fileName}_$counter.$extension")
            counter++
        }

        FileOutputStream(outFile).use { out ->
            out.write(bytes)
            out.flush()
        }

        MediaScannerConnection.scanFile(
            this,
            arrayOf(outFile.absolutePath),
            arrayOf(if (extension.equals("zip", true)) "application/zip" else "application/pdf"),
            null
        )

        return mapOf(
            "path" to outFile.absolutePath,
            "name" to outFile.name,
            "size" to outFile.length(),
            "createdAt" to outFile.lastModified()
        )
    }

    private fun handlePickPdfFile(result: MethodChannel.Result) {
        if (pendingPickResult != null) {
            result.error("BUSY", "File picker is already open", null)
            return
        }
        pendingPickResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/pdf"
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
            )
        }
        startActivityForResult(intent, REQUEST_PICK_PDF)
    }

    private data class FileIdentity(
        val raw: String,
        val mediaId: Long? = null,
        val filePath: String? = null,
        val relativePath: String? = null,
        val size: Long? = null
    )

    private data class MediaStoreDetails(
        val filePath: String? = null,
        val relativePath: String? = null,
        val size: Long? = null
    )

    private fun handleFindMatchingRegisteredPath(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")
        val registeredPaths = call.argument<List<String>>("registeredPaths")
        if (uriString.isNullOrBlank() || registeredPaths.isNullOrEmpty()) {
            result.success(null)
            return
        }

        ioExecutor.execute {
            val matched = try {
                findMatchingRegisteredPathSync(uriString, registeredPaths)
            } catch (_: Exception) {
                null
            }
            runOnUiThread {
                result.success(matched)
            }
        }
    }

    private fun findMatchingRegisteredPathSync(
        pickedUriString: String,
        registeredPaths: List<String>
    ): String? {
        if (registeredPaths.contains(pickedUriString)) {
            return pickedUriString
        }

        val picked = resolveFileIdentity(pickedUriString)
        val registered = registeredPaths.map { resolveFileIdentity(it) }

        // 1. Fast match by MediaStore ID, canonical file path, or primary relative path
        for (reg in registered) {
            if (picked.mediaId != null && reg.mediaId != null && picked.mediaId == reg.mediaId) {
                return reg.raw
            }
            if (picked.filePath != null && reg.filePath != null && picked.filePath == reg.filePath) {
                return reg.raw
            }
            if (picked.relativePath != null && reg.relativePath != null && picked.relativePath == reg.relativePath) {
                return reg.raw
            }
        }

        // 2. Fallback match by exact size + SHA-256 content hash (for third-party/OEM providers)
        val pickedSize = picked.size
        if (pickedSize != null && pickedSize > 0L) {
            val sizeCandidates = registered.filter { it.size == pickedSize }
            if (sizeCandidates.isNotEmpty()) {
                val pickedHash = computeSha256(pickedUriString)
                if (pickedHash != null) {
                    for (reg in sizeCandidates) {
                        val regHash = computeSha256(reg.raw)
                        if (regHash != null && regHash == pickedHash) {
                            return reg.raw
                        }
                    }
                }
            }
        }

        return null
    }

    private fun resolveFileIdentity(pathOrUri: String): FileIdentity {
        if (!pathOrUri.startsWith("content://")) {
            val path = if (pathOrUri.startsWith("file://")) {
                Uri.parse(pathOrUri).path
            } else {
                pathOrUri
            }
            if (path.isNullOrBlank()) return FileIdentity(raw = pathOrUri)
            val file = File(path)
            val canonical = try { file.canonicalPath } catch (_: Exception) { file.absolutePath }
            val size = if (file.exists()) file.length() else null
            return FileIdentity(
                raw = pathOrUri,
                filePath = canonical,
                relativePath = extractPrimaryRelativePath(canonical),
                size = size
            )
        }

        val uri = Uri.parse(pathOrUri)
        var mediaId: Long? = null
        var filePath: String? = null
        var relativePath: String? = null
        var size: Long? = null

        if (uri.authority == "media") {
            mediaId = try {
                ContentUris.parseId(uri).takeIf { it >= 0L }
            } catch (_: Exception) {
                null
            }
            val details = queryMediaStoreDetails(uri)
            filePath = details.filePath
            relativePath = details.relativePath
            size = details.size
        } else {
            if (DocumentsContract.isDocumentUri(this, uri)) {
                val docId = try { DocumentsContract.getDocumentId(uri) } catch (_: Exception) { null }
                if (!docId.isNullOrBlank()) {
                    when (uri.authority) {
                        "com.android.externalstorage.documents" -> {
                            if (docId.startsWith("primary:")) {
                                val rel = docId.removePrefix("primary:").trimStart('/')
                                if (rel.isNotEmpty()) {
                                    relativePath = rel.lowercase()
                                    val candidate = File(Environment.getExternalStorageDirectory(), rel)
                                    filePath = try { candidate.canonicalPath } catch (_: Exception) { candidate.absolutePath }
                                }
                            } else if (docId.startsWith("raw:")) {
                                val rawPath = docId.removePrefix("raw:")
                                if (rawPath.isNotEmpty()) {
                                    filePath = try { File(rawPath).canonicalPath } catch (_: Exception) { rawPath }
                                    relativePath = filePath?.let { extractPrimaryRelativePath(it) }
                                }
                            }
                        }
                        "com.android.providers.media.documents" -> {
                            val idPart = docId.substringAfter(':', "")
                            mediaId = idPart.toLongOrNull()?.takeIf { it >= 0L }
                        }
                        "com.android.providers.downloads.documents" -> {
                            if (docId.startsWith("msf:")) {
                                mediaId = docId.removePrefix("msf:").toLongOrNull()?.takeIf { it >= 0L }
                            } else if (docId.startsWith("raw:")) {
                                val rawPath = docId.removePrefix("raw:")
                                if (rawPath.isNotEmpty()) {
                                    filePath = try { File(rawPath).canonicalPath } catch (_: Exception) { rawPath }
                                    relativePath = filePath?.let { extractPrimaryRelativePath(it) }
                                }
                            }
                        }
                    }
                }
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && (mediaId == null || filePath == null)) {
                val mediaUri = try {
                    MediaStore.getMediaUri(this, uri)
                } catch (_: Exception) {
                    null
                }
                if (mediaUri != null && mediaUri.authority == "media") {
                    if (mediaId == null) {
                        mediaId = try {
                            ContentUris.parseId(mediaUri).takeIf { it >= 0L }
                        } catch (_: Exception) {
                            null
                        }
                    }
                    val details = queryMediaStoreDetails(mediaUri)
                    if (filePath == null) filePath = details.filePath
                    if (relativePath == null) relativePath = details.relativePath
                    if (size == null) size = details.size
                }
            }

            if (size == null) {
                size = (try { queryUriMetadata(uri)?.get("size") as? Long } catch (_: Exception) { null })
                    ?.takeIf { it > 0L }
                    ?: try {
                        contentResolver.openAssetFileDescriptor(uri, "r")?.use {
                            if (it.length > 0L) it.length else null
                        }
                    } catch (_: Exception) {
                        null
                    }
            }
        }

        return FileIdentity(
            raw = pathOrUri,
            mediaId = mediaId,
            filePath = filePath,
            relativePath = relativePath,
            size = size
        )
    }

    @Suppress("DEPRECATION")
    private fun queryMediaStoreDetails(uri: Uri): MediaStoreDetails {
        var filePath: String? = null
        var relativePath: String? = null
        var size: Long? = null

        try {
            contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                if (!cursor.moveToFirst()) return MediaStoreDetails()

                val sizeIdx = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (sizeIdx >= 0 && !cursor.isNull(sizeIdx)) {
                    size = cursor.getLong(sizeIdx).takeIf { it > 0L }
                }

                val dataIdx = cursor.getColumnIndex(MediaStore.MediaColumns.DATA)
                if (dataIdx >= 0 && !cursor.isNull(dataIdx)) {
                    val rawPath = cursor.getString(dataIdx)
                    if (!rawPath.isNullOrBlank()) {
                        filePath = try { File(rawPath).canonicalPath } catch (_: Exception) { rawPath }
                        relativePath = filePath?.let { extractPrimaryRelativePath(it) }
                    }
                }

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    val volIdx = cursor.getColumnIndex(MediaStore.MediaColumns.VOLUME_NAME)
                    val relIdx = cursor.getColumnIndex(MediaStore.MediaColumns.RELATIVE_PATH)
                    val nameIdx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    val volume = if (volIdx >= 0 && !cursor.isNull(volIdx)) cursor.getString(volIdx) else null
                    val relDir = if (relIdx >= 0 && !cursor.isNull(relIdx)) cursor.getString(relIdx) else null
                    val displayName = if (nameIdx >= 0 && !cursor.isNull(nameIdx)) cursor.getString(nameIdx) else null
                    if (!relDir.isNullOrBlank() && !displayName.isNullOrBlank()) {
                        val isPrimaryVolume = volume == null ||
                            volume.equals("external_primary", ignoreCase = true) ||
                            volume.equals("external", ignoreCase = true)
                        if (isPrimaryVolume) {
                            val combinedRel = "${relDir.trimEnd('/')}/$displayName".trimStart('/')
                            if (relativePath == null) {
                                relativePath = combinedRel.lowercase()
                            }
                            if (filePath == null) {
                                val candidate = File(Environment.getExternalStorageDirectory(), combinedRel)
                                if (candidate.exists()) {
                                    filePath = try { candidate.canonicalPath } catch (_: Exception) { candidate.absolutePath }
                                }
                            }
                        }
                    }
                }
            }
        } catch (_: Exception) {
            // Ignore provider errors for unreadable/revoked URIs
        }

        return MediaStoreDetails(
            filePath = filePath,
            relativePath = relativePath,
            size = size
        )
    }

    private fun extractPrimaryRelativePath(canonicalPath: String): String? {
        val extRoot = try {
            Environment.getExternalStorageDirectory().canonicalPath
        } catch (_: Exception) {
            Environment.getExternalStorageDirectory().absolutePath
        }.trimEnd('/')
        val prefix = "$extRoot/"
        return if (canonicalPath.startsWith(prefix, ignoreCase = true)) {
            canonicalPath.substring(prefix.length).trimStart('/').lowercase()
        } else {
            null
        }
    }

    private fun computeSha256(pathOrUri: String): String? {
        return try {
            val inputStream = if (pathOrUri.startsWith("content://")) {
                contentResolver.openInputStream(Uri.parse(pathOrUri))
            } else {
                val filePath = if (pathOrUri.startsWith("file://")) {
                    Uri.parse(pathOrUri).path
                } else {
                    pathOrUri
                } ?: return null
                val file = File(filePath)
                if (!file.exists()) return null
                file.inputStream()
            } ?: return null

            inputStream.use { stream ->
                val digest = MessageDigest.getInstance("SHA-256")
                val buffer = ByteArray(8192)
                var read: Int
                while (stream.read(buffer).also { read = it } != -1) {
                    digest.update(buffer, 0, read)
                }
                digest.digest().joinToString("") { "%02x".format(it) }
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun handleInspectUri(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")
        if (uriString.isNullOrBlank()) {
            result.success(null)
            return
        }
        try {
            val uri = Uri.parse(uriString)
            // Confirm the URI can actually be opened for reading
            contentResolver.openFileDescriptor(uri, "r")?.use { }
                ?: run {
                    result.success(null)
                    return
                }
            val meta = queryUriMetadata(uri)
            result.success(meta)
        } catch (_: Exception) {
            result.success(null)
        }
    }

    private fun queryUriMetadata(uri: Uri): Map<String, Any>? {
        contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            if (!cursor.moveToFirst()) return null

            val nameIdx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            val sizeIdx = cursor.getColumnIndex(OpenableColumns.SIZE)
            val docModifiedIdx = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_LAST_MODIFIED)
            val mediaModifiedIdx = cursor.getColumnIndex(MediaStore.MediaColumns.DATE_MODIFIED)

            val name = if (nameIdx >= 0 && !cursor.isNull(nameIdx)) {
                cursor.getString(nameIdx)
            } else {
                "Document.pdf"
            }

            val size = if (sizeIdx >= 0 && !cursor.isNull(sizeIdx)) {
                cursor.getLong(sizeIdx)
            } else {
                0L
            }

            val createdAtMs = when {
                docModifiedIdx >= 0 && !cursor.isNull(docModifiedIdx) -> {
                    val v = cursor.getLong(docModifiedIdx)
                    if (v > 0L) v else System.currentTimeMillis()
                }
                mediaModifiedIdx >= 0 && !cursor.isNull(mediaModifiedIdx) -> {
                    val v = cursor.getLong(mediaModifiedIdx)
                    if (v > 0L) v * 1000L else System.currentTimeMillis()
                }
                else -> System.currentTimeMillis()
            }

            return mapOf(
                "name" to name,
                "size" to size,
                "createdAt" to createdAtMs
            )
        }
        return null
    }

    private fun handleOpenUri(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")
        val mimeType = call.argument<String>("mimeType") ?: "application/pdf"
        if (uriString.isNullOrBlank()) {
            result.success(false)
            return
        }
        try {
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(Uri.parse(uriString), mimeType)
                addFlags(
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_ACTIVITY_NEW_TASK
                )
            }
            startActivity(intent)
            result.success(true)
        } catch (_: Exception) {
            result.success(false)
        }
    }

    private fun handleCopyUriToTempFile(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")
        val fileName = call.argument<String>("fileName") ?: "document.pdf"
        if (uriString.isNullOrBlank()) {
            result.success(null)
            return
        }
        try {
            val uri = Uri.parse(uriString)
            val safeName = File(fileName).name.ifBlank { "document.pdf" }
            val shareDir = File(cacheDir, "share_cache").apply { mkdirs() }
            val destFile = File(shareDir, safeName)

            contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(destFile).use { output ->
                    input.copyTo(output)
                }
            } ?: run {
                result.success(null)
                return
            }

            result.success(destFile.absolutePath)
        } catch (_: Exception) {
            result.success(null)
        }
    }

    private fun handleDeleteUri(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")
        if (uriString.isNullOrBlank()) {
            result.success(false)
            return
        }
        try {
            val uri = Uri.parse(uriString)
            val deleted = if (DocumentsContract.isDocumentUri(this, uri)) {
                DocumentsContract.deleteDocument(contentResolver, uri)
            } else {
                contentResolver.delete(uri, null, null) > 0
            }
            result.success(deleted)
        } catch (_: Exception) {
            result.success(false)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_PICK_PDF) {
            val result = pendingPickResult
            pendingPickResult = null
            if (result == null) return

            if (resultCode != Activity.RESULT_OK || data?.data == null) {
                result.success(null)
                return
            }

            val uri = data.data!!
            try {
                contentResolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION
                )
            } catch (_: SecurityException) {
                // Provider may only grant temporary permission
            }

            val meta = queryUriMetadata(uri)
            val fileName = (meta?.get("name") as? String) ?: "Imported.pdf"
            val size = (meta?.get("size") as? Long) ?: 0L
            val createdAt = (meta?.get("createdAt") as? Long) ?: System.currentTimeMillis()

            result.success(
                mapOf(
                    "path" to uri.toString(),
                    "name" to fileName,
                    "size" to size,
                    "createdAt" to createdAt
                )
            )
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_STORAGE_PERMISSION) {
            val result = pendingSaveResult
            val args = pendingSaveArgs
            pendingSaveResult = null
            pendingSaveArgs = null
            if (result == null || args == null) return

            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            if (granted) {
                try {
                    val saved = saveToLegacyDocuments(args.first, args.second, args.third)
                    result.success(saved)
                } catch (e: Exception) {
                    result.error("SAVE_FAILED", e.message ?: "Failed to save file", null)
                }
            } else {
                result.error("PERMISSION_DENIED", "Storage permission denied", null)
            }
        }
    }
}
