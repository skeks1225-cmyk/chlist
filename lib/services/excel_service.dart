import 'dart:io';
import 'package:excel/excel.dart';
import '../models/item_model.dart';

class ExcelService {
  // 엑셀 읽기 기능 추가 (빌드 에러 해결)
  Future<List<ItemModel>> loadExcel(String path) async {
    var bytes = File(path).readAsBytesSync();
    var excel = Excel.decodeBytes(bytes);
    List<ItemModel> items = [];

    for (var table in excel.tables.keys) {
      var sheet = excel.tables[table]!;
      if (sheet.maxRows <= 1) continue;

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
        if (row.length <= idxCode || row[idxCode]?.value == null) continue;

        items.add(ItemModel(
          realIndex: i,
          no: row[idxNo]?.value?.toString() ?? "",
          itemCode: row[idxCode]?.value?.toString() ?? "",
          quantity: row[idxQty]?.value?.toString() ?? "",
          complete: row[idxComp]?.value?.toString() == "V",
          shortage: row[idxShort]?.value?.toString() == "V",
          rework: row[idxRew]?.value?.toString() == "V",
          remarks: row[idxRem]?.value?.toString() ?? "",
        ));
      }
      break;
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

  Future<void> saveExcel(String path, List<ItemModel> items) async {
    var bytes = File(path).readAsBytesSync();
    var excel = Excel.decodeBytes(bytes);
    var sheet = excel.tables[excel.tables.keys.first]!;

    int idxComp = 3; // 인덱스 최적화 필요 시 위 loadExcel과 연동
    int idxShort = 4;
    int idxRew = 5;
    int idxRem = 6;

    for (var item in items) {
      int r = item.realIndex;
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: idxComp, rowIndex: r), 
          item.complete ? TextCellValue("V") : TextCellValue(""));
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: idxShort, rowIndex: r), 
          item.shortage ? TextCellValue("V") : TextCellValue(""));
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: idxRew, rowIndex: r), 
          item.rework ? TextCellValue("V") : TextCellValue(""));
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: idxRem, rowIndex: r), 
          TextCellValue(item.remarks));
    }
    
    var fileBytes = excel.save();
    if (fileBytes != null) File(path).writeAsBytesSync(fileBytes);
  }
}
