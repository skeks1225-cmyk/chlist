import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const MaterialApp(home: PureSmbTest()));
}

class PureSmbTest extends StatefulWidget {
  const PureSmbTest({super.key});

  @override
  State<PureSmbTest> createState() => _PureSmbTestState();
}

class _PureSmbTestState extends State<PureSmbTest> {
  final _ip = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  List<String> _results = [];
  bool _loading = false;
  String _status = "대기 중...";

  static const _chan = MethodChannel('pure_smb_test/channel');

  Future<void> _startScan() async {
    setState(() { _loading = true; _status = "스캔 중..."; _results = []; });
    try {
      final List<dynamic> res = await _chan.invokeMethod('scanShares', {
        'ip': _ip.text, 'user': _user.text, 'pass': _pass.text
      });
      setState(() { _results = res.cast<String>(); _status = "성공! (찾은 폴더: ${res.length}개)"; });
    } on PlatformException catch (e) {
      setState(() { _status = "실패: ${e.message}"; });
    } finally {
      setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("SMB 정찰병 테스트")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(controller: _ip, decoration: const InputDecoration(labelText: "IP 주소")),
            TextField(controller: _user, decoration: const InputDecoration(labelText: "사용자 ID")),
            TextField(controller: _pass, decoration: const InputDecoration(labelText: "비밀번호"), obscureText: true),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: _loading ? null : _startScan, child: const Text("공유폴더 목록 조회 시작")),
            const SizedBox(height: 20),
            Text(_status, style: const TextStyle(fontWeight: FontWeight.bold)),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: _results.length,
                itemBuilder: (ctx, idx) => ListTile(leading: const Icon(Icons.folder), title: Text(_results[idx])),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
