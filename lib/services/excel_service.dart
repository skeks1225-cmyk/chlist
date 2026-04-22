import 'dart:io';
import 'package:excel/excel.dart';
import '../models/item_model.dart';

class ExcelService {
  // 사용자가 요청한 정석 헤더 구조
  final List<String> _fixedHeader = ['no', '품목코드', '수량', '완료', '부족', '재작업', '비고'];

  Future<List<ItemModel>> loadExcel(String path) async {
    try {
      final bytes = File(path).readAsBytesSync();
      final excel = Excel.decodeBytes(bytes);
      List<ItemModel> items = [];

      if (excel.tables.isEmpty) return [];
      var sheet = excel.tables[excel.tables.keys.first];
      if (sheet == null || sheet.maxRows <= 1) return [];

      // 헤더 위치 분석
      var headerRow = sheet.rows[0];
      Map<String, int> colMap = {};
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
        if (row.length <= codeIdx || row[codeIdx] == null || row[codeIdx]?.value == null) continue;

        items.add(ItemModel(
          realIndex: i,
          no: _getVal(row, colMap['no']),
          itemCode: _getVal(row, colMap['code']),
          quantity: _getVal(row, colMap['qty']),
          complete: _getVal(row, colMap['comp']).toUpperCase() == "V",
          shortage: _getVal(row, colMap['short']).toUpperCase() == "V",
          rework: _getVal(row, colMap['rew']).toUpperCase() == "V",
          remarks: _getVal(row, colMap['rem']),
        ));
      }
      return items;
    } catch (e) {
      print("로드 에러: $e");
      rethrow;
    }
  }

  String _getVal(List<Data?> row, int? idx) {
    if (idx == null || idx < 0 || idx >= row.length || row[idx] == null) return "";
    return row[idx]!.value.toString();
  }

  Future<void> saveExcel(String path, List<ItemModel> items) async {
    try {
      // 1. 새로운 엑셀 객체 생성 (기존 파일의 찌꺼기를 없애기 위해 새로 만듦)
      var excel = Excel.createExcel();
      String sheetName = "Sheet1";
      excel.rename(excel.getDefaultSheet()!, sheetName);
      var sheet = excel[sheetName];

      // 2. 고정 헤더 쓰기
      for (int i = 0; i < _fixedHeader.length; i++) {
        sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0), TextCellValue(_fixedHeader[i]));
      }

      // 3. 데이터 쓰기
      for (int i = 0; i < items.length; i++) {
        var item = items[i];
        int r = i + 1; // 0번은 헤더이므로 1번부터 시작
        sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r), TextCellValue(item.no));
        sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r), TextCellValue(item.itemCode));
        sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r), TextCellValue(item.quantity));
        sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r), TextCellValue(item.complete ? "V" : ""));
        sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r), TextCellValue(item.shortage ? "V" : ""));
        sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r), TextCellValue(item.rework ? "V" : ""));
        sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: r), TextCellValue(item.remarks));
      }

      // 4. 물리적 파일 저장 (가장 중요)
      var fileBytes = excel.save();
      if (fileBytes != null) {
        final file = File(path);
        if (await file.exists()) await file.delete(); // 기존 파일 강제 삭제 후 재생성
        await file.writeAsBytes(fileBytes, flush: true);
        print("엑셀 저장 성공: $path");
      }
    } catch (e) {
      print("저장 치명적 에러: $e");
    }
  }
}
