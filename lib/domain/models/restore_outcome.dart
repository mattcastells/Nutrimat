/// Qué tan bien salió leer el documento guardado en el teléfono.
///
/// No es telemetría: es la diferencia entre "el teléfono estaba vacío" y "no
/// pudimos leer lo que había". Confundir las dos cosas fue lo que hizo que una
/// lectura fallida se viera exactamente igual que una cuenta nueva —y que el
/// respaldo vacío que salía de ahí pisara la copia buena de la nube.
class RestoreOutcome {
  const RestoreOutcome({
    this.profileFailed = false,
    this.skippedBySection = const <String, int>{},
    this.unreadableDocument = false,
    this.quarantined = false,
  });

  const RestoreOutcome.clean()
    : profileFailed = false,
      skippedBySection = const <String, int>{},
      unreadableDocument = false,
      quarantined = false;

  /// El JSON entero no se pudo parsear.
  final bool unreadableDocument;

  /// El perfil estaba y no se pudo leer.
  final bool profileFailed;

  /// Cuántos registros se saltearon, por sección.
  final Map<String, int> skippedBySection;

  /// Se guardó una copia intacta del documento original.
  final bool quarantined;

  int get skippedRecords =>
      skippedBySection.values.fold(0, (acc, n) => acc + n);

  bool get isClean =>
      !unreadableDocument && !profileFailed && skippedBySection.isEmpty;

  RestoreOutcome copyWithQuarantined() => RestoreOutcome(
    profileFailed: profileFailed,
    skippedBySection: skippedBySection,
    unreadableDocument: unreadableDocument,
    quarantined: true,
  );

  /// Una línea para mostrarle a la persona. `null` si no hay nada que decir.
  String? get message {
    if (unreadableDocument) {
      return 'No pudimos leer los datos guardados en este teléfono. No se '
          'borró nada: quedó una copia y podés traer tu respaldo de la nube.';
    }
    if (profileFailed) {
      return 'No pudimos leer tu perfil guardado. Guardamos una copia de lo '
          'que había y podés traer tu respaldo de la nube.';
    }
    if (skippedBySection.isNotEmpty) {
      final n = skippedRecords;
      return 'Hubo $n ${n == 1 ? 'registro' : 'registros'} que no pudimos '
          'leer y quedaron afuera. El resto está intacto y guardamos una '
          'copia de lo original.';
    }
    return null;
  }
}
