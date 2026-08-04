package org.example.checksheet

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch

@Composable
fun FileListScreen(smbHandler: SmbHandler, onFileClick: (String) -> Unit) {
    val scope = rememberCoroutineScope()
    var fileList by remember { mutableStateOf<List<Map<String, Any>>>(emptyList()) }
    var isLoading by remember { mutableStateOf(false) }

    // ❗ 실제 사용 시 환경 설정에서 불러와야 함
    val ip = "192.168.0.10"
    val user = "guest"
    val pass = ""
    val share = "data"
    val path = ""

    Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        Button(onClick = {
            scope.launch {
                isLoading = true
                fileList = smbHandler.listFiles(ip, user, pass, share, path)
                isLoading = false
            }
        }) {
            Text("SMB 파일 목록 불러오기")
        }

        if (isLoading) {
            CircularProgressIndicator()
        } else {
            LazyColumn {
                items(fileList) { file ->
                    val fileName = file["name"].toString()
                    val isDir = file["isDirectory"] as Boolean
                    Text(
                        text = if (isDir) "[DIR] $fileName" else fileName,
                        modifier = androidx.compose.ui.Modifier.padding(8.dp).then(
                            if (!isDir) androidx.compose.ui.Modifier.clickable { onFileClick(fileName) } else Modifier
                        )
                    )
                }
            }
        }
    }
}
