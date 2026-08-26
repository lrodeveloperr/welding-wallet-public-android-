package com.goodusestudios.weldinggaswallet.backend.backup

import android.content.ContentResolver
import android.net.Uri
import com.goodusestudios.weldinggaswallet.backend.domain.MAXIMUM_BACKUP_BYTES
import java.io.ByteArrayOutputStream
import java.nio.charset.StandardCharsets

class AndroidBackupFiles(private val contentResolver: ContentResolver) {
    fun readUtf8(uri: Uri): String {
        val bytes = contentResolver.openInputStream(uri)?.use { input ->
            val output = ByteArrayOutputStream()
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            var total = 0
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                total += count
                require(total <= MAXIMUM_BACKUP_BYTES) {
                    "Backup exceeds the maximum supported size."
                }
                output.write(buffer, 0, count)
            }
            output.toByteArray()
        } ?: throw IllegalArgumentException("Backup URI could not be opened.")
        return String(bytes, StandardCharsets.UTF_8)
    }

    fun writeUtf8(uri: Uri, encoded: String) {
        val bytes = encoded.toByteArray(StandardCharsets.UTF_8)
        require(bytes.size <= MAXIMUM_BACKUP_BYTES) { "Backup exceeds the maximum supported size." }
        contentResolver.openOutputStream(uri, "wt")?.use { output ->
            output.write(bytes)
            output.flush()
        } ?: throw IllegalArgumentException("Backup destination URI could not be opened.")
    }
}
