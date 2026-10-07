import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/config/supabase_config.dart';
import 'core/config/app_defaults.dart';
import 'core/data/local_database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Inicializar base de datos local SQLite (funciona offline en APK)
  await LocalDatabase.instance.initialize();

  // Inicializar valores por defecto (PINs, email/WhatsApp reportes)
  await AppDefaults.initialize();

  // Inicialización del backend (Supabase). Si no hay credenciales, la app
  // arranca en MODO DEMO con una base de datos local en memoria.
  await SupabaseConfig.initialize();

  runApp(const ProviderScope(child: ClothPosApp()));
}