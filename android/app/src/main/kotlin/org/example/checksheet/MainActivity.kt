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

        // ❗ 엔진 초기화
        smbHandler = SmbHandler(this)

        // ❗ 명령어 통로(MethodChannel) 연결
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                // ❗ 1단계: 접속 테스트 통로 복구
                "connectSMB" -> {
                    val ip = call.argument<String>("ip") ?: ""
                    val user = call.argument<String>("user") ?: ""
                    val pass = call.argument<String>("pass") ?: ""
                    
                    scope.launch {
                        // Kotlin 엔진 호출
                        val res = smbHandler.connect(ip, user, pass)
                        // Flutter UI로 결과 전송 (SUCCESS 또는 에러메시지)
                        result.success(res)
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
