package org.example.smbtest.smb_test

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import jcifs.context.SingletonContext
import jcifs.smb.NtlmPasswordAuthenticator
import jcifs.smb.SmbFile
import kotlinx.coroutines.*
import java.util.Properties

class MainActivity: FlutterActivity() {
    private val CHANNEL = "org.example.smbtest/test"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getShareList") {
                val ip = call.argument<String>("ip") ?: ""
                val user = call.argument<String>("user") ?: ""
                val pass = call.argument<String>("pass") ?: ""

                CoroutineScope(Dispatchers.IO).launch {
                    try {
                        val prop = Properties()
                        prop.setProperty("jcifs.smb.client.minVersion", "SMB202")
                        prop.setProperty("jcifs.smb.client.maxVersion", "SMB311")
                        
                        val baseContext = SingletonContext.getInstance().withProperties(prop)
                        val auth = NtlmPasswordAuthenticator(null, user, pass)
                        val context = baseContext.withCredentials(auth)
                        
                        val rootUrl = "smb://$ip/"
                        val rootDir = SmbFile(rootUrl, context)
                        
                        val shares = rootDir.list() ?: emptyArray()
                        val shareNames = shares.map { it.replace("/", "") }.filter { !it.endsWith("$") }
                        
                        withContext(Dispatchers.Main) {
                            result.success(shareNames)
                        }
                    } catch (e: Exception) {
                        withContext(Dispatchers.Main) {
                            result.error("TEST_ERROR", e.message, null)
                        }
                    }
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
