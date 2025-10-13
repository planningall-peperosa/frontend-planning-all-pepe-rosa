// android/app/src/main/kotlin/com/example/MainActivity.kt
package com.example.test_fotocamera_2  // <<< IMPORTANTISSIMO: metti qui il package REALE dell’app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.OutputStream

class MainActivity : FlutterActivity() {

    private val CHANNEL = "it.peperosa/savefile"

    // Stato per la richiesta in corso
    private var pendingResult: MethodChannel.Result? = null
    private var pendingTempPath: String? = null
    private var pendingSuggestedName: String? = null
    private var pendingMimeType: String? = null

    private val REQ_CREATE_DOCUMENT = 1001

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "createDocument") {
                    if (pendingResult != null) {
                        result.error("BUSY", "Another save is in progress", null)
                        return@setMethodCallHandler
                    }
                    val suggestedName = call.argument<String>("suggestedName") ?: "document.pdf"
                    val mimeType = call.argument<String>("mimeType") ?: "application/pdf"
                    val tempPath = call.argument<String>("tempPath") ?: run {
                        result.error("ARG", "tempPath missing", null)
                        return@setMethodCallHandler
                    }

                    pendingResult = result
                    pendingTempPath = tempPath
                    pendingSuggestedName = suggestedName
                    pendingMimeType = mimeType

                    val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = mimeType
                        putExtra(Intent.EXTRA_TITLE, suggestedName)
                    }
                    // Avvio il picker nativo SAF
                    startActivityForResult(intent, REQ_CREATE_DOCUMENT)
                } else {
                    result.notImplemented()
                }
            }
    }

    @Deprecated("Deprecated in Android 13, usiamo per compatibilità ampia")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        val res = pendingResult ?: return
        val tempPath = pendingTempPath
        if (requestCode != REQ_CREATE_DOCUMENT) return

        // Reset stato pending in ogni caso
        pendingResult = null
        pendingTempPath = null
        pendingSuggestedName = null
        pendingMimeType = null

        if (resultCode != Activity.RESULT_OK || data?.data == null || tempPath == null) {
            res.success(false) // utente ha annullato
            return
        }

        val uri: Uri = data.data!!
        try {
            val inputFile = File(tempPath)
            FileInputStream(inputFile).use { input ->
                val out: OutputStream? = contentResolver.openOutputStream(uri, "w")
                if (out == null) {
                    res.success(false)
                    return
                }
                out.use { output ->
                    input.copyTo(output)
                    output.flush()
                }
            }
            // opzionale: pulizia file temporaneo
            runCatching { File(tempPath).delete() }
            res.success(true)
        } catch (e: Exception) {
            res.error("WRITE_ERROR", e.message, null)
        }
    }
}
