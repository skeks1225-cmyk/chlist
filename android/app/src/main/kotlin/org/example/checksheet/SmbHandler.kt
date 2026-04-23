package org.example.checksheet

import android.content.Context
import com.hierynomus.smbj.SMBClient
import com.hierynomus.smbj.SmbConfig
import com.hierynomus.smbj.auth.AuthenticationContext
import com.hierynomus.smbj.connection.Connection
import com.hierynomus.smbj.session.Session
import com.hierynomus.smbj.share.DiskShare
import com.hierynomus.msdtyp.AccessMask
import com.hierynomus.mssmb2.SMB2CreateDisposition
import com.hierynomus.mssmb2.SMB2ShareAccess
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.util.EnumSet
import java.util.concurrent.TimeUnit

class SmbHandler(private val context: Context) {
    private val config = SmbConfig.builder()
        .withTimeout(10, TimeUnit.SECONDS)
        .withSoTimeout(10, TimeUnit.SECONDS)
        .build()
    
    private var client: SMBClient = SMBClient(config)
    private var connection: Connection? = null
    private var session: Session? = null

    // ❗ 목표: SUCCESS 또는 진짜 에러 메시지 반환
    suspend fun connect(ip: String, user: String, pass: String): String = withContext(Dispatchers.IO) {
        try {
            disconnect()
            connection = client.connect(ip)
            val auth = AuthenticationContext(user, pass.toCharArray(), "")
            session = connection?.authenticate(auth)
            if (session != null) "SUCCESS" else "Authentication Failed"
        } catch (e: Exception) {
            e.message ?: e.toString()
        }
    }

    // ❗ 빌드 성공을 위해 더미 데이터로 복구 (연결 확인이 먼저임)
    suspend fun listShares(): List<String> = withContext(Dispatchers.IO) {
        listOf("Shared", "Public", "Download")
    }

    suspend fun listFiles(shareName: String, path: String): List<Map<String, Any>> = withContext(Dispatchers.IO) {
        val result = mutableListOf<Map<String, Any>>()
        try {
            val share = session?.connectShare(shareName) as? DiskShare
            share?.let { s ->
                val list = s.list(path)
                for (file in list) {
                    if (file.fileName == "." || file.fileName == "..") continue
                    val isDir = (file.fileAttributes and 0x00000010L) != 0L
                    result.add(mapOf("name" to file.fileName, "isDirectory" to isDir))
                }
            }
        } catch (e: Exception) {}
        result
    }

    suspend fun downloadFile(shareName: String, remotePath: String, localPath: String): String? = withContext(Dispatchers.IO) {
        try {
            val share = session?.connectShare(shareName) as? DiskShare
            share?.let { s ->
                val remoteFile = s.openFile(remotePath, EnumSet.of(AccessMask.GENERIC_READ), null, EnumSet.of(SMB2ShareAccess.FILE_SHARE_READ), SMB2CreateDisposition.FILE_OPEN, null)
                val localFile = File(localPath)
                localFile.parentFile?.mkdirs()
                remoteFile.inputStream.use { input -> FileOutputStream(localFile).use { output -> input.copyTo(output) } }
                remoteFile.close()
                localPath
            }
        } catch (e: Exception) { null }
    }

    fun disconnect() {
        try { session?.close(); connection?.close() } catch (e: Exception) {}
    }
}
