import 'dart:io';
import 'package:excel/excel.dart';
import '../models/item_model.dart';

class ExcelService {
  // 로딩과 저장을 위해 감지된 컬럼 인덱스들을 보관
  int _idxNo = 0;
  int _idxCode = 1;
  int _idxQty = 2;
  int _idxComp = 3;
  int _idxShort = 4;
  int _idxRew = 5;
  int _idxRem = 6;

  Future<List<ItemModel>> loadExcel(String path) async {
    try {
      final bytes = File(path).readAsBytesSync();
      final excel = Excel.decodeBytes(bytes);
      List<ItemModel> items = [];

      if (excel.tables.isEmpty) return [];
      var sheet = excel.tables[excel.tables.keys.first];
      if (sheet == null || sheet.maxRows <= 1) return [];

      var header = sheet.rows[0];
      // 헤더 명칭을 기반으로 유연하게 인덱스 찾기
      _idxNo = _findCol(header, ['no', '번호'], 0);
      _idxCode = _findCol(header, ['품목코드', 'code', 'item code'], 1);
      _idxQty = _findCol(header, ['수량', 'qty'], 2);
      _idxComp = _findCol(header, ['완료', 'done'], 3);
      // '부족' 또는 '수량부족' 중 있는 것을 선택
      _idxShort = _findCol(header, ['부족', '수량부족', 'short'], 4);
      _idxRew = _findCol(header, ['재작업', 'rework'], 5);
      _idxRem = _findCol(header, ['비고', 'remarks'], 6);

      for (int i = 1; i < sheet.maxRows; i++) {
        var row = sheet.rows[i];
        if (row.length <= _idxCode || row[_idxCode] == null || row[_idxCode]?.value == null) continue;

        items.add(ItemModel(
          realIndex: i,
          no: row.length > _idxNo ? row[_idxNo]?.value?.toString() ?? "" : "",
          itemCode: row[_idxCode]?.value?.toString() ?? "",
          quantity: row.length > _idxQty ? row[_idxQty]?.value?.toString() ?? "" : "",
          complete: _isV(row, _idxComp),
          shortage: _isV(row, _idxShort) || _isV(row, _findCol(header, ['수량부족'], -1)),
          rework: _isV(row, _idxRew),
          remarks: (row.length > _idxRem ? row[_idxRem]?.value?.toString() ?? "" : ""),
        ));
      }
      return items;
    } catch (e) {
      rethrow;
    }
  }

  bool _isV(List<Data?> row, int idx) {
    if (idx < 0 || idx >= row.length) return false;
    return row[idx]?.value?.toString().toUpperCase() == "V";
  }

  int _findCol(List<Data?> header, List<String> targets, int defaultIdx) {
    for (int i = 0; i < header.length; i++) {
      if (header[i] == null) continue;
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
        // 감지된 인덱스 위치에 정확히 저장
        _safeUpdate(sheet, _idxComp, r, item.complete ? "V" : "");
        _safeUpdate(sheet, _idxShort, r, item.shortage ? "V" : "");
        _safeUpdate(sheet, _idxRew, r, item.rework ? "V" : "");
        _safeUpdate(sheet, _idxRem, r, item.remarks);
      }
      
      var fileBytes = excel.save();
      if (fileBytes != null) File(path).writeAsBytesSync(fileBytes);
    } catch (e) {
      print("저장 오류: $e");
    }
  }

  void _safeUpdate(Sheet sheet, int col, int row, String val) {
    if (col < 0) return;
    sheet.updateCell(
      CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
      TextCellValue(val),
    );
  }
}
