import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';
import '../lib/app_helpers.dart';

void main() {
  test('Inserer vrai rdv', () async {
    final client = SupabaseClient(
      'https://tnkyoqpxewvjsqlkvkcf.supabase.co',
      'sb_publishable_CvS_y4fnMs34RjNqokh2-A_QW9YGUFU',
    );

    final testId = 'cmd_${DateTime.now().millisecondsSinceEpoch}';
    final raw = {
      'id': testId,
      'nom_client': 'Grues Guay Inc.',
      'adresse': '10150 Boulevard Henri-Bourassa, Montréal, QC H1C 1G4',
      'adresse_facturation': '10150 Boulevard Henri-Bourassa, Montréal, QC H1C 1G4',
      'numero_commande': 'CO-67291-01',
      'numero_reference': 'TF-84729',
      'numero_bon_commande': '#PO-2026-991',
      'trouble': 'Calibration moment Rayco Wylie et capteur angle',
      'nom_contact': 'Marc-André Guay',
      'telephone': '514-555-8822',
      'courriel': 'dispatch@gruesguay.com',
      'type_machine': 'Grue télescopique',
      'marque': 'Tadano',
      'modele': 'GR-700XL',
      'annee': '2022',
      'numero_serie_machine': 'SN-TAD-991',
      'numero_unite': 'Unité #44-101',
      'alimentation': '24v',
      'modele_systeme': 'RaycoWylie i4500 RCI',
      'systeme_wylie': '12-34-567',
      'numero_serie_systeme': '12-34-567',
      'nom_technicien': 'Patrick Popatry',
      'numero_camion': 'Camion #101',
      'priorite': 'Normale',
      'statut': 'En attente',
      'date_rendez_vous': '2026-10-01',
      'heure_rendez_vous': '14:30',
      'duree_minutes': 120,
      'date_chantier': '2026-10-01',
    };

    final clean = <String, dynamic>{};
    for (final entry in raw.entries) {
      if (kColonnesInterventionsSupabase.contains(entry.key)) {
        clean[entry.key] = entry.value;
      }
    }
    clean['notes'] = mettreAJourNotesAvecMeta(
      notesExistantes: '',
      po: raw['numero_bon_commande']?.toString(),
      unite: raw['numero_unite']?.toString(),
      reference: raw['numero_reference']?.toString(),
      modeleSys: raw['modele_systeme']?.toString(),
    );
    clean['created_at'] = DateTime.now().toIso8601String();
    clean['updated_at'] = DateTime.now().toIso8601String();

    final res = await client.from('interventions').upsert(clean).select();
    print('Inséré dans Supabase: ' + res.length.toString() + ' ligne(s)');
  });
}
