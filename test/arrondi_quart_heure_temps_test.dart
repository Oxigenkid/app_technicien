import 'package:flutter_test/flutter_test.dart';
import 'package:rayco_field_service/app_helpers.dart';
import 'package:rayco_field_service/feuille_de_temps.dart';

void main() {
  group('⏱️ Tests de calcul du temps de travail & Arrondi au quart d\'heure', () {
    test('1. Fonction utilitaire d\'arrondi au quart d\'heure (minutes et secondes)', () {
      // Déplacement et Chantier (toujoursPlusHaut = true)
      expect(arrondirAuQuartDHeureMinutes(0, toujoursPlusHaut: true), equals(0));
      expect(arrondirAuQuartDHeureMinutes(1, toujoursPlusHaut: true), equals(15));
      expect(arrondirAuQuartDHeureMinutes(14, toujoursPlusHaut: true), equals(15));
      expect(arrondirAuQuartDHeureMinutes(15, toujoursPlusHaut: true), equals(15));
      expect(arrondirAuQuartDHeureMinutes(16, toujoursPlusHaut: true), equals(30));
      expect(arrondirAuQuartDHeureMinutes(29, toujoursPlusHaut: true), equals(30));
      expect(arrondirAuQuartDHeureMinutes(30, toujoursPlusHaut: true), equals(30));
      expect(arrondirAuQuartDHeureMinutes(31, toujoursPlusHaut: true), equals(45));
      expect(arrondirAuQuartDHeureMinutes(45, toujoursPlusHaut: true), equals(45));
      expect(arrondirAuQuartDHeureMinutes(46, toujoursPlusHaut: true), equals(60));
      expect(arrondirAuQuartDHeureMinutes(61, toujoursPlusHaut: true), equals(75));

      // Arrondi en secondes
      expect(arrondirAuQuartDHeureSecondes(0, toujoursPlusHaut: true), equals(0));
      expect(arrondirAuQuartDHeureSecondes(30, toujoursPlusHaut: true), equals(15 * 60)); // 1 min -> 15 min
      expect(arrondirAuQuartDHeureSecondes(16 * 60, toujoursPlusHaut: true), equals(30 * 60)); // 16 min -> 30 min

      // Format chrono
      expect(formatChrono(0), equals('00:00:00'));
      expect(formatChrono(65), equals('00:01:05'));
      expect(formatChrono(3665), equals('01:01:05'));
    });

    test('2. ActiviteQuart : Déplacement et Travail arrondis au quart d\'heure supérieur', () {
      final now = DateTime.now();

      // Déplacement de 18 minutes -> arrondi au 1/4h sup. -> 30 minutes
      final actTrajet = ActiviteQuart(
        id: 't1',
        type: TypeActivite.deplacement,
        description: 'Trajet vers chantier',
        debut: now.subtract(const Duration(minutes: 18)),
        fin: now,
      );
      expect(actTrajet.dureeMinutesBrute, equals(18));
      expect(actTrajet.dureeMinutes, equals(30));
      expect(actTrajet.estPaye, isTrue);

      // Travail en chantier de 32 minutes -> arrondi au 1/4h sup. -> 45 minutes
      final actTravail = ActiviteQuart(
        id: 'w1',
        type: TypeActivite.travail,
        description: 'Chantier installation',
        debut: now.subtract(const Duration(minutes: 32)),
        fin: now,
      );
      expect(actTravail.dureeMinutesBrute, equals(32));
      expect(actTravail.dureeMinutes, equals(45));
      expect(actTravail.estPaye, isTrue);

      // Pause repas de 40 minutes -> arrondi au 1/4h le plus proche -> 45 minutes
      final actRepas = ActiviteQuart(
        id: 'r1',
        type: TypeActivite.repas,
        description: 'Dîner',
        debut: now.subtract(const Duration(minutes: 40)),
        fin: now,
      );
      expect(actRepas.dureeMinutesBrute, equals(40));
      expect(actRepas.dureeMinutes, equals(45));
      expect(actRepas.estPaye, isFalse);

      // Pause attente de 16 minutes -> arrondi au 1/4h -> 15 minutes
      final actAttente = ActiviteQuart(
        id: 'a1',
        type: TypeActivite.attente,
        description: 'Attente grue',
        debut: now.subtract(const Duration(minutes: 16)),
        fin: now,
      );
      expect(actAttente.dureeMinutesBrute, equals(16));
      expect(actAttente.dureeMinutes, equals(15));
      expect(actAttente.estPaye, isTrue);
    });

    test('3. QuartDeTravail : Calcul total du temps payé avec les 4 composantes', () {
      final now = DateTime.now();
      final date = DateTime(now.year, now.month, now.day);

      // Création d'un quart avec :
      // - Trajet : 18 min brute -> 30 min payées
      // - Chantier : 32 min brute -> 45 min payées
      // - Attente : 16 min brute -> 15 min payées
      // - Repas : 40 min brute -> 45 min déduites
      final quart = QuartDeTravail(
        id: 'q_test_01',
        date: date,
        technicien: 'Pierre-Olivier Patry',
        clockIn: DateTime(date.year, date.month, date.day, 8, 0),
        clockOut: DateTime(date.year, date.month, date.day, 10, 0),
        activites: [
          ActiviteQuart(
            id: 't1',
            type: TypeActivite.deplacement,
            description: 'Trajet',
            debut: DateTime(date.year, date.month, date.day, 8, 0),
            fin: DateTime(date.year, date.month, date.day, 8, 18),
          ),
          ActiviteQuart(
            id: 'w1',
            type: TypeActivite.travail,
            description: 'Chantier',
            debut: DateTime(date.year, date.month, date.day, 8, 18),
            fin: DateTime(date.year, date.month, date.day, 8, 50),
          ),
          ActiviteQuart(
            id: 'a1',
            type: TypeActivite.attente,
            description: 'Attente client',
            debut: DateTime(date.year, date.month, date.day, 8, 50),
            fin: DateTime(date.year, date.month, date.day, 9, 6),
          ),
          ActiviteQuart(
            id: 'r1',
            type: TypeActivite.repas,
            description: 'Repas',
            debut: DateTime(date.year, date.month, date.day, 9, 6),
            fin: DateTime(date.year, date.month, date.day, 9, 46),
          ),
        ],
      );

      expect(quart.totalDeplacementMinutes, equals(30)); // 18m -> 30m
      expect(quart.totalTravailMinutes, equals(45));     // 32m -> 45m
      expect(quart.totalAttenteMinutes, equals(15));     // 16m -> 15m
      expect(quart.totalRepasMinutes, equals(45));       // 40m -> 45m

      // Temps payé = Deplacement + Travail + Attente = 30 + 45 + 15 = 90 min (1h 30m = 1.50 h)
      expect(quart.tempsPayeMinutes, equals(90));
      expect(quart.tempsPayeDecimal, equals(1.50));
      expect(quart.tempsPayeFormate, equals('1h 30m'));
    });

    test('4. Synchronisation d\'intervention avec règle du quart d\'heure supérieur', () async {
      final repo = FeuilleDeTempsRepository.instance;
      final now = DateTime.now();

      final intervention = <String, dynamic>{
        'id': 'test_interv_round_99',
        'nom_technicien': 'Pierre-Olivier Patry',
        'nom_client': 'Excavations ABC',
        'numero_bon_commande': 'PO-9988',
        'type_machine': 'Grue Mobile 50T',
        'heure_depart_trajet': now.subtract(const Duration(minutes: 22)).toIso8601String(),
        'heure_arrivee_site': now.subtract(const Duration(minutes: 5)).toIso8601String(),
        'heure_cloture': now.toIso8601String(),
        'duree_pause_secondes': 0,
        'duree_pause_chantier_secondes': 0,
        'statut': 'Complété',
      };

      await repo.synchroniserIntervention(intervention, sauvegarderApres: false);

      final quarts = await repo.getQuarts(technicien: 'Pierre-Olivier Patry');
      final quart = quarts.firstWhere(
        (q) => q.date.year == now.year && q.date.month == now.month && q.date.day == now.day,
      );

      // Trajet de 17 minutes (22 - 5) -> arrondi au 1/4h sup. -> 30 minutes
      expect(quart.totalDeplacementMinutes, greaterThanOrEqualTo(30));

      // Chantier de 5 minutes -> arrondi au 1/4h sup. -> 15 minutes
      expect(quart.totalTravailMinutes, greaterThanOrEqualTo(15));

      // Les minutes payées doivent être un multiple exact de 15 (quart d'heure)
      expect(quart.tempsPayeMinutes % 15, equals(0));
    });
  });
}
