import 'dart:io';
import 'package:smb_connect/smb_connect.dart';

class SmbService {
  String _ip = "";
  String _user = "";
  String _pass = "";

  void setConfig(String ip, String user, String pass) {
    _ip = ip; _user = user; _pass = pass;
  }

  // ❗ 상세 에러를 반환하여 접속 실패 원인을 분석함
  Future<String?> testConnection(String ip, String user, String pass) async {
    try {
      final connection = await SmbConnect.connectAuth(
        host: ip,
        username: user,
        password: pass,
        domain: "", // 도메인은 빈 값으로 처리
      );
      await connection.close();
      return null; // 성공
    } catch (e) {
      return e.toString(); // 실패 시 구체적인 시스템 에러 메시지 반환
    }
  }

  // 공유폴더 목록 가져오기
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
      print("SMB 목록 에러: $e");
      return [];
    }
  }

  // 파일 목록 가져오기
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

  // 파일 다운로드
  Future<File?> downloadFile(String shareName, String remotePath, String localPath) async {
    try {
      final connection = await SmbConnect.connectAuth(
        host: _ip,
        username: _user,
        password: _pass,
        domain: "",
      );
      final smbFile = await connection.file("/$shareName/$remotePath");
      final bytes = await connection.read(smbFile);
      await connection.close();

      final file = File(localPath);
      if (file.existsSync()) file.deleteSync();
      await file.writeAsBytes(bytes, flush: true);
      return file;
    } catch (e) {
      return null;
    }
  }
}
