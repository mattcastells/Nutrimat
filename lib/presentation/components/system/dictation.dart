import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/motion.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/local/dictation_gateway.dart';
import 'overlays.dart';

/// El micrófono que escribe en un campo de texto.
///
/// Va **adentro** del campo, como sufijo, y no como un botón aparte: contar lo
/// que comiste hablando no es otra forma de cargar una comida, es otra forma de
/// llenar ese campo. Todo lo que sigue —estimar con la IA, revisar los ítems,
/// guardar— es exactamente el mismo camino que si se hubiera escrito a mano.
///
/// Se toca una vez y escucha; se toca de nuevo, se hace silencio o pasa el
/// minuto, y para. Lo dictado se **suma** a lo que ya había escrito, no lo
/// pisa: quien escribió media frase y después habla no pierde la mitad.
///
/// Si el teléfono no puede dictar —sin motor de reconocimiento, o con el
/// permiso negado— el botón desaparece en vez de quedarse fallando. La primera
/// vez el permiso lo pide Android al tocarlo, que es cuando se entiende para
/// qué es.
class NmDictationButton extends StatefulWidget {
  const NmDictationButton({
    required this.controller,
    this.onChanged,
    this.enabled = true,
    super.key,
  });

  final TextEditingController controller;

  /// Se avisa con el texto ya actualizado, para que la pantalla haga lo mismo
  /// que si se hubiera tecleado (limpiar el error, habilitar el botón).
  final ValueChanged<String>? onChanged;
  final bool enabled;

  /// Dónde tiene sentido ofrecerlo. En escritorio y en los tests no hay motor
  /// de reconocimiento y el botón sería decorado.
  static bool get isSupportedPlatform =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  State<NmDictationButton> createState() => _NmDictationButtonState();
}

class _NmDictationButtonState extends State<NmDictationButton> {
  final DictationGateway _dictation = DictationGateway();

  bool _listening = false;

  /// Lo que había escrito cuando empezó a hablar. El reconocedor devuelve la
  /// frase entera de la sesión en cada corrección, así que sin esto cada
  /// corrección duplicaría lo anterior.
  String _base = '';

  /// Se apaga solo si el teléfono resulta no poder dictar. No arranca en
  /// `false` porque saberlo cuesta inicializar el motor, y eso es justo lo que
  /// dispara el pedido de permiso: se descubre al primer toque.
  bool _available = true;

  @override
  void dispose() {
    _dictation.cancel();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_listening) {
      await _dictation.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }

    _base = widget.controller.text.trimRight();
    final started = await _dictation.start(
      onText: _write,
      onDone: () {
        if (mounted) setState(() => _listening = false);
      },
    );
    if (!mounted) return;

    if (!started) {
      setState(() {
        _listening = false;
        _available = _dictation.isAvailable;
      });
      NmSnackbar.show(
        context,
        _dictation.isAvailable
            ? 'No pudimos abrir el micrófono. Escribilo y listo.'
            : 'Para dictar hace falta el permiso de micrófono. Podés '
                  'escribirlo igual.',
      );
      return;
    }
    setState(() => _listening = true);
  }

  void _write(String words) {
    if (!mounted) return;
    final texto = _base.isEmpty ? words : '$_base $words';
    widget.controller.value = TextEditingValue(
      text: texto,
      selection: TextSelection.collapsed(offset: texto.length),
    );
    widget.onChanged?.call(texto);
  }

  @override
  Widget build(BuildContext context) {
    if (!_available || !NmDictationButton.isSupportedPlatform) {
      return const SizedBox.shrink();
    }
    final nm = context.nm;

    return IconButton(
      onPressed: widget.enabled ? _toggle : null,
      // El estado se dice con palabras y no solo con el color: es un botón que
      // cambia lo que hace al tocarlo, y con lector de pantalla el color no
      // existe.
      tooltip: _listening ? 'Dejar de dictar' : 'Dictar',
      icon: AnimatedSwitcher(
        duration: context.motion.fade(NmMotion.fast),
        child: Icon(
          _listening
              ? PhosphorIcons.microphone(PhosphorIconsStyle.fill)
              : PhosphorIcons.microphone(),
          key: ValueKey<bool>(_listening),
          size: NmIconSize.md,
          color: _listening ? nm.accent : nm.textMuted,
        ),
      ),
    );
  }
}
