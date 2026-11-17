import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final url = Uri.parse('https://tnkyoqpxewvjsqlkvkcf.supabase.co/rest/v1/interventions?id=eq.cmd_1790705482805');
  final payload = {
    'statut': 'En attente',
    'heure_depart_trajet': null,
    'heure_arrivee_site': null,
    'duree_trajet': null,
    'distance_km': null,
    'en_pause': false,
    'duree_pause_secondes': 0,
  };
  final res = await http.patch(
    url,
    headers: {
      'apikey': 'sb_publishable_CvS_y4fnMs34RjNqokh2-A_QW9YGUFU',
      'Authorization': 'Bearer sb_publishable_CvS_y4fnMs34RjNqokh2-A_QW9YGUFU',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    },
    body: jsonEncode(payload),
  );
  print('Status code: ${res.statusCode}');
  print('Body: ${res.body}');
}
