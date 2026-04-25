import 'package:flutter/services.dart';
import 'dart:io';

class SmbService {
  static const _channel = MethodChannel('org.example.checksheet/smb');
  
  String _ip = "";
  String _user = "";
  String _pass = "";

  void setConfig(String ip, String user, String pass) {
    _ip = ip;
    _user = user;
    _pass = pass;
  }

  // ❗ 모든 메서드에서 최신 설정값을 함께 실어 보냄 (자동 재접속 보장)
  Future<String?> testConnection(String ip, String user, String pass) async {
    try {
      final String result = await _channel.invokeMethod('connectSMB', {
        'ip': ip,
        'user': user,
        'pass': pass,
      });
      if (result == "SUCCESS") {
        setConfig(ip, user, pass);
        return null;
      }
      return result;
    } catch (e) {
      return e.toString();
    }
  }

  Future<List<String>> listShares() async {
    try {
      final List<dynamic> result = await _channel.invokeMethod('listShares', {
        'ip': _ip,
        'user': _user,
        'pass': _pass,
      });
      return result.cast<String>();
    } catch (e) {
      return ["ERROR: ${e.toString()}"];
    }
  }

  Future<List<Map<String, dynamic>>> listFiles(String share, String path) async {
    try {
      final List<dynamic> result = await _channel.invokeMethod('listFiles', {
        'ip': _ip,
        'user': _user,
        'pass': _pass,
        'share': share,
        'path': path,
      });
      return result.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<File?> downloadFile(String share, String remotePath, String localPath) async {
    try {
      final String? result = await _channel.invokeMethod('downloadFile', {
        'ip': _ip,
        'user': _user,
        'pass': _pass,
        'share': share,
        'remotePath': remotePath,
        'localPath': localPath,
      });
      if (result != null) return File(result);
    } catch (e) {
      print("Download Error: $e");
    }
    return null;
  }
}
