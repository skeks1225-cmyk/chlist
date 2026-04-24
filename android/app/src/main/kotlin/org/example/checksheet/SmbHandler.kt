package org.example.checksheet

import android.content.Context
import com.hierynomus.msdtyp.AccessMask
import com.hierynomus.mssmb2.SMB2CreateDisposition
import com.hierynomus.mssmb2.SMB2ShareAccess
import com.hierynomus.smbj.SMBClient
import com.hierynomus.smbj.SmbConfig
import com.hierynomus.smbj.auth.AuthenticationContext
import com.hierynomus.smbj.connection.Connection
import com.hierynomus.smbj.session.Session
import com.hierynomus.smbj.share.DiskShare
import jcifs.context.BaseContext
import jcifs.config.PropertyConfiguration
import jcifs.smb.NtlmPasswordAuthenticator
import jcifs.smb.SmbFile
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.util.EnumSet // ❗ 누락되었던 필수 임포트 추가
import java.util.Properties
import java.util.concurrent.TimeUnit

class SmbHandler(private val context: Context) {
    // --- 1. SMBJ 엔진 (고속 전송용) ---
    private val smbjConfig = SmbConfig.builder()
        .withTimeout(15, TimeUnit.SECONDS)
        .withSoTimeout(15, TimeUnit.SECONDS)
        .build()
    private var smbjClient: SMBClient = SMBClient(smbjConfig)
    private var smbjConnection: Connection? = null
    private var smbjSession: Session? = null

    // --- 2. jCIFS-ng 엔진 (똑똑한 정찰용) ---
    private var jcifsBaseContext: BaseContext? = null

    private var lastIp: String? = null
    private var lastUser: String? = null
    private var lastPass: String? = null

    init {
        val prop = Properties()
        prop.setProperty("jcifs.smb.client.minVersion", "SMB202")
        prop.setProperty("jcifs.smb.client.maxVersion", "SMB311")
        prop.setProperty("jcifs.smb.client.useExtendedSecurity", "true")
        prop.setProperty("jcifs.resolveOrder", "DNS")
        val config = PropertyConfiguration(prop)
        jcifsBaseContext = BaseContext(config)
    }

    private suspend fun ensureConnected(): Boolean {
        if (smbjSession != null && smbjConnection?.isConnected == true) return true
        val ip = lastIp ?: return false
        return connect(ip, lastUser ?: "", lastPass ?: "") == "SUCCESS"
    }

    suspend fun connect(ip: String, user: String, pass: String): String = withContext(Dispatchers.IO) {
        try {
            disconnect()
            lastIp = ip; lastUser = user; lastPass = pass
            smbjConnection = smbjClient.connect(ip)
            val auth = AuthenticationContext(user, pass.toCharArray(), "")
            smbjSession = smbjConnection?.authenticate(auth)
            if (smbjSession != null) "SUCCESS" else "인증 실패"
        } catch (e: Exception) {
            e.message ?: e.toString()
        }
    }

    suspend fun listShares(): List<String> = withContext(Dispatchers.IO) {
        val result = mutableListOf<String>()
        try {
            val ip = lastIp ?: return@withContext result
            val auth = NtlmPasswordAuthenticator(null, lastUser ?: "", lastPass ?: "")
            val ctx = jcifsBaseContext?.withCredentials(auth)
            val rootUrl = "smb://$ip/"
            val server = SmbFile(rootUrl, ctx!!)
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

    suspend fun listFiles(shareName: String, path: String): List<Map<String, Any>> = withContext(Dispatchers.IO) {
        val result = mutableListOf<Map<String, Any>>()
        try {
            if (!ensureConnected()) return@withContext result
            val share = smbjSession?.connectShare(shareName) as? DiskShare
            if (share != null) {
                val list = share.list(path)
                for (info in list) {
                    val name = info.fileName
                    if (name == "." || name == "..") continue
                    val isDir = (info.fileAttributes and 0x00000010L) != 0L
                    val map = mutableMapOf<String, Any>()
                    map["name"] = name
                    map["isDirectory"] = isDir
                    result.add(map)
                }
            }
        } catch (e: Exception) { e.printStackTrace() }
        result
    }

    suspend fun downloadFile(shareName: String, remotePath: String, localPath: String): String? = withContext(Dispatchers.IO) {
        try {
            if (!ensureConnected()) return@withContext null
            val share = smbjSession?.connectShare(shareName) as? DiskShare ?: return@withContext null

            val parentPath = File(remotePath).parent ?: ""
            val targetName = File(remotePath).name
            val fileList = share.list(parentPath)
            var actualRemotePath = remotePath
            for (f in fileList) {
                if (f.fileName.equals(targetName, ignoreCase = true)) {
                    actualRemotePath = if (parentPath.isEmpty()) f.fileName else "$parentPath/${f.fileName}"
                    break
                }
            }

            val remoteInfo = share.getFileInformation(actualRemotePath)
            val remoteSize = remoteInfo.standardInformation.endOfFile
            val remoteTime = remoteInfo.basicInformation.lastWriteTime.toEpoch(TimeUnit.MILLISECONDS)

            val localFile = File(localPath)
            if (localFile.exists()) {
                if (localFile.length() == remoteSize && Math.abs(localFile.lastModified() - remoteTime) < 2000) {
                    return@withContext localPath
                }
            }

            localFile.parentFile?.mkdirs()
            // ❗ EnumSet.of 사용을 위해 상단에 import 추가 완료
            val remoteFile = share.openFile(actualRemotePath, EnumSet.of(AccessMask.GENERIC_READ), null, EnumSet.of(SMB2ShareAccess.FILE_SHARE_READ), SMB2CreateDisposition.FILE_OPEN, null)
            remoteFile.inputStream.use { input -> FileOutputStream(localFile).use { output -> input.copyTo(output) } }
            remoteFile.close()
            localFile.setLastModified(remoteTime)
            return@withContext localPath
        } catch (e: Exception) { e.printStackTrace() }
        null
    }

    fun disconnect() {
        try { smbjSession?.close(); smbjConnection?.close() } catch (e: Exception) {}
    }
}
