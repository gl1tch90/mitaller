import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Código de recuperación en papel, solo para el fundador.
///
/// Se genera una sola vez (al registrarse o desde Administración), se muestra
/// en pantalla para anotarlo en papel y solo se guarda su hash SHA-256.
/// Con el código se puede restablecer el PIN del fundador si lo olvida.
class RecoveryCode {
  /// Alfabeto sin caracteres ambiguos (sin 0/O, 1/I/L).
  static const _alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

  static const _salt = 'georges-garage-recovery-v1';

  /// Genera un código como "K7Q2-9MX4-P3TA".
  static String generate({Random? random}) {
    final r = random ?? Random.secure();
    final chars = List.generate(
        12, (_) => _alphabet[r.nextInt(_alphabet.length)]);
    final p1 = chars.sublist(0, 4).join();
    final p2 = chars.sublist(4, 8).join();
    final p3 = chars.sublist(8, 12).join();
    return '$p1-$p2-$p3';
  }

  /// Normaliza lo que escribe el usuario: mayúsculas y sin guiones/espacios.
  static String normalize(String input) =>
      input.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  /// Hash SHA-256 con sal. Es lo único que se guarda en el dispositivo.
  static String hash(String code) => sha256
      .convert(utf8.encode('$_salt|${normalize(code)}'))
      .toString();

  /// Verifica un código escrito por el usuario contra el hash guardado.
  static bool verify(String input, String expectedHash) =>
      hash(input) == expectedHash;
}
