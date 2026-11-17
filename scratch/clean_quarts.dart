import 'dart:convert';
import 'dart:io';

void main() async {
  final userProfile = Platform.environment['USERPROFILE'] ?? 'C:\\Users\\popatry';
  final file = File('$userProfile\\Documents\\AppTechnicien\\feuilles_de_temps.json');
  if (!await file.exists()) {
    print('File does not exist: ${file.path}');
    return;
  }

  final content = await file.readAsString();
  final dynamic decoded = jsonDecode(content);
  if (decoded is! Map<String, dynamic>) {
    print('Unexpected JSON format');
    return;
  }

  final list = decoded['quarts'] as List<dynamic>?;
  if (list == null) return;

  final now = DateTime.now();
  final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

  final List<dynamic> realQuarts = [];
  bool seenTodayPatry = false;

  for (final item in list) {
    if (item is! Map<String, dynamic>) continue;
    final id = (item['id'] ?? '').toString();
    final dateStr = (item['date'] ?? '').toString();
    final tech = (item['technicien'] ?? '').toString().toLowerCase();

    // Remove any hardcoded demo/test quarts
    if (id.startsWith('gen_') || id.startsWith('estime_ven_') || id.startsWith('quart_2026925_') || id.startsWith('quart_2026926_')) {
      continue;
    }

    final isToday = dateStr.startsWith(todayStr);
    final isPatry = tech.contains('patry') || tech.contains('pierre');

    if (isToday && isPatry) {
      if (!seenTodayPatry) {
        // Nettoyer d'éventuelles activités fictives
        final acts = (item['activites'] as List<dynamic>? ?? [])
            .where((a) {
              if (a is! Map<String, dynamic>) return false;
              final actId = (a['id'] ?? '').toString();
              return !actId.startsWith('act_po_') && !actId.startsWith('act_10') && !actId.startsWith('gen_');
            })
            .toList();
        item['activites'] = acts;
        item['clockOut'] = null; // Active
        item['id'] = 'quart_Pierre-Olivier_Patry_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
        realQuarts.add(item);
        seenTodayPatry = true;
      }
    } else {
      // Nettoyer les activités fictives
      final acts = (item['activites'] as List<dynamic>? ?? [])
          .where((a) {
            if (a is! Map<String, dynamic>) return false;
            final actId = (a['id'] ?? '').toString();
            return !actId.startsWith('act_po_') && !actId.startsWith('act_dh_') && !actId.startsWith('act_jfa_') && !actId.startsWith('gen_');
          })
          .toList();
      item['activites'] = acts;
      realQuarts.add(item);
    }
  }

  decoded['quarts'] = realQuarts;
  await file.writeAsString(const JsonEncoder.withIndent('  ').convert(decoded));
  print('Successfully purged test data. Remaining real quarts: ${realQuarts.length}');
}
