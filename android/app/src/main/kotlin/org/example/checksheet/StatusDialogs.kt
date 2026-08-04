package org.example.checksheet

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import org.example.checksheet.models.ItemModel

@Composable
fun StatusDialogs(item: ItemModel, onDismiss: () -> Unit, onUpdate: (ItemModel) -> Unit) {
    // 공정/보완/완료 다이얼로그 구현
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("상태 변경: ${item.itemCode}") },
        text = {
            Column {
                Button(onClick = { 
                    item.complete = !item.complete
                    onUpdate(item)
                    onDismiss()
                }) { Text(if (item.complete) "미완료 처리" else "완료 처리") }
                
                // 추가적인 공정/보완 버튼 구현...
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text("닫기") } }
    )
}
