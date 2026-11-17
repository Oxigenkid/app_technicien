import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

void main() async {
  const supabaseUrl = 'https://tnkyoqpxewvjsqlkvkcf.supabase.co/rest/v1/inventaire_camion';
  const apiKey = 'sb_publishable_CvS_y4fnMs34RjNqokh2-A_QW9YGUFU';

  final jsonFile = File('assets/inventaires/inventaire_camions.json');
  if (!jsonFile.existsSync()) {
    print('Fichier assets/inventaires/inventaire_camions.json introuvable !');
    exit(1);
  }

  final Map<String, dynamic> data = jsonDecode(await jsonFile.readAsString());
  final Map<String, Map<String, dynamic>> recordsById = {};
  int totalRaw = 0;

  data.forEach((techKey, techData) {
    final camion = techData['camion']?.toString() ?? 'Camion #101';
    final technicien = techData['technicien']?.toString() ?? '';
    final localisation = techData['localisation']?.toString() ?? '';
    final rawArticles = techData['articles'] as List<dynamic>? ?? [];

    final camionNum = camion.replaceAll(RegExp(r'[^0-9]'), '');

    for (final item in rawArticles) {
      totalRaw++;
      final map = Map<String, dynamic>.from(item as Map);
      final ref = (map['ref'] ?? '').toString();
      final id = '${camionNum}_$ref';
      final int qte = (map['quantite'] is num)
          ? (map['quantite'] as num).toInt()
          : (int.tryParse(map['quantite']?.toString() ?? '0') ?? 0);

      if (recordsById.containsKey(id)) {
        // Fusionner les doublons dans le même camion en additionnant le stock
        recordsById[id]!['quantite'] = (recordsById[id]!['quantite'] as int) + qte;
      } else {
        recordsById[id] = {
          'id': id,
          'camion': camion,
          'technicien': map['technicien']?.toString() ?? technicien,
          'localisation': map['localisation']?.toString() ?? localisation,
          'ref': ref,
          'nom': (map['nom'] ?? '').toString(),
          'quantite': qte,
          'unite': (map['unite'] ?? 'pcs').toString(),
          'cout': (map['cout'] is num) ? (map['cout'] as num).toDouble() : (double.tryParse(map['cout']?.toString() ?? '0') ?? 0.0),
          'entrepot': (map['entrepot'] ?? camion).toString(),
          'notes': (map['notes'] ?? '').toString(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        };
      }
    }
  });

  final List<Map<String, dynamic>> records = recordsById.values.toList();
  print('📦 $totalRaw articles analysés -> ${records.length} articles uniques consolidés pour envoi Cloud...');

  // Envoi par lots de 50 avec upsert (resolution=merge-duplicates)
  const batchSize = 50;
  int reussis = 0;
  for (var i = 0; i < records.length; i += batchSize) {
    final end = (i + batchSize < records.length) ? i + batchSize : records.length;
    final batch = records.sublist(i, end);

    final response = await http.post(
      Uri.parse(supabaseUrl),
      headers: {
        'apikey': apiKey,
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
        'Prefer': 'resolution=merge-duplicates',
      },
      body: jsonEncode(batch),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      reussis += batch.length;
      print('  ✅ Lot ${i ~/ batchSize + 1}/${(records.length / batchSize).ceil()} envoyé ($reussis/${records.length})');
    } else {
      print('  ❌ Erreur sur le lot ${i ~/ batchSize + 1}: ${response.statusCode}');
      print('     Détail: ${response.body}');
      break;
    }
  }

  if (reussis == records.length) {
    print('\n🎉 SUCCÈS COMPLET ! $reussis articles synchronisés sur Supabase Cloud !');
  } else {
    print('\n⚠️ Synchronisation partielle ($reussis/${records.length}).');
  }
}
