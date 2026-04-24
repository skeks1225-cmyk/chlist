package org.example.smb_scanner_test

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import jcifs.context.BaseContext
import jcifs.config.PropertyConfiguration
import jcifs.smb.NtlmPasswordAuthenticator
import jcifs.smb.SmbFile
import kotlinx.coroutines.*
import java.util.Properties

class MainActivity: FlutterActivity() {
    private val CHANNEL = "pure_smb_test/channel"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "scanShares") {
                val ip = call.argument<String>("ip") ?: ""
                val user = call.argument<String>("user") ?: ""
                val pass = call.argument<String>("pass") ?: ""

                CoroutineScope(Dispatchers.IO).launch {
                    try {
                        val prop = Properties()
                        // ❗ 최신 윈도우 및 Tailscale 환경을 위한 핵심 설정
                        prop.setProperty("jcifs.smb.client.minVersion", "SMB202")
                        prop.setProperty("jcifs.smb.client.maxVersion", "SMB311")
                        prop.setProperty("jcifs.smb.client.useExtendedSecurity", "true")
                        prop.setProperty("jcifs.resolveOrder", "DNS") // NetBIOS 무시하고 직접 접속
                        prop.setProperty("jcifs.smb.client.ipcSigningEnforced", "false")
                        
                        val config = PropertyConfiguration(prop)
                        val baseContext = BaseContext(config)
                        val auth = NtlmPasswordAuthenticator(null, user, pass)
                        val context = baseContext.withCredentials(auth)
                        
                        // ❗ 루트 주소 접속
                        val rootUrl = "smb://$ip/"
                        val server = SmbFile(rootUrl, context)
                        
                        // ❗ 리스트 긁어오기
                        val shares = server.list() ?: emptyArray()
                        val shareNames = shares.map { it.replace("/", "") }.filter { !it.endsWith("$") }
                        
                        withContext(Dispatchers.Main) {
                            result.success(shareNames)
                        }
                    } catch (e: Exception) {
                        withContext(Dispatchers.Main) {
                            // 에러 내용을 더 자세히 반환하여 원인 파악 도움
                            result.error("SCAN_ERROR", "${e.javaClass.simpleName}: ${e.message}", null)
                        }
                    }
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
