// ignore_for_file: avoid_print
import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  await Supabase.initialize(
    url: 'https://tnkyoqpxewvjsqlkvkcf.supabase.co',
    publishableKey: 'sb_publishable_CvS_y4fnMs34RjNqokh2-A_QW9YGUFU',
  );

  final client = Supabase.instance.client;
  try {
    final res = await client.from('inventaire_camion').select().limit(1);
    print('Select success: $res');
  } catch (e) {
    print('Select error: $e');
  }
}
