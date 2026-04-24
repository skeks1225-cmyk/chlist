import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const SmbTestApp());
}

class SmbTestApp extends StatelessWidget {
  const SmbTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SMB Share Discovery Test',
      theme: ThemeData(primarySwatch: Colors.orange),
      home: const TestScreen(),
    );
  }
}

class TestScreen extends StatefulWidget {
  const TestScreen({super.key});

  @override
  State<TestScreen> createState() => _TestScreenState();
}

class _TestScreenState extends State<TestScreen> {
  final _ipController = TextEditingController();
  final _userController = TextEditingController();
  final _passController = TextEditingController();
  List<String> _shares = [];
  bool _isLoading = false;
  String _error = "";

  static const _channel = MethodChannel('org.example.smbtest/test');

  Future<void> _runDiscovery() async {
    setState(() { _isLoading = true; _error = ""; _shares = []; });
    try {
      final List<dynamic> result = await _channel.invokeMethod('getShareList', {
        'ip': _ipController.text,
        'user': _userController.text,
        'pass': _passController.text,
      });
      setState(() { _shares = result.cast<String>(); });
    } on PlatformException catch (e) {
      setState(() { _error = "오류: ${e.message}"; });
    } finally {
      setState(() { _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("공유목록 정찰 테스트")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(controller: _ipController, decoration: const InputDecoration(labelText: "IP 주소")),
            TextField(controller: _userController, decoration: const InputDecoration(labelText: "ID")),
            TextField(controller: _passController, decoration: const InputDecoration(labelText: "PW"), obscureText: true),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isLoading ? null : _runDiscovery,
              child: _isLoading ? const CircularProgressIndicator() : const Text("공유목록 긁어오기 (jCIFS)"),
            ),
            const Divider(height: 40),
            if (_error.isNotEmpty) Text(_error, style: const TextStyle(color: Colors.red)),
            Expanded(
              child: ListView.builder(
                itemCount: _shares.length,
                itemBuilder: (ctx, i) => ListTile(
                  leading: const Icon(Icons.folder_shared),
                  title: Text(_shares[i]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
