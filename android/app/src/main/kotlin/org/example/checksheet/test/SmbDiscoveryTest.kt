package org.example.checksheet.test

import jcifs.context.SingletonContext
import jcifs.smb.NtlmPasswordAuthenticator
import jcifs.smb.SmbFile
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * jCIFS-ng를 사용하여 PC의 모든 공유 폴더 목록을 긁어올 수 있는지 테스트하는 클래스
 */
object SmbDiscoveryTest {

    suspend fun runTest(ip: String, user: String, pass: String): List<String> = withContext(Dispatchers.IO) {
        val result = mutableListOf<String>()
        try {
            // 1. 인증 정보 설정
            val auth = NtlmPasswordAuthenticator(null, user, pass)
            val context = SingletonContext.getInstance().withCredentials(auth)
            
            // 2. 루트 주소 접속 (smb://IP/)
            val rootUrl = "smb://$ip/"
            val rootDir = SmbFile(rootUrl, context)
            
            // 3. 목록 추출
            val shares = rootDir.list() ?: emptyArray()
            for (share in shares) {
                // 관리용 공유($)를 제외하고 이름만 추출
                if (!share.endsWith("$/")) {
                    result.add(share.replace("/", ""))
                }
            }
        } catch (e: Exception) {
            result.add("TEST_FAILED: ${e.message}")
        }
        result
    }
}
