enum UserRole { admin, colaborador }

class UserProfile {
  final String id;
  final String email;
  final String fullName;
  final UserRole role;
  final bool isActive;

  const UserProfile({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    this.isActive = true,
  });

  bool get isAdmin => role == UserRole.admin;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      email: json['email'] as String,
      fullName: json['full_name'] as String,
      role: (json['role'] as String).toUpperCase() == 'ADMIN'
          ? UserRole.admin
          : UserRole.colaborador,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'full_name': fullName,
        'role': role == UserRole.admin ? 'ADMIN' : 'COLABORADOR',
        'is_active': isActive,
      };

  UserProfile copyWith({
    String? id,
    String? email,
    String? fullName,
    UserRole? role,
    bool? isActive,
  }) {
    return UserProfile(
      id: id ?? this.id,
      email: email ?? this.email,
      fullName: fullName ?? this.fullName,
      role: role ?? this.role,
      isActive: isActive ?? this.isActive,
    );
  }
}
