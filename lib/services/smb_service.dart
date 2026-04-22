import 'dart:io';
import 'package:smb_connect/smb_connect.dart';

class SmbService {
  String _ip = "";
  String _user = "";
  String _pass = "";

  void setConfig(String ip, String user, String pass) {
    _ip = ip; _user = user; _pass = pass;
  }

  // ❗ 라이브러리 규격(0.0.9) 실시간 재교정
  Future<bool> testConnection(String ip, String user, String pass) async {
    try {
      final connection = await SmbConnect.connectAuth(
        host: ip,
        username: user,
        password: pass,
        domain: "",
      );
      
      // ❗ 'disconnect'가 아니라 'close'가 정석 메서드임
      await connection.close();
      return true;
    } catch (e) {
      print("SMB 접속 테스트 실패: $e");
      return false;
    }
  }

  Future<List<String>> listShares() async {
    try {
      final connection = await SmbConnect.connectAuth(
        host: _ip,
        username: _user,
        password: _pass,
        domain: "",
      );
      
      List<SmbFile> shares = await connection.listShares();
      await connection.close(); // ❗ 메서드 명칭 수정
      
      return shares
          .map((s) => s.name)
          .where((name) => !name.endsWith('\$')) // ❗ '$' 기호 이스케이프 처리 완료
          .toList();
    } catch (e) {
      print("공유폴더 목록 조회 실패: $e");
      return [];
    }
  }
}
