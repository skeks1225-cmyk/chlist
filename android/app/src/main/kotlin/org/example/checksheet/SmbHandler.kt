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
import java.util.EnumSet

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

    suspend fun listShares(): List<String> = withContext(Dispatchers.IO) {
        try {
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
                    
                    // ❗ 지피티가 제안한 가장 안전한 비트 연산 방식으로 교체
                    val isDir = (file.fileAttributes and 0x00000010L) != 0L
                    
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
