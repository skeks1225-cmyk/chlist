import 'dart:io';
import 'package:excel/excel.dart';
import '../models/item_model.dart';

class ExcelService {
  // 고정 헤더 (저장 시 사용)
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
        // 최소 품목코드(1번)는 있어야 함
        if (row.length <= 1 || row[1] == null || row[1]?.value == null) continue;

        items.add(ItemModel(
          realIndex: i,
          no: _getSafe(row, 0),       // 0: no
          itemCode: _getSafe(row, 1), // 1: 품목코드
          quantity: _getSafe(row, 2), // 2: 수량
          complete: _getSafe(row, 3).toUpperCase() == "V", // 3: 완료
          shortage: _getSafe(row, 4).toUpperCase() == "V", // 4: 부족
          rework: _getSafe(row, 5).toUpperCase() == "V",   // 5: 재작업
          remarks: _getSafe(row, 6),  // 6: 비고
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

      // 1. 헤더 쓰기
      for (int i = 0; i < _fixedHeader.length; i++) {
        sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0), TextCellValue(_fixedHeader[i]));
      }

      // 2. 데이터 쓰기
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

      // 3. 물리적 파일 저장 (안드로이드 권한 대응: 덮어쓰기)
      var fileBytes = excel.save();
      if (fileBytes != null) {
        final file = File(path);
        // 삭제 후 재생성보다 직접 쓰기가 더 안정적임
        await file.writeAsBytes(fileBytes, flush: true);
        return true;
      }
      return false;
    } catch (e) {
      print("저장 실패: $e");
      return false;
    }
  }
}
