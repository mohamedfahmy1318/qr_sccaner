import 'dart:io';

import 'package:flutter/material.dart';
import 'package:qrscanner/core/router/router.dart';
import 'package:qrscanner/features/card_scanner/card_scanner_view.dart';
import 'package:qrscanner/features/card_type/card_type_view.dart';
import 'package:qrscanner/features/login/login_view.dart';

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = MyHttpOverrides();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: const CardScannerView(),
      onGenerateRoute: onGenerateRoute,
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: ThemeData(fontFamily: 'Tajwal'),
    );
  }
}
