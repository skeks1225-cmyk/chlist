package org.example.checksheet

import android.content.Context
import jcifs.context.BaseContext
import jcifs.config.PropertyConfiguration
import jcifs.smb.NtlmPasswordAuthenticator
import jcifs.smb.SmbFile
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.util.Properties
import java.util.concurrent.TimeUnit

class SmbHandler(private val context: Context) {
    private var baseContext: BaseContext? = null
    
    // ❗ 메모리 유실 대비하여 매 호출마다 갱신 가능한 구조 유지
    private var lastIp: String? = null
    private var lastUser: String? = null
    private var lastPass: String? = null

    private suspend fun ensureContext(): BaseContext = withContext(Dispatchers.IO) {
        if (baseContext != null) return@withContext baseContext!!
        val prop = Properties()
        prop.setProperty("jcifs.smb.client.minVersion", "SMB202")
        prop.setProperty("jcifs.smb.client.maxVersion", "SMB311")
        prop.setProperty("jcifs.smb.client.useExtendedSecurity", "true")
        prop.setProperty("jcifs.resolveOrder", "DNS")
        prop.setProperty("jcifs.smb.client.ipcSigningEnforced", "false")
        val config = PropertyConfiguration(prop)
        val ctx = BaseContext(config)
        baseContext = ctx
        ctx
    }

    // ❗ 전달받은 정보로 즉시 인증 컨텍스트를 생성하는 헬퍼
    private suspend fun getAuthCtx(ip: String?, user: String?, pass: String?): jcifs.CIFSContext? {
        val finalIp = ip ?: lastIp ?: return null
        val finalUser = user ?: lastUser ?: ""
        val finalPass = pass ?: lastPass ?: ""
        
        // 정보 업데이트 (기억력 유지)
        lastIp = finalIp; lastUser = finalUser; lastPass = finalPass
        
        val ctx = ensureContext()
        val auth = NtlmPasswordAuthenticator(null, finalUser, finalPass)
        return ctx.withCredentials(auth)
    }

    suspend fun connect(ip: String, user: String, pass: String): String = withContext(Dispatchers.IO) {
        try {
            val ctx = getAuthCtx(ip, user, pass)
            val server = SmbFile("smb://$ip/", ctx!!)
            server.list()
            "SUCCESS"
        } catch (t: Throwable) { t.message ?: t.toString() }
    }

    suspend fun listShares(ip: String?, user: String?, pass: String?): List<String> = withContext(Dispatchers.IO) {
        val result = mutableListOf<String>()
        try {
            val ctx = getAuthCtx(ip, user, pass) ?: return@withContext result
            val server = SmbFile("smb://${ip ?: lastIp}/", ctx)
            val shares = server.list() ?: emptyArray()
            for (share in shares) {
                val name = share.replace("/", "")
                if (!name.endsWith("$")) result.add(name)
            }
        } catch (t: Throwable) { result.add("ERROR: ${t.message}") }
        result
    }

    suspend fun listFiles(ip: String?, user: String?, pass: String?, shareName: String, path: String): List<Map<String, Any>> = withContext(Dispatchers.IO) {
        val result = mutableListOf<Map<String, Any>>()
        try {
            val ctx = getAuthCtx(ip, user, pass) ?: return@withContext result
            val url = "smb://${ip ?: lastIp}/$shareName/${if (path.isEmpty()) "" else "$path/"}"
            val dir = SmbFile(url, ctx)
            val files = dir.listFiles() ?: emptyArray()
            for (f in files) {
                val name = f.name.replace("/", "")
                if (name == "." || name == "..") continue
                val map = mutableMapOf<String, Any>()
                map["name"] = name
                map["isDirectory"] = f.isDirectory
                result.add(map)
            }
        } catch (t: Throwable) {}
        result
    }

    suspend fun downloadFile(ip: String?, user: String?, pass: String?, shareName: String, remotePath: String, localPath: String): String? = withContext(Dispatchers.IO) {
        try {
            val ctx = getAuthCtx(ip, user, pass) ?: return@withContext null
            val currentIp = ip ?: lastIp

            val parentPath = File(remotePath).parent ?: ""
            val targetName = File(remotePath).name
            val parentUrl = "smb://$currentIp/$shareName/${if (parentPath.isEmpty()) "" else "$parentPath/"}"
            val parentDir = SmbFile(parentUrl, ctx)
            val files = parentDir.list() ?: emptyArray()
            
            var actualName = targetName
            for (f in files) {
                val cleanF = f.replace("/", "")
                if (cleanF.equals(targetName, ignoreCase = true)) {
                    actualName = cleanF
                    break
                }
            }

            val finalRemoteUrl = "smb://$currentIp/$shareName/${if (parentPath.isEmpty()) "" else "$parentPath/"}$actualName"
            val remoteFile = SmbFile(finalRemoteUrl, ctx)
            val localFile = File(localPath)

            if (localFile.exists()) {
                if (localFile.length() == remoteFile.length() && Math.abs(localFile.lastModified() - remoteFile.lastModified()) < 2000) {
                    return@withContext localPath
                }
            }

            localFile.parentFile?.mkdirs()
            remoteFile.inputStream.use { input -> FileOutputStream(localFile).use { output -> input.copyTo(output) } }
            localFile.setLastModified(remoteFile.lastModified())
            return@withContext localPath
        } catch (t: Throwable) { null }
    }

    fun disconnect() {}
}
