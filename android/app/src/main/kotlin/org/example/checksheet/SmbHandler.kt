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

    suspend fun connect(ip: String, user: String, pass: String): String = withContext(Dispatchers.IO) {
        try {
            disconnect()
            connection = client.connect(ip)
            val auth = AuthenticationContext(user, pass.toCharArray(), "")
            session = connection?.authenticate(auth)
            if (session != null) "SUCCESS" else "인증 실패: 사용자 정보를 확인하세요."
        } catch (e: Exception) {
            val msg = e.message ?: e.toString()
            if (msg.contains("Connection refused")) "접속 거부: PC IP가 맞는지 확인하세요."
            else if (msg.contains("Timeout")) "응답 시간 초과: Tailscale 연결을 확인하세요."
            else msg
        }
    }

    // ❗ 2단계: 실시간 공유폴더 목록만 반환 (더미 데이터 삭제)
    suspend fun listShares(): List<String> = withContext(Dispatchers.IO) {
        val result = mutableListOf<String>()
        try {
            // ❗ 이미 세션이 있다면 진짜 목록 조회 시도
            val shares = session?.listShares()
            if (shares != null) {
                for (s in shares) {
                    val name = s.name
                    if (!name.endsWith("$")) {
                        result.add(name)
                    }
                }
            }
        } catch (e: Exception) {
            // 목록 조회 권한이 막혀있을 경우만 ERROR 메시지 반환
            result.add("ERROR: 공유 목록 조회 권한이 없습니다. (PC 설정을 확인하세요)")
        }
        result
    }

    suspend fun listFiles(shareName: String, path: String): List<Map<String, Any>> = withContext(Dispatchers.IO) {
        val result = mutableListOf<Map<String, Any>>()
        try {
            val share = session?.connectShare(shareName) as? DiskShare
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
        } catch (e: Exception) {
            e.printStackTrace()
        }
        result
    }

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
        try {
            session?.close()
            connection?.close()
        } catch (e: Exception) {}
    }
}
