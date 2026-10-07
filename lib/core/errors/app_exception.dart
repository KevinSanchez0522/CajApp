import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Error de negocio/infraestructura con mensaje ya traducido y accionable
/// para el usuario final (evita mostrar `PostgrestException` crudo en la UI).
class AppException implements Exception {
  final String message;

  /// Código técnico opcional, útil para logs (p.ej. `42P01`, `42501`).
  final String? code;

  /// Si el usuario puede resolverlo reintentando la operación.
  final bool retryable;

  const AppException(this.message, {this.code, this.retryable = false});

  @override
  String toString() => message;
}

/// Traduce excepciones de red/Supabase a [AppException] con mensajes claros.
AppException mapErrorToAppException(Object error, {String contexto = ''}) {
  final prefijo = contexto.isEmpty ? '' : '$contexto: ';

  // --- Sin conexión / red caída -------------------------------------------
  if (error is SocketException) {
    return AppException(
      '${prefijo}Sin conexión a internet o el servidor no responde. '
      'Revisa tu red y vuelve a intentarlo.',
      retryable: true,
    );
  }
  if (error is HttpException) {
    return AppException(
      '${prefijo}El servidor rechazó la solicitud (${error.message}).',
      retryable: true,
    );
  }
  if (error is TimeoutException) {
    return AppException(
      '${prefijo}El servidor tardó demasiado en responder.',
      retryable: true,
    );
  }

  // --- Cliente Supabase no inicializado ----------------------------------
  // `Supabase.instance` lanza un TypeError (null check) si no se inicializó.
  if (error is TypeError || error is UnimplementedError) {
    return const AppException(
      'Supabase no está inicializado. '
      'Verifica SUPABASE_URL y SUPABASE_ANON_KEY al ejecutar la app.',
    );
  }

  // --- Errores de PostgREST / REST ---------------------------------------
  if (error is PostgrestException) {
    switch (error.code) {
      case '42P01': // undefined_table
        return AppException(
          '${prefijo}La tabla no existe en el proyecto de Supabase. '
          'Ejecuta el contenido de supabase/schema.sql en el SQL Editor.',
          code: error.code,
        );
      case '42501': // insufficient_privilege
        return AppException(
          '${prefijo}Acceso denegado por las políticas RLS. '
          'Inicia sesión en la app para obtener un JWT válido.',
          code: error.code,
        );
      case 'PGRST301': // JWT inválido
      case 'PGRST302':
        return AppException(
          '${prefijo}La sesión no es válida o expiró. Cierra sesión e inicia sesión de nuevo.',
          code: error.code,
        );
      case 'PGRST204': // no está en la caché de esquema (tabla o columna)
        return AppException(
          '${prefijo}Supabase no encuentra una tabla o columna en su caché de '
          "esquema. Ejecuta \"NOTIFY pgrst, 'reload schema';\" en el SQL Editor "
          'de Supabase y vuelve a intentarlo. Si persiste, revisa que el '
          'schema.sql esté aplicado y que la tabla exista.',
          code: error.code,
          retryable: true,
        );
      case '23505': // unique_violation
        return AppException(
          '${prefijo}Ya existe un registro con esos datos (SKU o código duplicado).',
          code: error.code,
        );
      case '23503': // foreign_key_violation
        return AppException(
          '${prefijo}La referencia no existe (categoría o producto inválido).',
          code: error.code,
        );
    }

    final detalle = error.message.isEmpty
        ? 'sin detalle'
        : error.message.replaceAll(RegExp(r'\s+'), ' ').trim();

    // El cliente Dart reporta el status HTTP dentro de `code`.
    if (error.code == '401' || error.code == '403') {
      return AppException(
        '${prefijo}Sesión requerida (HTTP ${error.code}). '
        'Inicia sesión en la app para que las políticas RLS te permitan leer los datos.',
        code: error.code,
      );
    }
    if (error.code == '404' || error.code == '400' || error.code == '406') {
      return AppException(
        '${prefijo}La API de Supabase respondió ${error.code}. '
        'Verifica la URL y que el schema esté aplicado. Detalle: $detalle',
        code: error.code,
      );
    }

    return AppException(
      '${prefijo}Error del servidor${error.code == null ? '' : ' (${error.code})'}: $detalle',
      code: error.code,
      retryable: true,
    );
  }

  // --- Auth ---------------------------------------------------------------
  if (error is AuthException) {
    final m = error.message.toLowerCase();
    if (m.contains('invalid login credentials')) {
      return const AppException('Correo o contraseña incorrectos.');
    }
    if (m.contains('email not confirmed')) {
      return const AppException('El correo no está confirmado. Revisa tu bandeja.');
    }
    if (m.contains('already registered') || m.contains('already exists')) {
      return const AppException('Ese correo ya está registrado.');
    }
    return AppException('Error de autenticación: ${error.message}');
  }

  // --- Genérico -----------------------------------------------------------
  final texto = error.toString().replaceAll('Exception: ', '').trim();
  return AppException('$prefijo$texto');
}