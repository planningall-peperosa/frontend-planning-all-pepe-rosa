import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/preventivo_builder_provider.dart';

/// Campo per selezionare PRANZO/CENA, controllato dal Provider.
/// - Legge il valore iniziale da PreventivoBuilderProvider.tipoPasto
/// - Aggiorna il provider quando l’utente cambia
/// - Se [required] è true, espone anche un piccolo messaggio d’errore se non selezionato
class TipoPastoField extends StatelessWidget {
  final bool required;
  const TipoPastoField({super.key, this.required = false});

  @override
  Widget build(BuildContext context) {
    return Consumer<PreventivoBuilderProvider>(
      builder: (_, builder, __) {
        final selected = builder.tipoPasto; // 'pranzo' | 'cena' | null

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tipo pasto', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Pranzo'),
                  selected: selected == 'pranzo',
                  onSelected: (_) => builder.setTipoPasto('pranzo'),
                ),
                ChoiceChip(
                  label: const Text('Cena'),
                  selected: selected == 'cena',
                  onSelected: (_) => builder.setTipoPasto('cena'),
                ),
              ],
            ),
            if (required && selected == null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Seleziona Pranzo o Cena',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
