import 'dart:io';
import 'package:excel/excel.dart';
import '../models/item_model.dart';

class ExcelService {
  Future<List<ItemModel>> loadExcel(String path) async {
    try {
      final bytes = File(path).readAsBytesSync();
      final excel = Excel.decodeBytes(bytes);
      List<ItemModel> items = [];

      // 첫 번째 시트 안전하게 가져오기
      if (excel.tables.isEmpty) return [];
      String firstSheetName = excel.tables.keys.first;
      var sheet = excel.tables[firstSheetName];
      if (sheet == null || sheet.maxRows <= 1) return [];

      var header = sheet.rows[0];
      int idxNo = _findCol(header, ['no', '번호'], 0);
      int idxCode = _findCol(header, ['품목코드', 'code'], 1);
      int idxQty = _findCol(header, ['수량', 'qty'], 2);
      int idxComp = _findCol(header, ['완료'], 3);
      int idxShort = _findCol(header, ['수량부족'], 4);
      int idxRew = _findCol(header, ['재작업'], 5);
      int idxRem = _findCol(header, ['비고'], 6);

      for (int i = 1; i < sheet.maxRows; i++) {
        var row = sheet.rows[i];
        // 품목코드가 없는 행은 스킵
        if (row.length <= idxCode || row[idxCode] == null || row[idxCode]?.value == null) continue;

        items.add(ItemModel(
          realIndex: i,
          no: row.length > idxNo ? row[idxNo]?.value?.toString() ?? "" : "",
          itemCode: row[idxCode]?.value?.toString() ?? "",
          quantity: row.length > idxQty ? row[idxQty]?.value?.toString() ?? "" : "",
          complete: (row.length > idxComp && row[idxComp]?.value?.toString().toUpperCase() == "V"),
          shortage: (row.length > idxShort && row[idxShort]?.value?.toString().toUpperCase() == "V"),
          rework: (row.length > idxRew && row[idxRew]?.value?.toString().toUpperCase() == "V"),
          remarks: (row.length > idxRem ? row[idxRem]?.value?.toString() ?? "" : ""),
        ));
      }
      return items;
    } catch (e) {
      rethrow;
    }
  }

  int _findCol(List<Data?> header, List<String> targets, int defaultIdx) {
    for (int i = 0; i < header.length; i++) {
      if (header[i] == null || header[i]?.value == null) continue;
      var val = header[i]?.value?.toString().toLowerCase().trim() ?? "";
      if (targets.contains(val)) return i;
    }
    return defaultIdx;
  }

  Future<void> saveExcel(String path, List<ItemModel> items) async {
    try {
      var bytes = File(path).readAsBytesSync();
      var excel = Excel.decodeBytes(bytes);
      if (excel.tables.isEmpty) return;
      
      var sheet = excel.tables[excel.tables.keys.first];
      if (sheet == null) return;

      for (var item in items) {
        int r = item.realIndex;
        // 인덱스가 범위를 벗어나지 않도록 안전하게 업데이트
        _safeUpdate(sheet, 3, r, item.complete ? "V" : "");
        _safeUpdate(sheet, 4, r, item.shortage ? "V" : "");
        _safeUpdate(sheet, 5, r, item.rework ? "V" : "");
        _safeUpdate(sheet, 6, r, item.remarks);
      }
      
      var fileBytes = excel.save();
      if (fileBytes != null) {
        File(path).writeAsBytesSync(fileBytes);
      }
    } catch (e) {
      print("저장 오류: $e");
    }
  }

  void _safeUpdate(Sheet sheet, int col, int row, String val) {
    sheet.updateCell(
      CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
      TextCellValue(val),
    );
  }
}
