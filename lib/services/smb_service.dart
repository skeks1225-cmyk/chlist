import 'dart:io';
import 'package:smb_connect/smb_connect.dart';

class SmbService {
  String _ip = "";
  String _user = "";
  String _pass = "";

  void setConfig(String ip, String user, String pass) {
    _ip = ip; _user = user; _pass = pass;
  }

  // ❗ 라이브러리 규격에 맞게 접속 테스트 로직 수정
  Future<bool> testConnection(String ip, String user, String pass) async {
    try {
      // smb_connect 0.0.9 버전 표준 연결 방식
      final config = SMBConfiguration();
      final connection = SMBConnection(
        ip,
        user,
        pass,
        "", // domain
        config,
      );
      
      await connection.connect();
      await connection.login();
      await connection.disconnect();
      return true;
    } catch (e) {
      print("SMB 접속 테스트 실패: $e");
      return false;
    }
  }

  // 향후 구현될 파일 리스트/다운로드 기능의 기반
  Future<List<String>> listShares() async {
    try {
      final config = SMBConfiguration();
      final connection = SMBConnection(_ip, _user, _pass, "", config);
      await connection.connect();
      await connection.login();
      final shares = await connection.listShares();
      await connection.disconnect();
      return shares.map((s) => s.name).toList();
    } catch (e) {
      return [];
    }
  }
}
