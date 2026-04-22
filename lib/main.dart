import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'screens/checklist_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _requestPermissions();
  runApp(const CheckSheetApp());
}

Future<void> _requestPermissions() async {
  // 1. 일반적인 저장소 권한 요청
  await [
    Permission.storage,
    Permission.notification,
  ].request();

  // 2. 안드로이드 11 이상 필수: 모든 파일 접근 권한 확인 및 요청
  if (await Permission.manageExternalStorage.isDenied) {
    await Permission.manageExternalStorage.request();
  }
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
