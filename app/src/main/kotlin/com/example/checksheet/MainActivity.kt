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

// --- 1. Data Model ---
data class CheckItem(
    val no: String,
    val itemCode: String,
    val quantity: String,
    var status: String = "NONE" // "DONE", "SHORT", "REWORK"
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
    var currentScreen by remember { mutableStateOf("LIST") } // "LIST", "VIEWER"
    var selectedItem by remember { mutableStateOf<CheckItem?>(null) }
    
    // Sample Data (Excel loading will be added in next step)
    val checkList = remember {
        mutableStateListOf(
            CheckItem("1", "A-001", "10"),
            CheckItem("2", "B-005", "5"),
            CheckItem("3", "C-010", "1")
        )
    }

    Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        if (!hasPermission) {
            // --- Permission Screen ---
            Column(
                modifier = Modifier.fillMaxSize(),
                verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text("Storage Permission Required", fontSize = 20.sp, fontWeight = FontWeight.Bold)
                Spacer(modifier = Modifier.height(20.dp))
                Button(onClick = { 
                    requestStoragePermission(context as ComponentActivity)
                    // In real app, we would use a lifecycle observer to re-check
                    Toast.makeText(context, "Please grant permission and restart app", Toast.LENGTH_LONG).show()
                }) {
                    Text("Grant All Files Access")
                }
            }
        } else {
            // --- Main App Logic ---
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
                        // Using a more Compose-friendly update
                        val index = checkList.indexOfFirst { it.itemCode == selectedItem?.itemCode }
                        if (index != -1) {
                            checkList[index] = item.copy(status = newStatus)
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
            "CheckSheet Items", 
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
                        .background(if (item.status != "NONE") Color(0xFFF0F0F0) else Color.Transparent)
                        .clickable { onItemClick(item) }
                        .padding(16.dp),
                    verticalAlignment = Alignment.CenterHorizontally
                ) {
                    Text(item.no, modifier = Modifier.weight(0.1f))
                    Text(item.itemCode, modifier = Modifier.weight(0.4f), fontWeight = FontWeight.Bold)
                    Text("Qty: ${item.quantity}", modifier = Modifier.weight(0.2f))
                    Text(
                        item.status, 
                        modifier = Modifier.weight(0.3f),
                        color = when(item.status) {
                            "DONE" -> Color(0xFF4CAF50)
                            "SHORT" -> Color(0xFFFFC107)
                            "REWORK" -> Color(0xFFF44336)
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
    val context = LocalContext.current
    // Path: /sdcard/Download/CheckSheet/itemCode.pdf
    val pdfFile = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "CheckSheet/${item.itemCode}.pdf")

    Column(modifier = Modifier.fillMaxSize()) {
        // Top Bar
        Row(
            modifier = Modifier.fillMaxWidth().background(Color.DarkGray).padding(8.dp),
            verticalAlignment = Alignment.CenterHorizontally
        ) {
            Button(onClick = onBack) { Text("Back") }
            Spacer(modifier = Modifier.width(16.dp))
            Text(item.itemCode, color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Bold)
        }

        // --- PDF View ---
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
                    Text("PDF FILE NOT FOUND", color = Color.Red, fontWeight = FontWeight.Bold)
                    Text(pdfFile.absolutePath, fontSize = 10.sp, color = Color.Gray)
                }
            }
        }

        // Bottom Controls
        Row(
            modifier = Modifier.fillMaxWidth().padding(16.dp),
            horizontalArrangement = Arrangement.SpaceEvenly
        ) {
            Button(
                onClick = { onStatusChange("DONE") },
                colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF4CAF50))
            ) { Text("DONE") }
            Button(
                onClick = { onStatusChange("SHORT") },
                colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFFFC107))
            ) { Text("SHORT") }
            Button(
                onClick = { onStatusChange("REWORK") },
                colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFF44336))
            ) { Text("REWORK") }
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
            val intent = Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
            activity.startActivity(intent)
        }
    }
}
