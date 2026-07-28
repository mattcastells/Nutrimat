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

/// F-11 · Registrar peso (`sheet.weight`).
///
/// Un peso por día: registrar de nuevo actualiza el existente y avisa (D-16).
Future<void> showWeightSheet(BuildContext context, {DateTime? date}) =>
    showNmSheet<void>(
      context: context,
      builder: (context) => _WeightSheet(date: date ?? DateTime.now()),
    );

class _WeightSheet extends ConsumerStatefulWidget {
  const _WeightSheet({required this.date});

  final DateTime date;

  @override
  ConsumerState<_WeightSheet> createState() => _WeightSheetState();
}

class _WeightSheetState extends ConsumerState<_WeightSheet> {
  late final TextEditingController _weight;
  late final TextEditingController _notes;
  late DateTime _date = widget.date;
  String? _error;
  String? _warning;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final repo = ref.read(repositoryProvider);
    final existing = repo.weightOn(widget.date);
    final last = existing?.weightKg ?? repo.currentWeightKg;
    _weight = TextEditingController(
      text: last == null ? '' : Fmt.decimal1(last),
    );
    _notes = TextEditingController(text: existing?.notes ?? '');
  }

  @override
  void dispose() {
    _weight.dispose();
    _notes.dispose();
    super.dispose();
  }

  double? get _parsed =>
      double.tryParse(_weight.text.replaceAll(',', '.').trim());

  Future<void> _save() async {
    final value = _parsed;
    if (value == null || value < 25 || value > 400) {
      setState(() => _error = 'Ingresá un peso entre 25 y 400 kg.');
      return;
    }

    final repo = ref.read(repositoryProvider);
    final previous = repo.currentWeightKg;
    final existing = repo.weightOn(_date);

    // Cambio grande en pocos días: se avisa, no se bloquea (F-11).
    if (_warning == null && previous != null) {
      final logs = repo.weightLogs;
      if (logs.isNotEmpty) {
        final days = daysBetween(logs.first.localDate, _date).abs();
        if ((value - previous).abs() > 3 && days < 3) {
          setState(
            () => _warning = 'Es un cambio grande respecto de tu último '
                'registro. ¿Lo confirmás?',
          );
          return;
        }
      }
    }

    setState(() => _saving = true);
    await repo.logWeight(
      weightKg: value,
      date: _date,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    );
    if (!mounted) return;
    Navigator.of(context).pop();
    NmSnackbar.show(
      context,
      existing == null ? 'Peso registrado' : 'Actualizamos el peso de ese día',
    );
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final units = ref.watch(unitSystemProvider);

    return NmSheet(
      title: 'Registrar peso',
      subtitle: friendlyDay(_date),
      footer: NmButton(
        label: 'Guardar',
        block: true,
        loading: _saving,
        onPressed: _save,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _weight,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: NmTextStyles.from(NmType.display, color: nm.text).tnum,
                  decoration: const InputDecoration(border: InputBorder.none),
                  onChanged: (_) => setState(() {
                    _error = null;
                    _warning = null;
                  }),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: NmSpace.s4),
                child: Text(
                  Fmt.weightUnit(units),
                  style: NmTextStyles.from(NmType.h3, color: nm.textMuted),
                ),
              ),
            ],
          ),
          const NmDivider(),
          if (_error != null) ...<Widget>[
            const SizedBox(height: NmSpace.s3),
            InfoNote(text: _error!, tone: NmNoteTone.caution),
          ],
          if (_warning != null) ...<Widget>[
            const SizedBox(height: NmSpace.s3),
            InfoNote(text: _warning!, tone: NmNoteTone.caution),
          ],
          const SizedBox(height: NmSpace.s6),
          NmDateField(
            label: 'Fecha',
            value: _date,
            lastDate: DateTime.now(),
            onChanged: (v) => setState(() => _date = v),
          ),
          const SizedBox(height: NmSpace.s6),
          NmTextField(
            label: 'Nota (opcional)',
            controller: _notes,
            hint: 'Cómo te sentiste, la balanza que usaste…',
            maxLines: 2,
          ),
        ],
      ),
    );
  }
}

/// Registrar una medida corporal (`/measurement/new`).
Future<void> showMeasurementSheet(BuildContext context) => showNmSheet<void>(
  context: context,
  builder: (context) => const _MeasurementSheet(),
);

class _MeasurementSheet extends ConsumerStatefulWidget {
  const _MeasurementSheet();

  @override
  ConsumerState<_MeasurementSheet> createState() => _MeasurementSheetState();
}

class _MeasurementSheetState extends ConsumerState<_MeasurementSheet> {
  final TextEditingController _value = TextEditingController();
  MeasurementMetric _metric = MeasurementMetric.waist;
  DateTime _date = DateTime.now();
  String? _error;

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final parsed = double.tryParse(_value.text.replaceAll(',', '.'));
    final isPct = _metric == MeasurementMetric.bodyFatPct;
    final min = isPct ? 3.0 : 10.0;
    final max = isPct ? 70.0 : 300.0;

    if (parsed == null || parsed < min || parsed > max) {
      setState(
        () => _error = isPct
            ? 'El porcentaje de grasa va de 3 a 70.'
            : 'La medida va de 10 a 300 cm.',
      );
      return;
    }

    await ref
        .read(repositoryProvider)
        .logMeasurement(metric: _metric, value: parsed, date: _date);
    if (!mounted) return;
    Navigator.of(context).pop();
    NmSnackbar.show(context, 'Medida registrada');
  }

  @override
  Widget build(BuildContext context) => NmSheet(
    title: 'Registrar medida',
    footer: NmButton(label: 'Guardar', block: true, onPressed: _save),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: NmSpace.s2,
          runSpacing: NmSpace.s2,
          children: <Widget>[
            for (final metric in MeasurementMetric.values)
              NmChip(
                label: metric.label,
                selected: metric == _metric,
                onTap: () => setState(() => _metric = metric),
              ),
          ],
        ),
        const SizedBox(height: NmSpace.s6),
        NmNumberField(
          label: _metric.label,
          controller: _value,
          decimals: 1,
          suffix: _metric == MeasurementMetric.bodyFatPct ? '%' : 'cm',
          error: _error,
          autofocus: true,
          onChanged: (_) => setState(() => _error = null),
        ),
        const SizedBox(height: NmSpace.s6),
        NmDateField(
          label: 'Fecha',
          value: _date,
          lastDate: DateTime.now(),
          onChanged: (v) => setState(() => _date = v),
        ),
      ],
    ),
  );
}
