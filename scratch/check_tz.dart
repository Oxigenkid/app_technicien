import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final nowLocal = DateTime.now();
  print('nowLocal: $nowLocal');
  print('nowLocal.toIso8601String(): ${nowLocal.toIso8601String()}');
  print('nowLocal.toUtc().toIso8601String(): ${nowLocal.toUtc().toIso8601String()}');

  // Let's check what Supabase returned for interventions
  final res = await http.get(
    Uri.parse('https://tnkyoqpxewvjsqlkvkcf.supabase.co/rest/v1/interventions?select=id,statut,heure_depart_trajet,heure_arrivee_site,heure_cloture'),
    headers: {
      'apikey': 'sb_publishable_CvS_y4fnMs34RjNqokh2-A_QW9YGUFU',
      'Authorization': 'Bearer sb_publishable_CvS_y4fnMs34RjNqokh2-A_QW9YGUFU',
    },
  );
  print('Supabase interventions: ${res.body}');
}
