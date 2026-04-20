package com.example.checksheet

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.Settings
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import com.github.barteksc.pdfviewer.PDFView
import java.io.File

// --- 1. 데이터 모델 (상태값 한글화) ---
data class CheckItem(
    val no: String,
    val itemCode: String,
    val quantity: String,
    var status: String = "미검사" // "완료", "부족", "재작업", "미검사"
)

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            CheckSheetNativeApp()
        }
    }
}

@Composable
fun CheckSheetNativeApp() {
    val context = LocalContext.current
    var hasPermission by remember { mutableStateOf(checkStoragePermission()) }
    var currentScreen by remember { mutableStateOf("LIST") } 
    var selectedItem by remember { mutableStateOf<CheckItem?>(null) }
    
    // 샘플 데이터 (다음 단계에서 엑셀 로딩 추가 예정)
    val checkList = remember {
        mutableStateListOf(
            CheckItem("1", "A-001", "10"),
            CheckItem("2", "B-005", "5"),
            CheckItem("3", "한글파일명테스트", "1")
        )
    }

    Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        if (!hasPermission) {
            Column(
                modifier = Modifier.fillMaxSize(),
                verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text("Storage Permission Required", fontSize = 20.sp, fontWeight = FontWeight.Bold)
                Spacer(modifier = Modifier.height(20.dp))
                Button(onClick = { 
                    requestStoragePermission(context as ComponentActivity)
                    Toast.makeText(context, "권한 승인 후 앱을 다시 켜주세요", Toast.LENGTH_LONG).show()
                }) {
                    Text("Grant All Files Access")
                }
            }
        } else {
            when (currentScreen) {
                "LIST" -> ListScreen(
                    checkList = checkList,
                    onItemClick = { item ->
                        selectedItem = item
                        currentScreen = "VIEWER"
                    }
                )
                "VIEWER" -> ViewerScreen(
                    item = selectedItem!!,
                    onBack = { currentScreen = "LIST" },
                    onStatusChange = { newStatus ->
                        val index = checkList.indexOfFirst { it.itemCode == selectedItem?.itemCode }
                        if (index != -1) {
                            checkList[index] = selectedItem!!.copy(status = newStatus)
                            selectedItem = checkList[index]
                        }
                    }
                )
            }
        }
    }
}

@Composable
fun ListScreen(checkList: List<CheckItem>, onItemClick: (CheckItem) -> Unit) {
    Column(modifier = Modifier.fillMaxSize()) {
        Text(
            "체크시트 항목 목록", 
            modifier = Modifier.padding(16.dp), 
            fontSize = 22.sp, 
            fontWeight = FontWeight.Bold
        )
        
        LazyColumn(modifier = Modifier.fillMaxSize()) {
            items(checkList) { item ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(4.dp)
                        .background(if (item.status != "미검사") Color(0xFFF0F0F0) else Color.Transparent)
                        .clickable { onItemClick(item) }
                        .padding(16.dp),
                    verticalAlignment = Alignment.CenterHorizontally
                ) {
                    Text(item.no, modifier = Modifier.weight(0.1f))
                    Text(item.itemCode, modifier = Modifier.weight(0.4f), fontWeight = FontWeight.Bold)
                    Text("수량: ${item.quantity}", modifier = Modifier.weight(0.2f))
                    Text(
                        item.status, 
                        modifier = Modifier.weight(0.3f),
                        color = when(item.status) {
                            "완료" -> Color(0xFF4CAF50)
                            "부족" -> Color(0xFFFFC107)
                            "재작업" -> Color(0xFFF44336)
                            else -> Color.Gray
                        },
                        fontWeight = FontWeight.Bold
                    )
                }
                Divider(thickness = 0.5.dp, color = Color.LightGray)
            }
        }
    }
}

@Composable
fun ViewerScreen(item: CheckItem, onBack: () -> Unit, onStatusChange: (String) -> Unit) {
    val pdfFile = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "CheckSheet/${item.itemCode}.pdf")

    Column(modifier = Modifier.fillMaxSize()) {
        Row(
            modifier = Modifier.fillMaxWidth().background(Color.DarkGray).padding(8.dp),
            verticalAlignment = Alignment.CenterHorizontally
        ) {
            Button(onClick = onBack) { Text("Back") }
            Spacer(modifier = Modifier.width(16.dp))
            Text(item.itemCode, color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Bold)
        }

        Box(modifier = Modifier.weight(1f).fillMaxWidth()) {
            if (pdfFile.exists()) {
                AndroidView(
                    factory = { ctx ->
                        PDFView(ctx, null).apply {
                            fromFile(pdfFile)
                                .enableSwipe(true)
                                .swipeHorizontal(false)
                                .load()
                        }
                    },
                    modifier = Modifier.fillMaxSize()
                )
            } else {
                Column(modifier = Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("PDF 파일을 찾을 수 없습니다", color = Color.Red, fontWeight = FontWeight.Bold)
                    Text(pdfFile.absolutePath, fontSize = 10.sp, color = Color.Gray)
                }
            }
        }

        Row(
            modifier = Modifier.fillMaxWidth().padding(16.dp),
            horizontalArrangement = Arrangement.SpaceEvenly
        ) {
            Button(
                onClick = { onStatusChange("완료") },
                colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF4CAF50))
            ) { Text("완료") }
            Button(
                onClick = { onStatusChange("부족") },
                colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFFFC107))
            ) { Text("부족") }
            Button(
                onClick = { onStatusChange("재작업") },
                colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFF44336))
            ) { Text("재작업") }
        }
    }
}

fun checkStoragePermission(): Boolean {
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        Environment.isExternalStorageManager()
    } else {
        true
    }
}

fun requestStoragePermission(activity: ComponentActivity) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        try {
            val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION)
            intent.addCategory("android.intent.category.DEFAULT")
            intent.data = Uri.parse("package:${activity.packageName}")
            activity.startActivity(intent)
        } catch (e: Exception) {
            val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION)
            activity.startActivity(intent)
        }
    }
}
