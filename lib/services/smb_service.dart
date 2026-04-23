import 'dart:io';
import 'package:flutter/services.dart';

class SmbService {
  static const _channel = MethodChannel('org.example.checksheet/smb');
  
  String _ip = "";
  String _user = "";
  String _pass = "";

  void setConfig(String ip, String user, String pass) {
    _ip = ip; _user = user; _pass = pass;
  }

  // ❗ 네이티브 SMBJ를 통한 접속 테스트
  Future<String?> testConnection(String ip, String user, String pass) async {
    try {
      final bool ok = await _channel.invokeMethod('connectSMB', {
        'ip': ip,
        'user': user,
        'pass': pass,
      });
      return ok ? null : "인증 실패 또는 네트워크 오류";
    } catch (e) {
      return e.toString();
    }
  }

  // ❗ 공유폴더 내 파일 리스트 조회
  Future<List<Map<String, dynamic>>> listFiles(String share, String path) async {
    try {
      final List<dynamic> result = await _channel.invokeMethod('listFiles', {
        'share': share,
        'path': path,
      });
      return result.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e) {
      return [];
    }
  }

  // ❗ 파일 다운로드
  Future<File?> downloadFile(String share, String remotePath, String localPath) async {
    try {
      final String? path = await _channel.invokeMethod('downloadFile', {
        'share': share,
        'remotePath': remotePath,
        'localPath': localPath,
      });
      return path != null ? File(path) : null;
    } catch (e) {
      return null;
    }
  }
}
