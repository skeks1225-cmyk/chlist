package org.example.checksheet

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*

class MainActivity: FlutterActivity() {
    private val CHANNEL = "org.example.checksheet/smb"
    private lateinit var smbHandler: SmbHandler
    private val scope = CoroutineScope(Dispatchers.Main + Job())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        smbHandler = SmbHandler(this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "connectSMB" -> {
                    val ip = call.argument<String>("ip") ?: ""
                    val user = call.argument<String>("user") ?: ""
                    val pass = call.argument<String>("pass") ?: ""
                    scope.launch { result.success(smbHandler.connect(ip, user, pass)) }
                }
                "listShares" -> {
                    scope.launch { result.success(smbHandler.listShares()) }
                }
                "listFiles" -> {
                    val share = call.argument<String>("share") ?: ""
                    val path = call.argument<String>("path") ?: ""
                    scope.launch { result.success(smbHandler.listFiles(share, path)) }
                }
                "downloadFile" -> {
                    val share = call.argument<String>("share") ?: ""
                    val remote = call.argument<String>("remotePath") ?: ""
                    val local = call.argument<String>("localPath") ?: ""
                    scope.launch { result.success(smbHandler.downloadFile(share, remote, local)) }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        smbHandler.disconnect()
        scope.cancel()
    }
}
