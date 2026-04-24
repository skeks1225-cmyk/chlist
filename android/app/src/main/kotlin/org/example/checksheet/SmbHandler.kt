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
    
    private var lastIp: String? = null
    private var lastUser: String? = null
    private var lastPass: String? = null

    // 비동기 초기화로 메인 쓰레드 튕김 방지
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

    // [1] connect
    suspend fun connect(ip: String, user: String, pass: String): String = withContext(Dispatchers.IO) {
        try {
            lastIp = ip; lastUser = user; lastPass = pass
            val ctx = ensureContext()
            val auth = NtlmPasswordAuthenticator(null, user, pass)
            val authenticatedCtx = ctx.withCredentials(auth)
            
            val rootUrl = "smb://$ip/"
            val server = SmbFile(rootUrl, authenticatedCtx)
            
            server.list()
            "SUCCESS"
        } catch (t: Throwable) {
            t.message ?: t.toString()
        }
    }

    private suspend fun getAuthenticatedContext(): jcifs.CIFSContext? {
        val ctx = ensureContext()
        if (lastIp == null) return null
        val auth = NtlmPasswordAuthenticator(null, lastUser ?: "", lastPass ?: "")
        return ctx.withCredentials(auth)
    }

    // [2] listShares (진짜 자동 목록)
    suspend fun listShares(): List<String> = withContext(Dispatchers.IO) {
        val result = mutableListOf<String>()
        try {
            val ip = lastIp ?: return@withContext result
            val ctx = getAuthenticatedContext() ?: return@withContext result
            val rootUrl = "smb://$ip/"
            val server = SmbFile(rootUrl, ctx)
            val shares = server.list() ?: emptyArray()
            for (share in shares) {
                val name = share.replace("/", "")
                if (!name.endsWith("$")) result.add(name)
            }
        } catch (t: Throwable) {
            result.add("ERROR: ${t.javaClass.simpleName}: ${t.message}")
        }
        result
    }

    // [3] listFiles
    suspend fun listFiles(shareName: String, path: String): List<Map<String, Any>> = withContext(Dispatchers.IO) {
        val result = mutableListOf<Map<String, Any>>()
        try {
            val ip = lastIp ?: return@withContext result
            val ctx = getAuthenticatedContext() ?: return@withContext result
            val url = "smb://$ip/$shareName/${if (path.isEmpty()) "" else "$path/"}"
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

    // [4] downloadFile (스마트 동기화 & 대소문자 무시)
    suspend fun downloadFile(shareName: String, remotePath: String, localPath: String): String? = withContext(Dispatchers.IO) {
        try {
            val ip = lastIp ?: return@withContext null
            val ctx = getAuthenticatedContext() ?: return@withContext null
            
            val parentPath = File(remotePath).parent?.replace("\\", "/") ?: ""
            val targetName = File(remotePath).name
            val parentUrl = "smb://$ip/$shareName/${if (parentPath.isEmpty()) "" else "$parentPath/"}"
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

            val finalRemoteUrl = "smb://$ip/$shareName/${if (parentPath.isEmpty()) "" else "$parentPath/"}$actualName"
            val remoteFile = SmbFile(finalRemoteUrl, ctx)
            val localFile = File(localPath)

            if (localFile.exists()) {
                if (localFile.length() == remoteFile.length() && Math.abs(localFile.lastModified() - remoteFile.lastModified()) < 2000) {
                    return@withContext localPath
                }
            }

            localFile.parentFile?.mkdirs()
            remoteFile.inputStream.use { input ->
                FileOutputStream(localFile).use { output ->
                    input.copyTo(output)
                }
            }
            localFile.setLastModified(remoteFile.lastModified())
            return@withContext localPath
        } catch (t: Throwable) {
            t.printStackTrace()
        }
        null
    }

    fun disconnect() {}
}
