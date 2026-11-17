import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  const url = 'https://tnkyoqpxewvjsqlkvkcf.supabase.co/rest/v1/inventaire_camion?select=id,camion,technicien,ref,nom,quantite';
  const apiKey = 'sb_publishable_CvS_y4fnMs34RjNqokh2-A_QW9YGUFU';

  final res = await http.get(
    Uri.parse(url),
    headers: {
      'apikey': apiKey,
      'Authorization': 'Bearer $apiKey',
      'Prefer': 'count=exact',
    },
  );

  print('Status: ${res.statusCode}');
  print('Content-Range header: ${res.headers['content-range']}');
  final list = jsonDecode(res.body) as List;
  print('Total items fetched: ${list.length}');

  // Group by camion
  final Map<String, int> perTruck = {};
  for (final item in list) {
    final c = item['camion'].toString();
    perTruck[c] = (perTruck[c] ?? 0) + 1;
  }
  perTruck.forEach((truck, count) {
    print('  $truck: $count articles');
  });

  print('\nExemple 1er article: ${list.first}');
}
