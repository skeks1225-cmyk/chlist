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
// ❗ 정석 위치: msfscc.fileinformation 패키지 참조
import com.hierynomus.msfscc.fileinformation.FileIdBothDirectoryInformation
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

    // [1] connectSMB (불변 계약 준수)
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

    // [2] listShares (불변 계약 준수 - 람다 제거 버전)
    suspend fun listShares(): List<String> = withContext(Dispatchers.IO) {
        val result = mutableListOf<String>()
        try {
            val shares = session?.listShares()
            if (shares != null) {
                for (share in shares) {
                    val name = share.name
                    if (!name.endsWith("$")) {
                        result.add(name)
                    }
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        result
    }

    // [3] listFiles (불변 계약 준수 - 람다 제거 버전)
    suspend fun listFiles(shareName: String, path: String): List<Map<String, Any>> = withContext(Dispatchers.IO) {
        val result = mutableListOf<Map<String, Any>>()
        try {
            val share = session?.connectShare(shareName) as? DiskShare
            share?.let { s ->
                val list = s.list(path)
                for (info in list) {
                    val fileName = info.fileName
                    if (fileName == "." || fileName == "..") continue
                    
                    // 비트 연산으로 디렉토리 여부 판단
                    val isDir = (info.fileAttributes and 0x00000010L) != 0L
                    
                    val fileMap = mutableMapOf<String, Any>()
                    fileMap["name"] = fileName
                    fileMap["isDirectory"] = isDir
                    result.add(fileMap)
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        result
    }

    // [4] downloadFile (불변 계약 준수)
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
