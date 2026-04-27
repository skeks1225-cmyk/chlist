import 'dart:io';
import 'package:excel/excel.dart';
import '../models/item_model.dart';

class ExcelService {
  final List<String> _fixedHeader = ['no', '품목코드', '수량', '완료', '보완', '공정', '비고'];

  Future<List<ItemModel>> loadExcel(String path) async {
    try {
      final bytes = File(path).readAsBytesSync();
      final excel = Excel.decodeBytes(bytes);
      List<ItemModel> items = [];

      if (excel.tables.isEmpty) return [];
      var sheet = excel.tables[excel.tables.keys.first];
      if (sheet == null || sheet.maxRows <= 1) return [];

      for (int i = 1; i < sheet.maxRows; i++) {
        var row = sheet.rows[i];
        if (row.isEmpty) continue;

        String no = _getSafe(row, 0);
        String code = _getSafe(row, 1);
        String qty = _getSafe(row, 2);

        if (code.isEmpty && no.isEmpty && qty.isEmpty) continue;

        bool isSub = (no.isEmpty && qty.isEmpty && code.isNotEmpty);

        // ❗ 기존 'V' 데이터 무시하고 글자 데이터 그대로 읽기
        items.add(ItemModel(
          realIndex: i,
          no: no,
          itemCode: code,
          quantity: qty,
          complete: _getSafe(row, 3).toUpperCase() == "V",
          complement: _getSafe(row, 4),
          process: _getSafe(row, 5),
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

      for (int i = 0; i < items.length; i++) {
        var item = items[i];
        int r = i + 1;
        sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r), TextCellValue(item.no));
        sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r), TextCellValue(item.itemCode));
        sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r), TextCellValue(item.quantity));
        sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r), TextCellValue(item.complete ? "V" : ""));
        sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r), TextCellValue(item.complement));
        sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r), TextCellValue(item.process));
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
