import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:rayco_field_service/inventaire_donnees.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Inventaire Camions RaycoWylie Tests', () {
    test('Normalisation des camions et techniciens', () {
      expect(InventaireService.normaliserCamion('Camion #101'), 'Camion #101');
      expect(InventaireService.normaliserCamion(null, 'David Hestin'), 'Camion #101');
      expect(InventaireService.normaliserCamion('TECH 1'), 'Camion #101');

      expect(InventaireService.normaliserCamion('Camion #102'), 'Camion #102');
      expect(InventaireService.normaliserCamion(null, 'Pierre-Olivier Patry'), 'Camion #102');
      expect(InventaireService.normaliserCamion('TECH 2'), 'Camion #102');

      expect(InventaireService.normaliserCamion('Camion #103'), 'Camion #103');
      expect(InventaireService.normaliserCamion(null, 'Jean-François Allie'), 'Camion #103');
      expect(InventaireService.normaliserCamion('TECH 3'), 'Camion #103');
    });

    test('Structure du fichier JSON officiel', () {
      final file = File('assets/inventaires/inventaire_camions.json');
      expect(file.existsSync(), true, reason: 'Le fichier inventaire_camions.json doit exister');

      final content = file.readAsStringSync();
      final Map<String, dynamic> data = jsonDecode(content);

      expect(data.containsKey('tech_01'), true);
      expect(data.containsKey('tech_02'), true);
      expect(data.containsKey('tech_03'), true);

      final t1 = data['tech_01'];
      final t2 = data['tech_02'];
      final t3 = data['tech_03'];

      expect(t1['technicien'], 'David Hestin');
      expect(t1['camion'], 'Camion #101');
      expect((t1['articles'] as List).length, 182);

      expect(t2['technicien'], 'Pierre-Olivier Patry');
      expect(t2['camion'], 'Camion #102');
      expect((t2['articles'] as List).length, 231);

      expect(t3['technicien'], 'Jean-François Allie');
      expect(t3['camion'], 'Camion #103');
      expect((t3['articles'] as List).length, 140);
    });

    test('Déduction de pièces par camion de technicien', () {
      final service = InventaireService.instance;

      // Charger les données de test
      final file = File('assets/inventaires/inventaire_camions.json');
      final Map<String, dynamic> data = jsonDecode(file.readAsStringSync());

      final List<ArticleCamion> articles = [];
      data.forEach((k, v) {
        final c = v['camion'].toString();
        final t = v['technicien'].toString();
        final loc = v['localisation'].toString();
        for (final a in (v['articles'] as List)) {
          articles.add(ArticleCamion.fromJson(
            Map<String, dynamic>.from(a as Map),
            defaultCamion: c,
            defaultTech: t,
            defaultLoc: loc,
          ));
        }
      });

      // Charger dans le service
      service.chargerDepuisArticles(articles);

      // Trouver un article présent dans Camion #102
      final art102 = articles.firstWhere(
        (a) => a.camion == 'Camion #102' && a.quantite > 2,
      );
      final initialQte = art102.quantite;

      // Simuler une intervention clôturée par Pierre-Olivier Patry (Camion #102)
      final piecesUtilisees = [
        {
          'ref': art102.ref,
          'utilise': 2,
          'camion': 'Camion #102',
        }
      ];

      // Exécuter la déduction
      service.deduirePieces(
        piecesUtilisees,
        camion: 'Camion #102',
        technicien: 'Pierre-Olivier Patry',
      );

      // Vérifier que la déduction a bien été faite
      final qteApres = service.getStockPourCamion(art102.ref, 'Camion #102');
      expect(qteApres, initialQte - 2);
    });
  });
}
