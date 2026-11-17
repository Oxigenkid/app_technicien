import 'dart:convert';
import 'dart:io';

void main() {
  final data = jsonDecode(File('assets/inventaires/inventaire_camions.json').readAsStringSync()) as Map<String, dynamic>;
  final Map<String, List<Map<String, dynamic>>> map = {};
  int total = 0;

  data.forEach((k, v) {
    final cNum = (v['camion'] as String).replaceAll(RegExp(r'\D'), '');
    for (final a in (v['articles'] as List)) {
      total++;
      final id = '${cNum}_${a['ref']}';
      map.putIfAbsent(id, () => []).add(Map<String, dynamic>.from(a as Map));
    }
  });

  final dups = map.entries.where((e) => e.value.length > 1).toList();
  print('Total articles: $total');
  print('Unique IDs: ${map.length}');
  print('Duplicates count: ${dups.length}');
  for (final d in dups) {
    print('\nDup ID: ${d.key} (${d.value.length} occurrences)');
    for (final item in d.value) {
      print('  ref=${item['ref']} nom=${item['nom']} qte=${item['quantite']} camion=${item['camion']}');
    }
  }
}
