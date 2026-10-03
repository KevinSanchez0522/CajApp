import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cloth_inventory_pos/core/errors/app_exception.dart';
import 'package:postgrest/postgrest.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('mapErrorToAppException', () {
    test('SocketException -> mensaje de red con reintento', () {
      final ex = mapErrorToAppException(
        const SocketException('sin internet'),
        contexto: 'Error al cargar categorías',
      );
      expect(ex.message, contains('Error al cargar categorías'));
      expect(ex.message, contains('Sin conexión'));
      expect(ex.retryable, isTrue);
    });

    test('PostgrestException 42P01 -> schema no aplicado', () {
      final ex = mapErrorToAppException(
        const PostgrestException(
          message: 'relation "public.categories" does not exist',
          code: '42P01',
        ),
      );
      expect(ex.message, contains('schema.sql'));
      expect(ex.code, '42P01');
    });

    test('PostgrestException 401 -> sesión requerida (RLS)', () {
      final ex = mapErrorToAppException(
        const PostgrestException(message: 'Unauthorized', code: '401'),
      );
      expect(ex.message, contains('Sesión requerida'));
      expect(ex.message, contains('401'));
    });

    test('PostgrestException 42501 -> RLS deniega acceso', () {
      final ex = mapErrorToAppException(
        const PostgrestException(message: 'permission denied', code: '42501'),
      );
      expect(ex.message, contains('RLS'));
    });

    test('PostgrestException 23505 -> duplicado', () {
      final ex = mapErrorToAppException(
        const PostgrestException(message: 'duplicate key', code: '23505'),
      );
      expect(ex.message, contains('duplicado'));
    });

    test('AuthException de credenciales -> mensaje en español', () {
      final ex = mapErrorToAppException(
        const AuthException('Invalid login credentials'),
      );
      expect(ex.message, contains('Correo o contraseña incorrectos'));
    });

    test('AuthException de email duplicado', () {
      final ex = mapErrorToAppException(
        const AuthException('User already registered'),
      );
      expect(ex.message, contains('ya está registrado'));
    });

    test('Error genérico conserva el mensaje', () {
      final ex = mapErrorToAppException(
        Exception('algo raro'),
        contexto: 'Error al cargar categorías',
      );
      expect(ex.message, contains('Error al cargar categorías'));
      expect(ex.message, contains('algo raro'));
    });

    test('No lanza con exception de Postgrest sin code', () {
      final ex = mapErrorToAppException(
        const PostgrestException(message: 'detalle multi\nlinea'),
      );
      expect(ex.message, isNot(contains('\n')));
    });
  });
}