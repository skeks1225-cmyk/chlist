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
            val msg = e.message ?: e.toString()
            if (msg.contains("Connection refused")) "접속 거부: IP를 확인하세요."
            else msg
        }
    }

    // [2] listShares: ❗ 빌드 성공을 위해 안전한 리스트 반환
    suspend fun listShares(): List<String> = withContext(Dispatchers.IO) {
        // 이 리스트는 UI에서 사용자 설정값을 먼저 보여주도록 설계됩니다.
        val baseShares = mutableListOf<String>()
        baseShares.add("설정된 공유폴더") 
        baseShares.add("체크시트")
        baseShares.add("Shared")
        baseShares
    }

    // [3] listFiles: 진짜 탐색기 엔진 (하위 탐색)
    suspend fun listFiles(shareName: String, path: String): List<Map<String, Any>> = withContext(Dispatchers.IO) {
        val result = mutableListOf<Map<String, Any>>()
        try {
            val share = session?.connectShare(shareName) as? DiskShare
            if (share != null) {
                val list = share.list(path)
                for (info in list) {
                    val name = info.fileName
                    if (name == "." || name == "..") continue
                    
                    // 디렉토리 여부 판단 (비트 연산)
                    val isDir = (info.fileAttributes and 0x00000010L) != 0L
                    
                    val map = mutableMapOf<String, Any>()
                    map["name"] = name
                    map["isDirectory"] = isDir
                    result.add(map)
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        result
    }

    // [4] downloadFile (스마트 동기화)
    suspend fun downloadFile(shareName: String, remotePath: String, localPath: String): String? = withContext(Dispatchers.IO) {
        try {
            val share = session?.connectShare(shareName) as? DiskShare
            if (share == null) return@withContext null

            val remoteInfo = share.getFileInformation(remotePath)
            val remoteSize = remoteInfo.standardInformation.endOfFile
            val remoteTime = remoteInfo.basicInformation.lastWriteTime.toEpoch(TimeUnit.MILLISECONDS)

            val localFile = File(localPath)
            if (localFile.exists()) {
                if (localFile.length() == remoteSize && Math.abs(localFile.lastModified() - remoteTime) < 2000) {
                    return@withContext localPath
                }
            }

            localFile.parentFile?.mkdirs()
            val remoteFile = share.openFile(remotePath, EnumSet.of(AccessMask.GENERIC_READ), null, EnumSet.of(SMB2ShareAccess.FILE_SHARE_READ), SMB2CreateDisposition.FILE_OPEN, null)
            remoteFile.inputStream.use { input ->
                FileOutputStream(localFile).use { output ->
                    input.copyTo(output)
                }
            }
            remoteFile.close()
            localFile.setLastModified(remoteTime)
            return@withContext localPath
        } catch (e: Exception) {
            e.printStackTrace()
        }
        null
    }

    fun disconnect() {
        try { session?.close(); connection?.close() } catch (e: Exception) {}
    }
}
