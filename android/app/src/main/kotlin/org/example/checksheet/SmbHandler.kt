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
import com.hierynomus.smbj.share.FileIdBothDirectoryInformation
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.util.EnumSet
import java.util.concurrent.TimeUnit

class SmbHandler(private val context: Context) {
    private val config: SmbConfig = SmbConfig.builder()
        .withTimeout(15, TimeUnit.SECONDS)
        .withSoTimeout(15, TimeUnit.SECONDS)
        .build()
    
    private var client: SMBClient = SMBClient(config)
    private var connection: Connection? = null
    private var session: Session? = null

    // [1] connectSMB
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

    // [2] listShares (SMBJ 정석 구현)
    suspend fun listShares(): List<String> = withContext(Dispatchers.IO) {
        try {
            val shares = session?.listShares() ?: emptyList()
            // 숨김 공유($) 제외하고 일반 이름만 추출
            shares.map { it.name }.filter { !it.endsWith("$") }
        } catch (e: Exception) {
            // 실패 시 계약에 따라 빈 리스트 반환
            emptyList<String>()
        }
    }

    // [3] listFiles
    suspend fun listFiles(shareName: String, path: String): List<Map<String, Any>> = withContext(Dispatchers.IO) {
        val result = mutableListOf<Map<String, Any>>()
        try {
            val share = session?.connectShare(shareName) as? DiskShare
            share?.let { s ->
                val list = s.list(path)
                for (info in list) {
                    if (info.fileName == "." || info.fileName == "..") continue
                    
                    // 비트 연산으로 디렉토리 여부 판단 (0x00000010L = FILE_ATTRIBUTE_DIRECTORY)
                    val isDir = (info.fileAttributes and 0x00000010L) != 0L
                    
                    result.add(mapOf(
                        "name" to info.fileName,
                        "isDirectory" to isDir
                    ))
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        result
    }

    // [4] downloadFile
    suspend fun downloadFile(shareName: String, remotePath: String, localPath: String): String? = withContext(Dispatchers.IO) {
        try {
            val share = session?.connectShare(shareName) as? DiskShare
            share?.let { s ->
                val remoteFile = s.openFile(
                    remotePath,
                    EnumSet.of(AccessMask.GENERIC_READ),
                    null,
                    EnumSet.of(SMB2ShareAccess.FILE_SHARE_READ),
                    SMB2CreateDisposition.FILE_OPEN,
                    null
                )
                
                val localFile = File(localPath)
                localFile.parentFile?.mkdirs()
                
                remoteFile.inputStream.use { input ->
                    FileOutputStream(localFile).use { output ->
                        input.copyTo(output)
                    }
                }
                remoteFile.close()
                return@withContext localPath
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        null
    }

    fun disconnect() {
        try {
            session?.close()
            connection?.close()
        } catch (e: Exception) {}
    }
}
