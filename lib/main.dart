import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'screens/checklist_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _requestPermissions();
  runApp(const CheckSheetApp());
}

Future<void> _requestPermissions() async {
  // 저장소 및 관리 권한 요청 (안드로이드 11 이상 대응)
  await [
    Permission.storage,
    Permission.manageExternalStorage,
  ].request();
}

class CheckSheetApp extends StatelessWidget {
  const CheckSheetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CheckSheet Final',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
        useMaterial3: true,
      ),
      home: const ChecklistScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
