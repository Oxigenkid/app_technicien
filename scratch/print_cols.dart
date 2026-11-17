import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final url = Uri.parse('https://tnkyoqpxewvjsqlkvkcf.supabase.co/rest/v1/inventaire_camion');
  final res1 = await http.post(
    url,
    headers: {
      'apikey': 'sb_publishable_CvS_y4fnMs34RjNqokh2-A_QW9YGUFU',
      'Authorization': 'Bearer sb_publishable_CvS_y4fnMs34RjNqokh2-A_QW9YGUFU',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    },
    body: jsonEncode({
      'ref': 'TEST_PK_1',
      'nom': 'Article Test PK 1',
      'quantite': 10,
      'entrepot': 'Camion #101',
    }),
  );
  print('Insert 1: ${res1.statusCode} ${res1.body}');

  final res2 = await http.post(
    url,
    headers: {
      'apikey': 'sb_publishable_CvS_y4fnMs34RjNqokh2-A_QW9YGUFU',
      'Authorization': 'Bearer sb_publishable_CvS_y4fnMs34RjNqokh2-A_QW9YGUFU',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    },
    body: jsonEncode({
      'ref': 'TEST_PK_1',
      'nom': 'Article Test PK 1',
      'quantite': 20,
      'entrepot': 'Camion #102',
    }),
  );
  print('Insert 2: ${res2.statusCode} ${res2.body}');

  // Nettoyage
  final delUrl = Uri.parse('https://tnkyoqpxewvjsqlkvkcf.supabase.co/rest/v1/inventaire_camion?ref=eq.TEST_PK_1');
  await http.delete(delUrl, headers: {
    'apikey': 'sb_publishable_CvS_y4fnMs34RjNqokh2-A_QW9YGUFU',
    'Authorization': 'Bearer sb_publishable_CvS_y4fnMs34RjNqokh2-A_QW9YGUFU',
  });
  print('Nettoyage fait.');
}
