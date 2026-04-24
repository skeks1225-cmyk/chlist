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

    init {
        // jCIFS-ng 환경 설정 고정 (Tailscale 및 최신 윈도우 대응)
        val prop = Properties()
        prop.setProperty("jcifs.smb.client.minVersion", "SMB202")
        prop.setProperty("jcifs.smb.client.maxVersion", "SMB311")
        prop.setProperty("jcifs.smb.client.useExtendedSecurity", "true")
        prop.setProperty("jcifs.resolveOrder", "DNS")
        prop.setProperty("jcifs.smb.client.ipcSigningEnforced", "false")
        val config = PropertyConfiguration(prop)
        baseContext = BaseContext(config)
    }

    // [1] connect (인증 정보 저장 및 테스트)
    suspend fun connect(ip: String, user: String, pass: String): String = withContext(Dispatchers.IO) {
        try {
            lastIp = ip; lastUser = user; lastPass = pass
            val auth = NtlmPasswordAuthenticator(null, user, pass)
            val ctx = baseContext?.withCredentials(auth)
            val rootUrl = "smb://$ip/"
            val server = SmbFile(rootUrl, ctx!!)
            
            // 실제 접속 시도 (목록 조회를 통해 인증 확인)
            server.list()
            "SUCCESS"
        } catch (e: Exception) {
            e.message ?: e.toString()
        }
    }

    private fun getAuthenticatedContext(): jcifs.CIFSContext? {
        val auth = NtlmPasswordAuthenticator(null, lastUser ?: "", lastPass ?: "")
        return baseContext?.withCredentials(auth)
    }

    // [2] listShares (진짜 자동 탐색기)
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
        } catch (e: Exception) {
            result.add("ERROR: ${e.message}")
        }
        result
    }

    // [3] listFiles (하위 탐색)
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
        } catch (e: Exception) {}
        result
    }

    // [4] downloadFile (스마트 동기화 및 대소문자 무시)
    suspend fun downloadFile(shareName: String, remotePath: String, localPath: String): String? = withContext(Dispatchers.IO) {
        try {
            val ip = lastIp ?: return@withContext null
            val ctx = getAuthenticatedContext() ?: return@withContext null
            
            // ❗ 대소문자 무시를 위해 실제 파일명 검색
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

            // 스마트 동기화 대조
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
        } catch (e: Exception) {
            e.printStackTrace()
        }
        null
    }

    fun disconnect() {
        // jCIFS-ng는 세션을 직접 닫을 필요가 없으나 구조 유지를 위해 둠
    }
}
