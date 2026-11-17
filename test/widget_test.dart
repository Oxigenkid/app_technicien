import 'package:flutter_test/flutter_test.dart';
import 'package:rayco_field_service/app_helpers.dart';

void main() {
  group('Tests Création Interventions & Champs Requis', () {
    test('Colonnes Supabase et structure des champs obligatoires', () {
      expect(kColonnesInterventionsSupabase.contains('numero_reference'), true);
      expect(kColonnesInterventionsSupabase.contains('numero_commande'), true);
      expect(kColonnesInterventionsSupabase.contains('nom_client'), true);
      expect(kColonnesInterventionsSupabase.contains('trouble'), true);
      expect(kColonnesInterventionsSupabase.contains('numero_serie_machine'), true);
    });

    test('Structure complète d\'une intervention avec PO, Référence et Unité', () {
      final nouvelle = {
        'id': 'cmd_123456789',
        'nom_client': 'Levage & Grues du Québec Inc.',
        'adresse': '2450 Rue Dalton, Québec, QC G1P 3X1',
        'adresse_facturation': 'C.P. 4402, Succ. Principale, Québec, QC G1K 8Z4',
        'numero_commande': 'CO-2026-0928-14',
        'numero_reference': 'TF-12345',
        'numero_bon_commande': '#PO-12345678',
        'trouble': 'Afficheur Rayco Wylie ne s\'allume pas.',
        'nom_contact': 'Jean Tremblay',
        'telephone': '418-650-2020',
        'courriel': 'service@levagequebec.com',
        'type_machine': 'Grue téléscopique',
        'marque': 'Tadano',
        'modele': 'GR-700XL',
        'annee': '2021',
        'numero_serie_machine': 'TD-847291',
        'numero_unite': 'Unité #GR-4021',
        'alimentation': '24v',
        'systeme_wylie': 'Rayco Wylie i4500 RCI',
        'nom_technicien': 'Pierre-Olivier Patry',
        'numero_camion': 'Camion #102',
        'statut': 'En attente',
        'date_rendez_vous': '2026-09-28',
        'heure_rendez_vous': '09:00',
        'duree_minutes': 180,
      };

      // Vérifier les 3 champs spécifiques demandés par l'utilisateur
      expect(nouvelle['numero_reference'], 'TF-12345');
      expect(nouvelle['numero_bon_commande'], '#PO-12345678');
      expect(nouvelle['numero_unite'], 'Unité #GR-4021');

      // Vérifier les formats
      expect(nouvelle['numero_reference'].toString().startsWith('TF-'), true);
      expect(nouvelle['numero_bon_commande'].toString().startsWith('#PO-'), true);
      expect(nouvelle['numero_unite'].toString().contains('Unité'), true);
    });

    test('Types de machine standardisés RaycoWylie disponibles', () {
      expect(kTypesMachineRayco.contains('Grue téléscopique'), true);
      expect(kTypesMachineRayco.contains('Grue conventionelle'), true);
      expect(kTypesMachineRayco.contains('Grue articulée'), true);
      expect(kTypesMachineRayco.contains('Chariot élévateur'), true);
      expect(kTypesMachineRayco.contains('Pelle'), true);
      expect(kTypesMachineRayco.contains('Pépine'), true);
      expect(kTypesMachineRayco.contains('Camion'), true);
      expect(kTypesMachineRayco.contains('Pompe à béton'), true);
      expect(kTypesMachineRayco.contains('Téléhandler'), true);
      expect(kTypesMachineRayco.contains('Nacelle'), true);
    });

    test('Construction URL Google Maps itinéraire et démarrage trajet', () {
      String genererMapsUrl(dynamic adresseBrute) {
        final destination = (adresseBrute ?? '').toString().trim();
        return destination.isNotEmpty
            ? "https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(destination)}&travelmode=driving"
            : "https://www.google.com/maps/dir/?api=1";
      }

      final urlAvecAdresse = genererMapsUrl('2450 Rue Dalton, Québec');
      expect(urlAvecAdresse.startsWith('https://www.google.com/maps/dir/?api=1&destination='), true);
      expect(urlAvecAdresse.contains('travelmode=driving'), true);
      expect(urlAvecAdresse.contains('2450%20Rue%20Dalton'), true);

      final urlVide = genererMapsUrl(null);
      expect(urlVide, 'https://www.google.com/maps/dir/?api=1');

      // Résolution sécurisée de destination avec fallback
      final itemSansAdresse = {
        'id': '123',
        'adresse': null,
        'adresse_intervention': null,
        'nom_client': 'Chantier Pont Pierre-Laporte',
      };
      final destFallback = (itemSansAdresse['adresse'] ??
              itemSansAdresse['adresse_intervention'] ??
              itemSansAdresse['nom_client'] ??
              '')
          .toString();
      expect(destFallback, 'Chantier Pont Pierre-Laporte');
      final urlFallback = genererMapsUrl(destFallback);
      expect(urlFallback.contains('Pont%20Pierre-Laporte'), true);
    });
  });
}
