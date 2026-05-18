import 'package:flutter/material.dart';
import 'screens/checklist_screen.dart';

void main() {
  runApp(const CheckSheetApp());
}

class CheckSheetApp extends StatelessWidget {
  const CheckSheetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CheckSheet',
      debugShowCheckedModeBanner: false,
      // ❗ 라이트 모드 테마 정의
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorSchemeSeed: Colors.blueGrey,
      ),
      // ❗ 다크 모드 테마 정의 (이게 있어야 다크모드 인식이 됩니다)
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.blueGrey,
      ),
      // ❗ 시스템 설정에 따라 자동으로 테마 변경
      themeMode: ThemeMode.system,
      home: const ChecklistScreen(),
    );
  }
}
