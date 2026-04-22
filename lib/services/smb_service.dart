import 'dart:io';
import 'package:smb_connect/smb_connect.dart';

class SmbService {
  String _ip = "";
  String _user = "";
  String _pass = "";

  void setConfig(String ip, String user, String pass) {
    _ip = ip; _user = user; _pass = pass;
  }

  // ❗ 접속 테스트 기능
  Future<bool> testConnection(String ip, String user, String pass) async {
    try {
      final client = SmbClient(
        server: ip,
        user: user,
        password: pass,
        domain: ".",
      );
      // 공유폴더 목록을 하나라도 가져올 수 있으면 성공으로 간주
      await client.getShareList();
      return true;
    } catch (e) {
      print("SMB 접속 실패: $e");
      return false;
    }
  }

  Future<List<String>> listShares() async {
    final client = SmbClient(server: _ip, user: _user, password: _pass, domain: ".");
    final shares = await client.getShareList();
    return shares.map((s) => s.name).where((name) => !name.endsWith('\$')).toList();
  }
  
  // 파일 리스트 및 다운로드 로직은 라이브러리 규격에 맞춰 계속 보완 가능
}
