package org.example.checksheet.test

import jcifs.context.SingletonContext
import jcifs.smb.NtlmPasswordAuthenticator
import jcifs.smb.SmbFile
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.Properties

/**
 * jCIFS-ng를 사용하여 PC의 모든 공유 폴더 목록을 긁어올 수 있는지 테스트하는 클래스
 */
object SmbDiscoveryTest {

    suspend fun runTest(ip: String, user: String, pass: String): List<String> = withContext(Dispatchers.IO) {
        val result = mutableListOf<String>()
        try {
            // ❗ 1. jCIFS 속성 초기화 (충돌 방지)
            val prop = Properties()
            prop.setProperty("jcifs.smb.client.minVersion", "SMB202")
            prop.setProperty("jcifs.smb.client.maxVersion", "SMB311")
            
            val baseContext = SingletonContext.getInstance().withProperties(prop)
            val auth = NtlmPasswordAuthenticator(null, user, pass)
            val context = baseContext.withCredentials(auth)
            
            // ❗ 2. 루트 주소 접속 (정석 smb://IP/ 형식)
            val rootUrl = "smb://$ip/"
            val rootDir = SmbFile(rootUrl, context)
            
            // ❗ 3. 목록 추출 (시간이 걸릴 수 있음)
            val shares = rootDir.list() ?: emptyArray()
            for (share in shares) {
                if (!share.endsWith("$/")) {
                    result.add(share.replace("/", ""))
                }
            }
        } catch (e: Exception) {
            // 앱이 죽지 않도록 모든 에러를 텍스트로 처리
            result.add("ERROR: ${e.message ?: e.toString()}")
        }
        result
    }
}
