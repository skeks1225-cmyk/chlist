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
            // ❗ 모든 호출에서 공통적으로 IP, User, Pass 추출
            val ip = call.argument<String>("ip")
            val user = call.argument<String>("user")
            val pass = call.argument<String>("pass")

            when (call.method) {
                "connectSMB" -> {
                    scope.launch { result.success(smbHandler.connect(ip!!, user!!, pass!!)) }
                }
                "listShares" -> {
                    scope.launch { result.success(smbHandler.listShares(ip, user, pass)) }
                }
                "listFiles" -> {
                    val share = call.argument<String>("share") ?: ""
                    val path = call.argument<String>("path") ?: ""
                    scope.launch { result.success(smbHandler.listFiles(ip, user, pass, share, path)) }
                }
                "downloadFile" -> {
                    val share = call.argument<String>("share") ?: ""
                    val remote = call.argument<String>("remotePath") ?: ""
                    val local = call.argument<String>("localPath") ?: ""
                    scope.launch { result.success(smbHandler.downloadFile(ip, user, pass, share, remote, local)) }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        scope.cancel()
    }
}
