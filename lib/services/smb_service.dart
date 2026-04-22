import 'dart:io';
import 'package:smb_connect/smb_connect.dart';

class SmbService {
  String _ip = "";
  String _user = "";
  String _pass = "";

  void setConfig(String ip, String user, String pass) {
    _ip = ip; _user = user; _pass = pass;
  }

  // ❗ 라이브러리 실제 규격(0.0.9)에 맞춰 수정
  Future<bool> testConnection(String ip, String user, String pass) async {
    try {
      // SmbConnect.connectAuth 정석 사용법
      final connection = await SmbConnect.connectAuth(
        host: ip,
        username: user,
        password: pass,
        domain: "", // 일반적인 Windows 공유폴더는 비워둠
      );
      
      // 연결 확인 후 즉시 해제
      await connection.disconnect();
      return true;
    } catch (e) {
      print("SMB 접속 테스트 실패: $e");
      return false;
    }
  }

  // 공유폴더 목록 가져오기 (실제 로직)
  Future<List<String>> listShares() async {
    try {
      final connection = await SmbConnect.connectAuth(
        host: _ip,
        username: _user,
        password: _pass,
        domain: "",
      );
      
      // 공유폴더 리스트 조회
      List<SmbFile> shares = await connection.listShares();
      await connection.disconnect();
      
      // 특수 목적용 폴더($로 끝나는 것) 제외
      return shares
          .map((s) => s.name)
          .where((name) => !name.endsWith('$'))
          .toList();
    } catch (e) {
      print("공유폴더 목록 조회 실패: $e");
      return [];
    }
  }
}
