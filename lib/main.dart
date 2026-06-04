import 'package:flutter/material.dart';

import 'src/app_config.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: AppConfig.appName,
      home: Scaffold(body: Center(child: Text(AppConfig.appName))),
    );
  }
}
