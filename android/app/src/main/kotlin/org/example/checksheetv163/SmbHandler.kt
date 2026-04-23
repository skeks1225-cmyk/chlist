package org.example.checksheetv163

import android.content.Context
import com.hierynomus.msdtyp.AccessMask
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

    suspend fun listShares(): List<String> = withContext(Dispatchers.IO) {
        try {
            val shares = session?.listShares() ?: emptyList()
            shares.map { it.name }.filter { !it.endsWith("$") }
        } catch (e: Exception) {
            emptyList<String>()
        }
    }

    suspend fun listFiles(shareName: String, path: String): List<Map<String, Any>> = withContext(Dispatchers.IO) {
        val result = mutableListOf<Map<String, Any>>()
        try {
            // ❗ DiskShare 타입 명시적 캐스팅으로 타입 추론 에러 해결
            val share = session?.connectShare(shareName) as? DiskShare
            share?.let { s ->
                val list = s.list(path)
                for (file in list) {
                    if (file.fileName == "." || file.fileName == "..") continue
                    result.add(mapOf(
                        "name" to file.fileName,
                        "isDirectory" to file.fileInformation.standardInformation.isDirectory
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
