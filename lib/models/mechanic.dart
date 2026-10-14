/// Puestos disponibles al registrar a un usuario del taller.
class MechanicPositions {
  static const List<String> options = [
    'Mecánico',
    'Técnico',
    'Ayudante',
    'Eléctrico',
    'Jefe de taller',
    'Otro',
  ];

  static const String def = 'Mecánico';
}

/// Avatares precargados para identificar al mecánico.
/// Se guardan como emoji (texto), sin fotos ni archivos.
class MechanicAvatars {
  static const List<String> options = [
    '🧑‍🔧', '👨‍🔧', '👩‍🔧', '🏍️',
    '🔧', '🚗', '⚙️', '🛠️',
    '🧰', '🏎️', '🔩', '⛽',
  ];

  static const String def = '🧑‍🔧';

  /// Avatar válido o el predeterminado si el guardado no existe.
  static String sanitize(String? raw) =>
      raw != null && options.contains(raw) ? raw : def;
}

/// Mecánico que usa la app. El PIN se guarda localmente en el dispositivo.
/// [isAdmin] indica si es el jefe/administrador del taller.
/// [isFounder] marca al primer usuario registrado: no se puede eliminar
/// ni quitarle el rol de administrador, y es el único que puede
/// eliminar o degradar a otros administradores.
/// [recoveryCodeHash] guarda el hash SHA-256 del código de recuperación
/// en papel del fundador (solo él tiene uno). Permite restablecer su PIN
/// si lo olvida. El código en claro nunca se guarda.
/// [language] es el idioma preferido del mecánico: 'es', 'en' o '' (vacío
/// = usar el idioma predeterminado del teléfono).
/// [positions] son los puestos del mecánico: puede tener varios a la vez.
class Mechanic {
  final String id;
  final String name;
  final String pin;
  final List<String> positions;
  final bool isAdmin;
  final bool isFounder;
  final String? recoveryCodeHash;
  final String language;
  /// Emoji del avatar elegido.
  final String avatar;

  Mechanic({
    required this.id,
    required this.name,
    required this.pin,
    this.positions = const [MechanicPositions.def],
    this.isAdmin = false,
    this.isFounder = false,
    this.recoveryCodeHash,
    this.language = '',
    this.avatar = MechanicAvatars.def,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'pin': pin,
        'positions': positions,
        'isAdmin': isAdmin,
        'isFounder': isFounder,
        'recoveryCodeHash': recoveryCodeHash,
        'language': language,
        'avatar': avatar,
      };

  factory Mechanic.fromJson(Map<String, dynamic> json) => Mechanic(
        id: json['id'] as String,
        name: json['name'] as String,
        pin: json['pin'] as String,
        positions: _parsePositions(json),
        isAdmin: json['isAdmin'] as bool? ?? false,
        isFounder: json['isFounder'] as bool? ?? false,
        recoveryCodeHash: json['recoveryCodeHash'] as String?,
        language: json['language'] as String? ?? '',
        avatar: MechanicAvatars.sanitize(json['avatar'] as String?),
      );

  /// Lee la lista nueva ('positions') o la cadena vieja ('position') de
  /// instalaciones anteriores, para no perder el puesto ya guardado.
  static List<String> _parsePositions(Map<String, dynamic> json) {
    final list = json['positions'];
    if (list is List && list.isNotEmpty) {
      return list.map((e) => e.toString()).toList();
    }
    final single = json['position'];
    if (single is String && single.isNotEmpty) {
      return [single];
    }
    return const [MechanicPositions.def];
  }

  Mechanic copyWith({
    String? name,
    String? pin,
    List<String>? positions,
    bool? isAdmin,
    bool? isFounder,
    String? recoveryCodeHash,
    String? language,
    String? avatar,
  }) =>
      Mechanic(
        id: id,
        name: name ?? this.name,
        pin: pin ?? this.pin,
        positions: positions ?? this.positions,
        isAdmin: isAdmin ?? this.isAdmin,
        isFounder: isFounder ?? this.isFounder,
        recoveryCodeHash: recoveryCodeHash ?? this.recoveryCodeHash,
        language: language ?? this.language,
        avatar: avatar ?? this.avatar,
      );
}
