import 'package:supabase_flutter/supabase_flutter.dart';

import '../errors/app_exception.dart';

class SupabaseConfig {
  // Configuración de Supabase (Reemplazar con tus credenciales de producción)
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://demo-pos-cloth.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'demo-anon-key-placeholder',
  );

  static bool isInitialized = false;

  /// Error de inicialización (URL/clave inválidas, sin red, etc.).
  /// Antes se silenciaba y la app caía a modo demo sin avisar, lo que
  /// provocaba que el usuario no entendiera por qué no cargaban los datos.
  static AppException? initializationError;

  static bool get isDemoMode =>
      supabaseUrl.contains('demo-pos') ||
      supabaseAnonKey.contains('demo-anon');

  static Future<void> initialize() async {
    initializationError = null;
    isInitialized = false;

    if (isDemoMode) {
      // En modo demo no inicializamos el cliente de red: los repositorios
      // usan la simulación local en memoria.
      return;
    }

    try {
      await Supabase.initialize(
        url: supabaseUrl,
        publishableKey: supabaseAnonKey,
      );
      isInitialized = true;
    } catch (e) {
      isInitialized = false;
      initializationError = mapErrorToAppException(
        e,
        contexto: 'No se pudo conectar con Supabase',
      );
    }
  }

  /// Comprueba que el proyecto responde y que el schema está aplicado.
  /// Devuelve `null` si todo está bien, o un [AppException] con el motivo.
  static Future<AppException?> verifyBackend() async {
    if (isDemoMode) return null;
    if (!isInitialized) {
      return initializationError ??
          const AppException(
            'Supabase no está inicializado. Verifica SUPABASE_URL y SUPABASE_ANON_KEY.',
          );
    }

    try {
      // Un SELECT mínimo sobre `categories`: falla si la tabla no existe (42P01)
      // y devuelve 0 filas si la RLS bloquea al usuario anónimo.
      final res = await Supabase.instance.client
          .from('categories')
          .select('id')
          .limit(1);

      if (res.isEmpty) {
        return const AppException(
          'Las políticas RLS devolvieron 0 filas: no hay sesión iniciada o el '
          'usuario no tiene permiso de lectura. Inicia sesión en la app.',
        );
      }
      return null;
    } catch (e) {
      return mapErrorToAppException(e, contexto: 'Verificación del backend');
    }
  }
}