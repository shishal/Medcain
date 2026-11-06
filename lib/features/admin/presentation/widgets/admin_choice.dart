import 'package:flutter/material.dart';

/// Labeled dropdown. [items] are `(value, label)` pairs.
class AdminChoice extends StatelessWidget {
  const AdminChoice({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.allowEmpty = false,
    this.emptyLabel = 'None',
    super.key,
  });

  final String label;
  final String? value;
  final List<(String, String)> items;
  final ValueChanged<String?> onChanged;
  final bool allowEmpty;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final known = items.any((item) => item.$1 == value);
    return DropdownButtonFormField<String?>(
      // initialValue is read once; a new key applies the latest selection.
      key: ValueKey('$label::$value'),
      initialValue: known ? value : null,
      decoration: InputDecoration(labelText: label),
      items: [
        if (allowEmpty)
          DropdownMenuItem<String?>(value: null, child: Text(emptyLabel)),
        for (final item in items)
          DropdownMenuItem<String?>(value: item.$1, child: Text(item.$2)),
      ],
      onChanged: onChanged,
    );
  }
}
