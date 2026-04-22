import 'dart:io';
import 'package:excel/excel.dart';
import '../models/item_model.dart';

class ExcelService {
  final List<String> _fixedHeader = ['no', '품목코드', '수량', '완료', '부족', '재작업', '비고'];

  Future<List<ItemModel>> loadExcel(String path) async {
    try {
      final bytes = File(path).readAsBytesSync();
      final excel = Excel.decodeBytes(bytes);
      List<ItemModel> items = [];

      if (excel.tables.isEmpty) return [];
      var sheet = excel.tables[excel.tables.keys.first];
      if (sheet == null || sheet.maxRows <= 1) return [];

      // 전문가 조언: 이름이 달라도 "위치 기반"으로 읽어옴
      for (int i = 1; i < sheet.maxRows; i++) {
        var row = sheet.rows[i];
        if (row.length <= 1) continue;

        String no = _getSafe(row, 0);
        String code = _getSafe(row, 1);
        String qty = _getSafe(row, 2);

        // ❗ 소제목 판단: No와 Qty가 없고 코드만 있을 때
        bool isSub = (no.isEmpty && qty.isEmpty && code.isNotEmpty);

        items.add(ItemModel(
          realIndex: i,
          no: no,
          itemCode: code,
          quantity: qty,
          complete: _getSafe(row, 3).toUpperCase() == "V",
          shortage: _getSafe(row, 4).toUpperCase() == "V",
          rework: _getSafe(row, 5).toUpperCase() == "V",
          remarks: _getSafe(row, 6),
          isSubheading: isSub,
        ));
      }
      return items;
    } catch (e) {
      rethrow;
    }
  }

  String _getSafe(List<Data?> row, int idx) {
    if (idx < 0 || idx >= row.length || row[idx] == null) return "";
    return row[idx]!.value.toString();
  }

  Future<bool> saveExcel(String path, List<ItemModel> items) async {
    try {
      var excel = Excel.createExcel();
      String sheetName = "Sheet1";
      excel.rename(excel.getDefaultSheet()!, sheetName);
      var sheet = excel[sheetName];

      for (int i = 0; i < _fixedHeader.length; i++) {
        sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0), TextCellValue(_fixedHeader[i]));
      }

      // ❗ 정렬과 상관없이 전달받은 리스트(원본 순서) 그대로 저장
      for (int i = 0; i < items.length; i++) {
        var item = items[i];
        int r = i + 1;
        sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r), TextCellValue(item.no));
        sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r), TextCellValue(item.itemCode));
        sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r), TextCellValue(item.quantity));
        sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r), TextCellValue(item.complete ? "V" : ""));
        sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r), TextCellValue(item.shortage ? "V" : ""));
        sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r), TextCellValue(item.rework ? "V" : ""));
        sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: r), TextCellValue(item.remarks));
      }

      var fileBytes = excel.save();
      if (fileBytes != null) {
        final file = File(path);
        file.writeAsBytesSync(fileBytes, flush: true);
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }
}
