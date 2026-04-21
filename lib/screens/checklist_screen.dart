import 'package:flutter/material.dart';
import '../models/item_model.dart';
import '../services/excel_service.dart';
import 'pdf_view_screen.dart';

class ChecklistScreen extends StatefulWidget {
  const ChecklistScreen({super.key});

  @override
  State<ChecklistScreen> createState() => _ChecklistScreenState();
}

class _ChecklistScreenState extends State<ChecklistScreen> {
  final ExcelService _excelService = ExcelService();
  List<ItemModel> _items = [];
  final String _excelPath = "data.xlsx"; // 실제 경로 연동 필요

  void _toggleStatus(ItemModel item, String type) {
    setState(() {
      if (type == 'complete') item.complete = !item.complete;
      else if (type == 'shortage') item.shortage = !item.shortage;
      else if (type == 'rework') item.rework = !item.rework;
    });
    _excelService.saveExcel(_excelPath, _items);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("체크리스트")),
      body: ListView.builder(
        itemCount: _items.length,
        itemBuilder: (context, index) {
          final item = _items[index];
          return ListTile(
            title: Text(item.itemCode),
            onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => PdfViewerScreen(filePath: "${item.itemCode}.pdf")
            )),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(icon: Icon(Icons.check, color: item.complete ? Colors.green : Colors.grey), 
                           onPressed: () => _toggleStatus(item, 'complete')),
                IconButton(icon: Icon(Icons.warning, color: item.shortage ? Colors.orange : Colors.grey), 
                           onPressed: () => _toggleStatus(item, 'shortage')),
                IconButton(icon: Icon(Icons.build, color: item.rework ? Colors.red : Colors.grey), 
                           onPressed: () => _toggleStatus(item, 'rework')),
              ],
            ),
          );
        },
      ),
    );
  }
}
