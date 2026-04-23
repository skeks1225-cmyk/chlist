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
                // 1. connectSMB(ip, user, pass) -> String
                "connectSMB" -> {
                    val ip = call.argument<String>("ip") ?: ""
                    val user = call.argument<String>("user") ?: ""
                    val pass = call.argument<String>("pass") ?: ""
                    scope.launch {
                        val res = smbHandler.connect(ip, user, pass)
                        result.success(res)
                    }
                }
                // 2. listShares() -> List<String>
                "listShares" -> {
                    scope.launch {
                        val shares = smbHandler.listShares()
                        result.success(shares)
                    }
                }
                // 3. listFiles(share, path) -> List<Map<String, Any>>
                "listFiles" -> {
                    val share = call.argument<String>("share") ?: ""
                    val path = call.argument<String>("path") ?: ""
                    scope.launch {
                        val files = smbHandler.listFiles(share, path)
                        result.success(files)
                    }
                }
                // 4. downloadFile(share, remotePath, localPath) -> String?
                "downloadFile" -> {
                    val share = call.argument<String>("share") ?: ""
                    val remote = call.argument<String>("remotePath") ?: ""
                    val local = call.argument<String>("localPath") ?: ""
                    scope.launch {
                        val localPath = smbHandler.downloadFile(share, remote, local)
                        result.success(localPath)
                    }
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
