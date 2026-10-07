import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/app_defaults.dart';
import '../domain/user_profile.dart';
import 'auth_repository.dart';

/// Comprueba que el código introducido coincida con el PIN de administrador.
///
/// Se acepta el PIN guardado para el usuario admin por defecto y, si quien
/// opera es admin, también su propio PIN. Si nunca se guardó ninguno, se
/// valida contra el PIN por defecto de la app para no bloquear la función.
///
/// Es la única fuente de verdad de la regla de PIN: la usan todas las
/// acciones sensibles (quitar unidades, borrar prenda y limpieza masiva de
/// inventario).
Future<bool> verifyAdminPin(WidgetRef ref, String pin) async {
  final code = pin.trim();
  if (code.isEmpty) return false;

  final repo = ref.read(authRepositoryProvider);
  final UserProfile profile = ref.read(currentUserProfileProvider);

  final candidates = <String>{
    AppDefaults.adminUserId,
    if (profile.isAdmin) profile.id,
  };
  for (final userId in candidates) {
    if (await repo.verifyLocalPin(userId, code)) return true;
  }

  final stored = await repo.getLocalPin(AppDefaults.adminUserId);
  if ((stored == null || stored.isEmpty) &&
      code == AppDefaults.defaultAdminPin) {
    return true;
  }
  return false;
}
