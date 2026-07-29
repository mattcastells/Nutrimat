import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/formats.dart';
import '../../../domain/enums/enums.dart';
import '../../components/system/buttons.dart';
import '../../components/system/inputs.dart';
import '../../components/system/overlays.dart';
import '../../components/system/surfaces.dart';
import '../../providers/app_providers.dart';

/// S-26 · Registrar medidas corporales.
///
/// Una nutricionista no entrega una medida: entrega una planilla con
/// perímetros, pliegues y lo que dijo la balanza, todo del mismo día. Por eso
/// el formulario carga la sesión entera y no un valor por vez, y viene con los
/// valores que ya haya de esa fecha para poder corregirlos.
///
/// El peso y la talla quedan afuera a propósito: el peso tiene su propio
/// registro diario y la altura vive en el perfil corporal, donde alimenta el
/// cálculo del metabolismo basal.
Future<void> showMeasurementSheet(
  BuildContext context, {
  DateTime? date,
  MeasurementGroup? group,
}) => showNmSheet<void>(
  context: context,
  builder: (context) => _MeasurementSheet(
    date: date ?? DateTime.now(),
    group: group ?? MeasurementGroup.perimeters,
  ),
);

class _MeasurementSheet extends ConsumerStatefulWidget {
  const _MeasurementSheet({required this.date, required this.group});

  final DateTime date;
  final MeasurementGroup group;

  @override
  ConsumerState<_MeasurementSheet> createState() => _MeasurementSheetState();
}

class _MeasurementSheetState extends ConsumerState<_MeasurementSheet> {
  late MeasurementGroup _group = widget.group;
  late DateTime _date = widget.date;

  /// Un controlador por métrica, en las tres pestañas a la vez: cambiar de
  /// grupo no puede tirar lo que se venía escribiendo.
  final Map<MeasurementMetric, TextEditingController> _fields =
      <MeasurementMetric, TextEditingController>{};
  final Map<MeasurementMetric, String> _errors =
      <MeasurementMetric, String>{};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final existing = ref.read(repositoryProvider).measurementsOn(_date);
    for (final metric in MeasurementMetric.values) {
      final text = existing[metric] == null
          ? ''
          : Fmt.decimal1(existing[metric]!.value);
      final field = _fields[metric];
      if (field == null) {
        _fields[metric] = TextEditingController(text: text);
      } else {
        field.text = text;
      }
    }
    _errors.clear();
  }

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  double? _parse(MeasurementMetric metric) {
    final raw = _fields[metric]!.text.replaceAll(',', '.').trim();
    if (raw.isEmpty) return null;
    return double.tryParse(raw);
  }

  /// Sumatoria de los pliegues cargados. Se muestra con cuántos, porque una
  /// suma de cuatro y una de siete no son el mismo número ni se comparan.
  (double sum, int count) get _foldSum {
    var sum = 0.0;
    var count = 0;
    for (final metric in MeasurementMetric.folds) {
      final value = _parse(metric);
      if (value != null && value >= metric.min && value <= metric.max) {
        sum += value;
        count++;
      }
    }
    return (sum, count);
  }

  Future<void> _save() async {
    final errors = <MeasurementMetric, String>{};
    final toSave = <MeasurementMetric, double>{};

    for (final metric in MeasurementMetric.values) {
      final raw = _fields[metric]!.text.trim();
      if (raw.isEmpty) continue;
      final value = _parse(metric);
      if (value == null || value < metric.min || value > metric.max) {
        errors[metric] =
            'Va de ${Fmt.decimal1(metric.min)} a ${Fmt.decimal1(metric.max)}'
            '${metric.unitLabel.isEmpty ? '' : ' ${metric.unitLabel}'}.';
        continue;
      }
      toSave[metric] = value;
    }

    if (errors.isNotEmpty) {
      setState(() {
        _errors
          ..clear()
          ..addAll(errors);
        // Se salta al primer grupo con problemas para que el error se vea.
        _group = errors.keys.first.group;
      });
      return;
    }

    if (toSave.isEmpty) {
      setState(() => _errors[MeasurementMetric.waist] = 'Cargá al menos una.');
      return;
    }

    setState(() => _saving = true);
    final repo = ref.read(repositoryProvider);

    // Lo que se dejó en blanco y ya existía se borra: vaciar un campo es la
    // forma natural de decir "esto no se midió".
    final existing = repo.measurementsOn(_date);
    for (final entry in existing.entries) {
      if (!toSave.containsKey(entry.key)) {
        await repo.deleteMeasurement(entry.value.id);
      }
    }
    for (final entry in toSave.entries) {
      await repo.logMeasurement(
        metric: entry.key,
        value: entry.value,
        date: _date,
      );
    }

    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop();
    NmSnackbar.show(
      context,
      toSave.length == 1
          ? 'Medida registrada'
          : '${toSave.length} medidas registradas',
    );
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final metrics = MeasurementMetric.inGroup(_group);
    final (foldSum, foldCount) = _foldSum;

    return NmSheet(
      title: 'Registrar medidas',
      subtitle: friendlyDay(_date),
      footer: NmButton(
        label: 'Guardar',
        block: true,
        loading: _saving,
        onPressed: _save,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          NmSegmentedControl<MeasurementGroup>(
            options: const <(MeasurementGroup, String)>[
              (MeasurementGroup.perimeters, 'Perímetros'),
              (MeasurementGroup.skinfolds, 'Pliegues'),
              (MeasurementGroup.composition, 'Balanza'),
            ],
            value: _group,
            onChanged: (v) => setState(() => _group = v),
          ),
          const SizedBox(height: NmSpace.s3),
          Text(
            _group.help,
            style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
          ),
          const SizedBox(height: NmSpace.s5),

          for (final metric in metrics)
            Padding(
              padding: const EdgeInsets.only(bottom: NmSpace.s4),
              child: NmNumberField(
                label: metric.label,
                controller: _fields[metric]!,
                decimals: 1,
                suffix: metric.unitLabel.isEmpty
                    ? 'índice'
                    : metric.unitLabel,
                error: _errors[metric],
                onChanged: (_) => setState(() => _errors.remove(metric)),
              ),
            ),

          if (_group == MeasurementGroup.skinfolds && foldCount >= 2) ...<Widget>[
            NmCard(
              raised: true,
              child: ValueRow(
                label: 'Sumatoria',
                caption: '$foldCount pliegues',
                value: '${Fmt.decimal1(foldSum)} mm',
                emphasis: true,
              ),
            ),
            const SizedBox(height: NmSpace.s3),
            Text(
              'Nutrimat no convierte los pliegues a porcentaje de grasa: cada '
              'ecuación pide un juego de pliegues distinto y da un número '
              'distinto. La suma sirve para compararte con vos mismo.',
              style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
            ),
            const SizedBox(height: NmSpace.s4),
          ],

          NmDateField(
            label: 'Fecha',
            value: _date,
            lastDate: DateTime.now(),
            onChanged: (v) => setState(() {
              _date = v;
              _load();
            }),
          ),
          const SizedBox(height: NmSpace.s3),
          Text(
            'El peso se registra aparte, y la altura está en Perfil corporal.',
            style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
          ),
        ],
      ),
    );
  }
}
