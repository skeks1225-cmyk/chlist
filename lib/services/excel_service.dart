import 'dart:io';
import 'package:excel/excel.dart';
import '../models/item_model.dart';

class ExcelService {
  Future<void> saveExcel(String path, List<ItemModel> items) async {
    var bytes = File(path).readAsBytesSync();
    var excel = Excel.decodeBytes(bytes);
    var sheet = excel.tables[excel.tables.keys.first]!;

    for (var item in items) {
      int r = item.realIndex;
      // 완료(3), 부족(4), 재작업(5), 비고(6) 인덱스 기준 업데이트
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r), 
          item.complete ? TextCellValue("V") : TextCellValue(""));
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r), 
          item.shortage ? TextCellValue("V") : TextCellValue(""));
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r), 
          item.rework ? TextCellValue("V") : TextCellValue(""));
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: r), 
          TextCellValue(item.remarks));
    }
    
    var fileBytes = excel.save();
    if (fileBytes != null) File(path).writeAsBytesSync(fileBytes);
  }
}
