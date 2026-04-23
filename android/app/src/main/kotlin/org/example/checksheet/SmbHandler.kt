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

    suspend fun listShares(): List<String> = withContext(Dispatchers.IO) {
        val result = mutableListOf<String>()
        try {
            val shares = session?.listShares()
            if (shares != null) {
                for (s in shares) {
                    if (!s.name.endsWith("$")) result.add(s.name)
                }
            }
            if (result.isEmpty()) result.add("체크시트")
        } catch (e: Exception) {
            result.add("ERROR: 공유 목록 조회 실패 (${e.message})")
        }
        result
    }

    suspend fun listFiles(shareName: String, path: String): List<Map<String, Any>> = withContext(Dispatchers.IO) {
        val result = mutableListOf<Map<String, Any>>()
        try {
            val share = session?.connectShare(shareName) as? DiskShare
            share?.let { s ->
                val list = s.list(path)
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
        } catch (e: Exception) {}
        result
    }

    // ❗ [4] 스마트 동기화 다운로드 (날짜/용량 비교)
    suspend fun downloadFile(shareName: String, remotePath: String, localPath: String): String? = withContext(Dispatchers.IO) {
        try {
            val share = session?.connectShare(shareName) as? DiskShare
            if (share == null) return@withContext null

            // 1. PC 원본 파일 정보 획득
            val remoteInfo = share.getFileInformation(remotePath)
            val remoteSize = remoteInfo.standardInformation.endOfFile
            val remoteTime = remoteInfo.basicInformation.lastWriteTime.toEpoch(TimeUnit.MILLISECONDS)

            val localFile = File(localPath)
            
            // 2. 내 폰에 이미 파일이 있는지, 그리고 똑같은지 비교
            if (localFile.exists()) {
                val localSize = localFile.length()
                val localTime = localFile.lastModified()

                // 용량과 수정 시간이 거의 일치하면 다운로드 생략 (1초 오차 허용)
                if (localSize == remoteSize && Math.abs(localTime - remoteTime) < 2000) {
                    return@withContext localPath 
                }
            }

            // 3. 파일이 없거나 다르면 다운로드 수행
            localFile.parentFile?.mkdirs()
            val remoteFile = share.openFile(
                remotePath,
                EnumSet.of(AccessMask.GENERIC_READ),
                null,
                EnumSet.of(SMB2ShareAccess.FILE_SHARE_READ),
                SMB2CreateDisposition.FILE_OPEN,
                null
            )
            
            remoteFile.inputStream.use { input ->
                FileOutputStream(localFile).use { output ->
                    input.copyTo(output)
                }
            }
            remoteFile.close()

            // 4. 다운로드 후 로컬 파일의 시간을 PC 원본 시간과 동기화 (다음에 비교할 때 사용)
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
