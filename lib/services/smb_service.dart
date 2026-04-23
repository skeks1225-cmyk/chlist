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

  // [1] connectSMB -> String
  Future<String?> testConnection(String ip, String user, String pass) async {
    try {
      final String result = await _channel.invokeMethod('connectSMB', {
        'ip': ip,
        'user': user,
        'pass': pass,
      });
      return result == "SUCCESS" ? null : result;
    } catch (e) {
      return e.toString();
    }
  }

  // [2] listShares -> List<String>
  Future<List<String>> listShares() async {
    try {
      final List<dynamic> result = await _channel.invokeMethod('listShares');
      return result.cast<String>();
    } catch (e) {
      return [];
    }
  }

  // [3] listFiles -> List<Map<String, Any>>
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

  // [4] downloadFile -> String?
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
