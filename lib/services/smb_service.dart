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
  Future<bool> testConnection(String ip, String user, String pass) async {
    try {
      final bool ok = await _channel.invokeMethod('connectSMB', {
        'ip': ip,
        'user': user,
        'pass': pass,
      });
      return ok;
    } catch (e) {
      return false;
    }
  }

  // ❗ 공유폴더 목록(Share List) 조회 추가
  Future<List<String>> listShares() async {
    try {
      final List<dynamic> result = await _channel.invokeMethod('listShares');
      return result.cast<String>();
    } catch (e) {
      return [];
    }
  }

  // ❗ 특정 폴더 내 파일 목록 조회 (Map 기반)
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
