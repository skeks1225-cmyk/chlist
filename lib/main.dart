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
