import 'dart:io';
import 'package:smb_connect/smb_connect.dart';

class SmbService {
  // SMB 접속 정보
  String _ip = "";
  String _user = "";
  String _pass = "";

  void setConfig(String ip, String user, String pass) {
    _ip = ip; _user = user; _pass = pass;
  }

  // ❗ 원격 파일 리스트 가져오기
  Future<List<SmbFile>> listFiles(String shareName, String path) async {
    try {
      final session = SmbSession(_ip, _user, _pass);
      final share = await session.getShare(shareName);
      return await share.list(path);
    } catch (e) {
      rethrow;
    }
  }

  // ❗ 공유폴더 리스트 가져오기
  Future<List<String>> listShares() async {
    try {
      final session = SmbSession(_ip, _user, _pass);
      return await session.listShares();
    } catch (e) {
      rethrow;
    }
  }

  // ❗ 파일 다운로드 (핵심)
  Future<File> downloadFile(String shareName, String remotePath, String localPath) async {
    try {
      final session = SmbSession(_ip, _user, _pass);
      final share = await session.getShare(shareName);
      final remoteFile = await share.getFile(remotePath);
      
      final localFile = File(localPath);
      if (localFile.existsSync()) localFile.deleteSync();
      
      final bytes = await remoteFile.readAsBytes();
      await localFile.writeAsBytes(bytes, flush: true);
      
      return localFile;
    } catch (e) {
      rethrow;
    }
  }
}

// 간단한 SMB 파일 정보를 담는 헬퍼 클래스
class SmbSession {
  final String ip;
  final String user;
  final String pass;

  SmbSession(this.ip, this.user, this.pass);

  // 실제 smb_connect 라이브러리 연동 로직 (필요시 구현체 보완)
  Future<List<String>> listShares() async {
    // smb_connect의 실제 API를 사용하여 구현
    // 여기서는 개념적 흐름을 작성하며, 실제 연동 시 라이브러리 문법을 정교하게 맞춥니다.
    return ["SharedFolder1", "Documents", "PDF_Drawings"]; 
  }

  Future<dynamic> getShare(String name) async {
    return null; // 라이브러리 실제 객체 반환
  }
}
