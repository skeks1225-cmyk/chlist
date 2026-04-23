import 'dart:io';
import 'package:smb_connect/smb_connect.dart';

class SmbService {
  String _ip = "";
  String _user = "";
  String _pass = "";

  void setConfig(String ip, String user, String pass) {
    _ip = ip; _user = user; _pass = pass;
  }

  // ❗ 3개의 인자(IP, ID, PW)만 받도록 수정
  Future<String?> testConnection(String ip, String user, String pass) async {
    try {
      final connection = await SmbConnect.connectAuth(
        host: ip,
        username: user,
        password: pass,
        domain: "",
      );
      await connection.close();
      return null; // 성공
    } catch (e) {
      return e.toString();
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
      await connection.close();
      return shares.map((s) => s.name).where((n) => !n.endsWith('\$')).toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<SmbFile>> listFiles(String shareName, String path) async {
    try {
      final connection = await SmbConnect.connectAuth(
        host: _ip,
        username: _user,
        password: _pass,
        domain: "",
      );
      final dir = await connection.file("/$shareName/$path");
      final files = await connection.listFiles(dir);
      await connection.close();
      return files;
    } catch (e) {
      return [];
    }
  }

  Future<File?> downloadFile(String shareName, String remotePath, String localPath) async {
    try {
      final connection = await SmbConnect.connectAuth(
        host: _ip,
        username: _user,
        password: _pass,
        domain: "",
      );
      final smbFile = await connection.file("/$shareName/$remotePath");
      
      // ❗ 0.0.9 버전의 정석 읽기 방식: read 메서드 사용
      final bytes = await connection.read(smbFile);
      await connection.close();

      final file = File(localPath);
      if (!file.parent.existsSync()) file.parent.createSync(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
      return file;
    } catch (e) {
      print("다운로드 에러: $e");
      return null;
    }
  }
}
