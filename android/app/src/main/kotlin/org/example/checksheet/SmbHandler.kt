package org.example.checksheet

import android.content.Context
import com.hierynomus.msdtyp.AccessMask
import com.hierynomus.msfscc.FileAttributes
import com.hierynomus.mssmb2.SMB2CreateDisposition
import com.hierynomus.mssmb2.SMB2ShareAccess
import com.hierynomus.smbj.SMBClient
import com.hierynomus.smbj.auth.AuthenticationContext
import com.hierynomus.smbj.connection.Connection
import com.hierynomus.smbj.session.Session
import com.hierynomus.smbj.share.DiskShare
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream

class SmbHandler(private val context: Context) {
    private var client: SMBClient = SMBClient()
    private var connection: Connection? = null
    private var session: Session? = null

    suspend fun connect(ip: String, user: String, pass: String): Boolean = withContext(Dispatchers.IO) {
        try {
            disconnect()
            connection = client.connect(ip)
            val auth = AuthenticationContext(user, pass.toCharArray(), "")
            session = connection?.authenticate(auth)
            session != null
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    // ❗ SMBJ에서 공유 목록 조회는 기본 지원되지 않으므로, 연결 성공 시 빈 리스트 대신 더미 또는 직접 입력 유도
    suspend fun listShares(): List<String> = withContext(Dispatchers.IO) {
        try {
            // 현재는 엑셀/PDF가 들어있는 실제 공유 폴더명을 UI에서 바로 쓰도록 하거나,
            // 기본적으로 많이 쓰이는 명칭들을 테스트용으로 제공합니다.
            listOf("Shared", "Public", "Users", "Documents") 
        } catch (e: Exception) {
            emptyList<String>()
        }
    }

    suspend fun listFiles(shareName: String, path: String): List<Map<String, Any>> = withContext(Dispatchers.IO) {
        val result = mutableListOf<Map<String, Any>>()
        try {
            val share = session?.connectShare(shareName) as? DiskShare
            share?.let { s ->
                val list = s.list(path)
                for (file in list) {
                    if (file.fileName == "." || file.fileName == "..") continue
                    
                    // ❗ 정석 API: fileAttributes를 통해 디렉토리 판별
                    val isDir = file.fileAttributes.contains(FileAttributes.FILE_ATTRIBUTE_DIRECTORY)
                    
                    result.add(mapOf(
                        "name" to file.fileName,
                        "isDirectory" to isDir
                    ))
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
            share?.let { s ->
                val remoteFile = s.openFile(
                    remotePath,
                    setOf(AccessMask.GENERIC_READ),
                    null,
                    setOf(SMB2ShareAccess.FILE_SHARE_READ),
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
