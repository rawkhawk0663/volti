/// Version dieser Volti-Ausgabe, z. B. „v0.1.42“ – dieselbe Nummer wie beim
/// Download auf GitHub. Wird beim Bauen gesetzt (`--dart-define=VOLTI_VERSION`).
const voltiVersion = String.fromEnvironment('VOLTI_VERSION', defaultValue: 'Testversion');
