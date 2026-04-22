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

      Map<String, int> colMap = {'no': 0, 'code': 1, 'qty': 2, 'comp': 3, 'short': 4, 'rew': 5, 'rem': 6};
      var headerRow = sheet.rows[0];
      for (int i = 0; i < headerRow.length; i++) {
        if (headerRow[i] == null) continue;
        String val = headerRow[i]!.value.toString().toLowerCase().trim();
        if (val.contains('no') || val.contains('번호')) colMap['no'] = i;
        else if (val.contains('품목코드') || val.contains('code')) colMap['code'] = i;
        else if (val.contains('수량')) colMap['qty'] = i;
        else if (val.contains('완료')) colMap['comp'] = i;
        else if (val.contains('부족')) colMap['short'] = i;
        else if (val.contains('재작업')) colMap['rew'] = i;
        else if (val.contains('비고')) colMap['rem'] = i;
      }

      for (int i = 1; i < sheet.maxRows; i++) {
        var row = sheet.rows[i];
        int codeIdx = colMap['code'] ?? 1;
        if (row.length <= codeIdx || row[codeIdx] == null) continue;

        items.add(ItemModel(
          realIndex: i,
          no: _getSafe(row, colMap['no']),
          itemCode: _getSafe(row, colMap['code']),
          quantity: _getSafe(row, colMap['qty']),
          complete: _getSafe(row, colMap['comp']).toUpperCase() == "V",
          shortage: _getSafe(row, colMap['short']).toUpperCase() == "V",
          rework: _getSafe(row, colMap['rew']).toUpperCase() == "V",
          remarks: _getSafe(row, colMap['rem']),
        ));
      }
      return items;
    } catch (e) {
      rethrow;
    }
  }

  String _getSafe(List<Data?> row, int? idx) {
    if (idx == null || idx < 0 || idx >= row.length || row[idx] == null) return "";
    return row[idx]!.value.toString();
  }

  Future<bool> saveExcel(String path, List<ItemModel> items) async {
    try {
      final file = File(path);
      
      // 파일 접근 가능 여부 체크
      if (file.existsSync()) {
        try {
          var f = file.openSync(mode: FileMode.append);
          f.closeSync();
        } catch (e) {
          throw Exception("파일이 다른 앱에서 사용 중입니다. 엑셀 뷰어 등을 종료해 주세요.");
        }
      }

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
        sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r), TextCellValue(item.shortage ? "V" : ""));
        sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r), TextCellValue(item.rework ? "V" : ""));
        sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: r), TextCellValue(item.remarks));
      }

      var fileBytes = excel.save();
      if (fileBytes != null) {
        // ❗ 기존 파일을 완전히 지우고 새로운 바이트로 덮어쓰기
        await file.writeAsBytes(fileBytes, flush: true);
        return true;
      }
      return false;
    } catch (e) {
      print("엑셀 저장 오류: $e");
      rethrow;
    }
  }
}
