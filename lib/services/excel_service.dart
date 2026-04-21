import 'dart:io';
import 'package:excel/excel.dart';
import '../models/checklist_item.dart';

class ExcelService {
  Future<List<ChecklistItem>> loadExcel(String path) async {
    var bytes = File(path).readAsBytesSync();
    var excel = Excel.decodeBytes(bytes);
    List<ChecklistItem> items = [];

    for (var table in excel.tables.keys) {
      var sheet = excel.tables[table]!;
      if (sheet.maxRows == 0) continue;

      var header = sheet.rows[0];
      int idxNo = _findCol(header, ['no', '번호'], 0);
      int idxCode = _findCol(header, ['품목코드', 'code'], 1);
      int idxQty = _findCol(header, ['수량', 'qty'], 2);
      int idxComp = _findCol(header, ['완료', 'done'], 3);
      int idxShort = _findCol(header, ['수량부족', 'short'], 4);
      int idxRew = _findCol(header, ['재작업', 'rework'], 5);
      int idxRem = _findCol(header, ['비고', 'remarks'], 6);

      for (int i = 1; i < sheet.maxRows; i++) {
        var row = sheet.rows[i];
        if (row.length <= idxCode || row[idxCode] == null) continue;

        items.add(ChecklistItem(
          realIndex: i,
          no: row[idxNo]?.value?.toString() ?? "",
          itemCode: row[idxCode]?.value?.toString() ?? "",
          quantity: row[idxQty]?.value?.toString() ?? "",
          isComplete: row[idxComp]?.value?.toString().toUpperCase() == "V",
          isShortage: row[idxShort]?.value?.toString().toUpperCase() == "V",
          isRework: row[idxRew]?.value?.toString().toUpperCase() == "V",
          remarks: row[idxRem]?.value?.toString() ?? "",
        ));
      }
      break; // 첫 번째 시트만 사용
    }
    return items;
  }

  int _findCol(List<Data?> header, List<String> targets, int defaultIdx) {
    for (int i = 0; i < header.length; i++) {
      var val = header[i]?.value?.toString().toLowerCase().trim() ?? "";
      if (targets.contains(val)) return i;
    }
    return defaultIdx;
  }

  Future<void> saveExcel(String path, List<ChecklistItem> items) async {
    var bytes = File(path).readAsBytesSync();
    var excel = Excel.decodeBytes(bytes);
    var sheet = excel.tables[excel.tables.keys.first]!;

    // 헤더에서 인덱스 다시 찾기
    var header = sheet.rows[0];
    int idxComp = _findCol(header, ['완료'], 3);
    int idxShort = _findCol(header, ['수량부족'], 4);
    int idxRew = _findCol(header, ['재작업'], 5);
    int idxRem = _findCol(header, ['비고'], 6);

    for (var item in items) {
      int r = item.realIndex;
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: idxComp, rowIndex: r), 
          item.isComplete ? "V" : "");
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: idxShort, rowIndex: r), 
          item.isShortage ? "V" : "");
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: idxRew, rowIndex: r), 
          item.isRework ? "V" : "");
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: idxRem, rowIndex: r), 
          item.remarks);
    }

    var fileBytes = excel.save();
    if (fileBytes != null) {
      File(path)
        ..createSync(recursive: true)
        ..writeAsBytesSync(fileBytes);
    }
  }
}
