package org.example.checksheet

import android.content.Context
import android.view.View
import com.github.barteksc.pdfviewer.PDFView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import java.io.File

class PdfPlatformView(
    context: Context,
    messenger: BinaryMessenger,
    viewId: Int,
    creationParams: Map<String?, Any?>?
) : PlatformView, MethodChannel.MethodCallHandler {

    private val pdfView: PDFView = PDFView(context, null)
    private val channel: MethodChannel = MethodChannel(messenger, "org.example.checksheet/pdf_viewer_$viewId")

    init {
        channel.setMethodCallHandler(this)
        val pdfPath = creationParams?.get("pdfPath") as? String
        if (pdfPath != null) {
            loadPdf(pdfPath)
        }
    }

    override fun getView(): View {
        return pdfView
    }

    override fun dispose() {
        channel.setMethodCallHandler(null)
    }

    private fun loadPdf(path: String) {
        val file = File(path)
        if (file.exists()) {
            pdfView.fromFile(file)
                .enableDoubletap(true) // 더블탭 줌 활성화
                .enableSwipe(true)
                .swipeHorizontal(false)
                .defaultPage(0)
                .load()
        }
    }

    private fun resetFit() {
        pdfView.zoomTo(pdfView.minZoom)
        pdfView.performPageSnap()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "loadPdf" -> {
                val path = call.argument<String>("pdfPath")
                if (path != null) {
                    loadPdf(path)
                    result.success(true)
                } else {
                    result.error("INVALID_ARGUMENT", "pdfPath is null", null)
                }
            }
            "resetFit" -> {
                resetFit()
                result.success(true)
            }
            else -> {
                result.notImplemented()
            }
        }
    }
}
