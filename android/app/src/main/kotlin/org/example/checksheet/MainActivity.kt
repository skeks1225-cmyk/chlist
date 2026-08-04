package org.example.checksheet

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.platform.LocalContext

class MainActivity : ComponentActivity() {
    private lateinit var smbHandler: SmbHandler

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        smbHandler = SmbHandler(this)

        setContent {
            val context = LocalContext.current
            MaterialTheme {
                // 진입점: 파일 목록 화면
                FileListScreen(smbHandler) { fileName ->
                    val intent = Intent(context, PdfViewerActivity::class.java).apply {
                        putExtra("filePath", "/storage/emulated/0/Download/CheckSheet/$fileName")
                    }
                    context.startActivity(intent)
                }
            }
        }
    }
}

}
