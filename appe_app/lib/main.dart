import 'package:flutter/material.dart';

import 'app_config.dart';
import 'screens/splash_screen.dart';
import 'services/location_service.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocationService.initialize();
  runApp(const AppeApp());
}

class AppeApp extends StatelessWidget {
  const AppeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const SplashScreen(),
    );
  }
}
