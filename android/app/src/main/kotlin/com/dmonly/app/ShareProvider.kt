package com.dmonly.app

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import java.io.File
import java.io.FileNotFoundException

/**
 * Lends share-sheet pictures (word cards) to the app the user shares with. Serves only files in
 * cache/share, read-only, and only to apps given a one-off grant by the share intent.
 */
class ShareProvider : ContentProvider() {
    override fun onCreate() = true

    private fun fileFor(uri: Uri): File? {
        val dir = dir(context ?: return null)
        val file = File(dir, uri.lastPathSegment ?: return null)
        val inside = file.canonicalPath.startsWith(dir.canonicalPath + File.separator)
        return if (inside && file.isFile) file else null
    }

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        if (mode != "r") throw SecurityException("Read only")
        val file = fileFor(uri) ?: throw FileNotFoundException(uri.toString())
        return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
    }

    // Many apps ask for the name and size before reading the picture.
    override fun query(
        uri: Uri, projection: Array<String>?, selection: String?,
        selectionArgs: Array<String>?, sortOrder: String?,
    ): Cursor? {
        val file = fileFor(uri) ?: return null
        val columns = projection ?: arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        val row = columns.map {
            when (it) {
                OpenableColumns.DISPLAY_NAME -> file.name
                OpenableColumns.SIZE -> file.length()
                else -> null
            }
        }
        return MatrixCursor(columns, 1).apply { addRow(row) }
    }

    override fun getType(uri: Uri) = "image/png"
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<String>?) = 0
    override fun update(
        uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<String>?,
    ) = 0

    companion object {
        fun dir(context: Context) = File(context.cacheDir, "share").apply { mkdirs() }

        /** Writes [png] to the share folder and returns a content:// address for it. */
        fun publish(context: Context, png: ByteArray, name: String): Uri {
            val file = File(dir(context), name)
            file.writeBytes(png)
            return Uri.Builder()
                .scheme("content")
                .authority("${context.packageName}.share")
                .appendPath(file.name)
                .build()
        }
    }
}
