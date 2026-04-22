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
      // 라이트 테마
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey, brightness: Brightness.light),
        useMaterial3: true,
      ),
      // 다크 테마
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      // 시스템 설정에 따라 자동 전환
      themeMode: ThemeMode.system,
      home: const ChecklistScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
