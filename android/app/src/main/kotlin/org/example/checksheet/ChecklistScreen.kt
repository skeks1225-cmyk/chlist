package org.example.checksheet

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import org.example.checksheet.models.ItemModel

@Composable
fun ChecklistScreen(items: List<ItemModel>, onUpdate: (ItemModel) -> Unit) {
    LazyColumn(modifier = Modifier.fillMaxSize()) {
        items(items) { item ->
            ItemRow(item = item, onUpdate = onUpdate)
        }
    }
}

@Composable
fun ItemRow(item: ItemModel, onUpdate: (ItemModel) -> Unit) {
    Card(modifier = Modifier.fillMaxWidth().padding(8.dp)) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(text = item.itemCode, style = MaterialTheme.typography.titleMedium)
            Row {
                Checkbox(checked = item.complete, onCheckedChange = {
                    item.complete = it
                    onUpdate(item)
                })
                Text(text = "완료")
            }
        }
    }
}
