import 'dart:io';
import 'package:excel/excel.dart';
import '../models/item_model.dart';

class ExcelService {
  final List<String> _fixedHeader = ['no', '품목코드', '수량', '완료', '공정', '보완', '비고'];

  Future<List<ItemModel>> loadExcel(String path) async {
    try {
      final bytes = File(path).readAsBytesSync();
      final excel = Excel.decodeBytes(bytes);
      List<ItemModel> items = [];

      if (excel.tables.isEmpty) return [];
      var sheet = excel.tables[excel.tables.keys.first];
      if (sheet == null || sheet.maxRows <= 1) return [];

      String lastMainNo = "";
      int subIndex = 0;
      String currentSubheadingTitle = ""; // ❗ 현재 추적 중인 부분제목

      for (int i = 1; i < sheet.maxRows; i++) {
        var row = sheet.rows[i];
        if (row.isEmpty) continue;

        // ❗ 문자열 "null" 방지를 위해 _getSafe 로직 적용
        String rawNo = _getSafe(row, 0).trim();
        String code = _getSafe(row, 1).trim();
        String qty = _getSafe(row, 2).trim();

        if (code.isEmpty && rawNo.isEmpty && qty.isEmpty) continue;

        bool isSub = (rawNo.isEmpty && qty.isEmpty && code.isNotEmpty);
        if (isSub) {
          currentSubheadingTitle = code;
        }

        String displayNo = rawNo;
        if (rawNo.isNotEmpty) {
          lastMainNo = rawNo;
          subIndex = 0;
          displayNo = rawNo;
        } else if (qty.isNotEmpty) {
          subIndex++;
          displayNo = lastMainNo.isNotEmpty ? "$lastMainNo-$subIndex" : "$subIndex";
        }

        items.add(ItemModel(
          realIndex: i,
          no: rawNo, // 엑셀에 저장될 원본 번호 (비어있으면 빈값)
          displayNo: displayNo, // 화면에 보여줄 가상 번호
          itemCode: code,
          quantity: qty,
          complete: _getSafe(row, 3).toUpperCase() == "V",
          process: _getSafe(row, 4),
          complement: _getSafe(row, 5),
          remarks: _getSafe(row, 6),
          isSubheading: isSub,
          subheadingTitle: isSub ? "" : currentSubheadingTitle, // ❗ 부분제목 저장
        ));
      }
      return items;
    } catch (e) {
      rethrow;
    }
  }

  // ❗ 실제 문자열 "null"이 반환되는 문제를 원천 차단
  String _getSafe(List<Data?> row, int idx) {
    if (idx < 0 || idx >= row.length || row[idx] == null || row[idx]!.value == null) return "";
    String val = row[idx]!.value.toString();
    return (val.toLowerCase() == "null") ? "" : val;
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
        // ❗ item.no가 빈값인 경우 확실하게 빈 문자열로 저장
        sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r), TextCellValue(item.no));
        sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r), TextCellValue(item.itemCode));
        sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r), TextCellValue(item.quantity));
        sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r), TextCellValue(item.complete ? "V" : ""));
        sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r), TextCellValue(item.process));
        sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r), TextCellValue(item.complement));
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
