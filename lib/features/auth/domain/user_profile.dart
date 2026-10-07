enum UserRole { admin, colaborador }

class UserProfile {
  final String id;
  final String email;
  final String fullName;
  final UserRole role;
  final bool isActive;
  final String? localPin; // PIN local de 4-6 dígitos para desbloqueo rápido

  const UserProfile({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    this.isActive = true,
    this.localPin,
  });

  bool get isAdmin => role == UserRole.admin;
  bool get hasLocalPin => localPin != null && localPin!.isNotEmpty;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      email: json['email'] as String,
      fullName: json['full_name'] as String,
      role: (json['role'] as String).toUpperCase() == 'ADMIN'
          ? UserRole.admin
          : UserRole.colaborador,
      isActive: json['is_active'] as bool? ?? true,
      localPin: json['local_pin'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'full_name': fullName,
        'role': role == UserRole.admin ? 'ADMIN' : 'COLABORADOR',
        'is_active': isActive,
        'local_pin': localPin,
      };

  UserProfile copyWith({
    String? id,
    String? email,
    String? fullName,
    UserRole? role,
    bool? isActive,
    String? localPin,
    bool clearPin = false,
  }) {
    return UserProfile(
      id: id ?? this.id,
      email: email ?? this.email,
      fullName: fullName ?? this.fullName,
      role: role ?? this.role,
      isActive: isActive ?? this.isActive,
      localPin: clearPin ? null : (localPin ?? this.localPin),
    );
  }
}
