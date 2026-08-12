import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Dictado: lo que se dice al micrófono, convertido en texto.
///
/// Lo hace el reconocedor del propio teléfono (`SpeechRecognizer` de Android),
/// no un servicio nuestro: el audio no pasa por Nutrimat, no se guarda en
/// ningún lado y no hay un archivo que subir. Lo único que llega a la app es la
/// frase ya transcripta, que es exactamente lo que la persona habría escrito.
///
/// Está acá y no adentro del widget para que la pantalla no sepa de
/// `speech_to_text`: la del micrófono es la clase de dependencia que conviene
/// tener detrás de una puerta, porque falla de maneras muy distintas según el
/// teléfono —sin motor de reconocimiento, sin permiso, sin idioma instalado— y
/// ninguna de esas puede llegar a la interfaz como una excepción suelta.
class DictationGateway {
  DictationGateway({SpeechToText? engine}) : _engine = engine ?? SpeechToText();

  final SpeechToText _engine;

  /// Cuánto silencio corta el dictado. Tres segundos es lo que tarda alguien en
  /// pensar el segundo plato sin que se le corte la frase.
  static const Duration pauseFor = Duration(seconds: 3);

  /// Techo duro de una sesión. Nadie describe una comida durante un minuto, y
  /// un micrófono abierto para siempre es lo peor que puede quedar prendido.
  static const Duration listenFor = Duration(seconds: 60);

  bool _initialized = false;
  bool _unavailable = false;

  bool get isListening => _engine.isListening;

  /// Si este teléfono puede dictar. `false` sin motor de reconocimiento o con
  /// el permiso denegado: ahí el micrófono ni se ofrece, en vez de ofrecer un
  /// botón que siempre falla.
  bool get isAvailable => _initialized && !_unavailable;

  /// Prepara el motor. Devuelve `false` si no se puede dictar en este teléfono.
  ///
  /// **Es también donde Android pide el permiso de micrófono**, así que se
  /// llama al tocar el botón y no al abrir la pantalla: un permiso que aparece
  /// solo, antes de que nadie pida nada, es la forma más rápida de que lo
  /// nieguen para siempre.
  Future<bool> prepare() async {
    if (_initialized) return !_unavailable;
    try {
      final ok = await _engine.initialize(
        onError: _onError,
        // `initialize` no lanza cuando el permiso se niega: devuelve false. El
        // `catch` de abajo es para lo otro —un motor que no responde—, que sí
        // llega como excepción de canal.
      );
      _initialized = true;
      _unavailable = !ok;
      return ok;
    } on Object {
      _initialized = true;
      _unavailable = true;
      return false;
    }
  }

  void _onError(SpeechRecognitionError error) {
    // `error_no_match` y `error_speech_timeout` son "no se entendió" y "no
    // dijiste nada": no inhabilitan el dictado, pasan todo el tiempo y no son
    // un problema del teléfono. Los permanentes sí apagan el botón.
    if (error.permanent && error.errorMsg != 'error_no_match') {
      _unavailable = true;
    }
  }

  /// Empieza a escuchar. [onText] recibe la frase **completa** de la sesión
  /// cada vez que el reconocedor la corrige, no los pedazos sueltos.
  ///
  /// [onDone] avisa cuando dejó de escuchar por su cuenta —silencio, tope de
  /// tiempo o un fallo—, que es lo que el botón necesita para volver a su
  /// estado normal sin que nadie lo toque.
  Future<bool> start({
    required ValueChanged<String> onText,
    required VoidCallback onDone,
  }) async {
    if (!await prepare()) return false;
    try {
      await _engine.listen(
        onResult: (SpeechRecognitionResult result) {
          onText(result.recognizedWords);
          if (result.finalResult) onDone();
        },
        listenOptions: SpeechListenOptions(
          // Parciales: la frase aparece mientras se habla. Sin esto la pantalla
          // se queda muda hasta el final y no se sabe si está escuchando.
          partialResults: true,
          listenMode: ListenMode.dictation,
          cancelOnError: true,
          pauseFor: pauseFor,
          listenFor: listenFor,
          localeId: await _localeId(),
        ),
      );
      return _engine.isListening;
    } on Object {
      _unavailable = true;
      return false;
    }
  }

  Future<void> stop() async {
    if (!_initialized) return;
    try {
      await _engine.stop();
    } on Object {
      // Cortar el micrófono no puede fallar hacia afuera: el peor caso es que
      // el motor ya estuviera cortado.
    }
  }

  Future<void> cancel() async {
    if (!_initialized) return;
    try {
      await _engine.cancel();
    } on Object {
      // Igual que `stop`.
    }
  }

  /// Español rioplatense si el teléfono lo tiene; cualquier español si no.
  ///
  /// Sin esto el reconocedor usa el idioma del sistema, que puede no ser el que
  /// se está hablando — y "dos empanadas de carne" leído en inglés no se parece
  /// a nada.
  Future<String?> _localeId() async {
    try {
      final locales = await _engine.locales();
      if (locales.isEmpty) return null;
      for (final wanted in const <String>['es_AR', 'es-AR', 'es_419']) {
        for (final locale in locales) {
          if (locale.localeId == wanted) return locale.localeId;
        }
      }
      for (final locale in locales) {
        if (locale.localeId.toLowerCase().startsWith('es')) {
          return locale.localeId;
        }
      }
      return null;
    } on Object {
      return null;
    }
  }
}
