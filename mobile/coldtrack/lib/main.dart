import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load .env so services can read AWS config. Fails loudly in dev if missing.
  await dotenv.load(fileName: '.env');

  // Warm up the local notifications plugin before the UI builds so the first
  // alert does not have to wait for initialisation.
  await NotificationService().init();

  runApp(const ProviderScope(child: ColdTrackApp()));
}