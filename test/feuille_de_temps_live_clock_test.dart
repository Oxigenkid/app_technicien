import 'package:flutter_test/flutter_test.dart';
import 'package:rayco_field_service/feuille_de_temps.dart';
import 'package:rayco_field_service/app_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('⏱️ Horodateur, Feuilles de temps & Arrondis au Quart d\'Heure', () {
    test('1. Arrondi au quart d\'heure (règles trajet, chantier, repas)', () {
      // Trajet & Chantier : TOUJOURS au quart d'heure supérieur (plus haut)
      expect(arrondirAuQuartDHeureMinutes(1, toujoursPlusHaut: true), equals(15));
      expect(arrondirAuQuartDHeureMinutes(15, toujoursPlusHaut: true), equals(15));
      expect(arrondirAuQuartDHeureMinutes(16, toujoursPlusHaut: true), equals(30));
      expect(arrondirAuQuartDHeureMinutes(31, toujoursPlusHaut: true), equals(45));
      expect(arrondirAuQuartDHeureMinutes(46, toujoursPlusHaut: true), equals(60));

      // Pauses et arrêts normaux : arrondi standard au quart d'heure le plus proche
      expect(arrondirAuQuartDHeureMinutes(6), equals(0));
      expect(arrondirAuQuartDHeureMinutes(8), equals(15));
      expect(arrondirAuQuartDHeureMinutes(22), equals(15));
      expect(arrondirAuQuartDHeureMinutes(23), equals(30));
    });

    test('2. Clock-In active immédiatement le quart et passe estActif à true', () async {
      final repo = FeuilleDeTempsRepository.instance;
      await repo.charger();

      final now = DateTime.now();
      final quart = await repo.clockIn(technicien: 'Pierre-Olivier Patry', heure: now);

      expect(quart.estActif, isTrue);
      expect(quart.clockOut, isNull);
      expect(quart.clockIn.year, equals(now.year));
      expect(quart.clockIn.day, equals(now.day));

      // Vérifier la détection par getQuartActif
      final actif = repo.getQuartActif(technicien: 'Pierre-Olivier Patry');
      expect(actif, isNotNull);
      expect(actif!.estActif, isTrue);
    });

    test('3. Clock-Out termine le quart et passe estActif à false', () async {
      final repo = FeuilleDeTempsRepository.instance;
      await repo.charger();

      var actifAvant = repo.getQuartActif(technicien: 'Pierre-Olivier Patry');
      actifAvant ??= await repo.clockIn(technicien: 'Pierre-Olivier Patry', heure: DateTime.now());
      expect(actifAvant, isNotNull);

      final now = DateTime.now();
      await repo.clockOut(actifAvant.id, technicien: 'Pierre-Olivier Patry', heure: now);

      final actifApres = repo.getQuartActif(technicien: 'Pierre-Olivier Patry');
      expect(actifApres, isNull);

      final quartJour = repo.getQuartPourJour(now, technicien: 'Pierre-Olivier Patry');
      expect(quartJour, isNotNull);
      expect(quartJour!.estActif, isFalse);
      expect(quartJour.clockOut, isNotNull);
    });

    test('4. Reprendre le quart (re-Clock-In) réactive le quart sans perdre le début initial', () async {
      final repo = FeuilleDeTempsRepository.instance;
      await repo.charger();

      final debutMatin = DateTime(2026, 9, 29, 7, 30);
      // Créer/activer avec début à 7h30
      final quart = await repo.clockIn(technicien: 'David Hestin', heure: debutMatin);
      expect(quart.clockIn, equals(debutMatin));
      expect(quart.estActif, isTrue);

      // Clock-out à 12h00
      await repo.clockOut(quart.id, technicien: 'David Hestin', heure: DateTime(2026, 9, 29, 12, 0));
      expect(repo.getQuartActif(technicien: 'David Hestin'), isNull);

      // Re-Clock-in à 13h00 : doit réactiver sans effacer le punch initial de 7h30
      final reouvert = await repo.clockIn(technicien: 'David Hestin', heure: DateTime(2026, 9, 29, 13, 0));
      expect(reouvert.estActif, isTrue);
      expect(reouvert.clockIn, equals(debutMatin));
      expect(reouvert.clockOut, isNull);
    });

    test('5. Calcul du temps payé : cumul activités et shift arrondi au quart d\'heure', () {
      final now = DateTime.now();
      final debut = now.subtract(const Duration(hours: 3, minutes: 10)); // 3h10 = 190 min

      final quart = QuartDeTravail(
        id: 'test_calc',
        date: DateTime(now.year, now.month, now.day),
        technicien: 'Pierre-Olivier Patry',
        clockIn: debut,
        clockOut: null, // Actif
        activites: [
          // Trajet 40 min -> arrondi haut à 45 min
          ActiviteQuart(
            id: 'act_1',
            type: TypeActivite.deplacement,
            description: 'Trajet',
            debut: debut,
            fin: debut.add(const Duration(minutes: 40)),
            dureeMinutesFixe: 40,
          ),
          // Travail 1h10 (70 min) -> arrondi haut à 75 min (1h15)
          ActiviteQuart(
            id: 'act_2',
            type: TypeActivite.travail,
            description: 'Chantier',
            debut: debut.add(const Duration(minutes: 40)),
            fin: debut.add(const Duration(minutes: 110)),
            dureeMinutesFixe: 70,
          ),
          // Repas 45 min (déduit)
          ActiviteQuart(
            id: 'act_3',
            type: TypeActivite.repas,
            description: 'Dîner',
            debut: debut.add(const Duration(minutes: 110)),
            fin: debut.add(const Duration(minutes: 155)),
            dureeMinutesFixe: 45,
          ),
        ],
      );

      expect(quart.totalDeplacementMinutes, equals(45)); // 40m arrondi à 45m
      expect(quart.totalTravailMinutes, equals(75));     // 70m arrondi à 75m
      expect(quart.totalRepasMinutes, equals(45));

      // Shift brut : 190m - 45m repas = 145m -> arrondi au quart d'heure supérieur = 150m (2h30)
      // Somme activités payées = 45m + 75m = 120m (2h00)
      // Temps payé prend le max (150m = 2h30)
      expect(quart.tempsPayeMinutes, equals(150));
      expect(quart.tempsPayeFormate, equals('2h 30m'));
    });

    test('6. PUNCH Multi-sessions : cumul exact des périodes et exclusion des pauses', () {
      final jour = DateTime(2026, 9, 29);
      final p1Debut = DateTime(2026, 9, 29, 8, 0);
      final p1Fin = DateTime(2026, 9, 29, 11, 30); // 3h30 = 210 min = 12600s
      final p2Debut = DateTime(2026, 9, 29, 12, 30); // 1h de pause non travaillée (11h30 - 12h30)
      final p2Fin = DateTime(2026, 9, 29, 16, 30); // 4h00 = 240 min = 14400s

      final quart = QuartDeTravail(
        id: 'multi_punch_test',
        date: jour,
        technicien: 'David Hestin',
        clockIn: p1Debut,
        clockOut: p2Fin,
        punches: [
          IntervallePunch(entree: p1Debut, sortie: p1Fin),
          IntervallePunch(entree: p2Debut, sortie: p2Fin),
        ],
      );

      // Cumul exact : 210m + 240m = 450 min (7h30 = 27000s)
      expect(quart.punches.length, equals(2));
      expect(quart.cumulSecondesPunches, equals(27000));
      expect(quart.dureeBruteMinutes, equals(450));
      expect(quart.tempsPayeMinutes, equals(450));
      expect(quart.tempsPayeFormate, equals('7h 30m'));
      expect(quart.estActif, isFalse);
    });

    test('7. assurerClockInActif active automatiquement si aucun quart actif', () async {
      final repo = FeuilleDeTempsRepository.instance;
      await repo.charger();

      // S'assurer que le technicien n'a pas de quart actif (nom unique pour isolation)
      final techTest = 'Tech Iso ${DateTime.now().microsecondsSinceEpoch}';
      expect(repo.getQuartActif(technicien: techTest), isNull);

      // Déclenchement automatique (comme lors d'un départ en trajet)
      final now = DateTime.now();
      final q = await repo.assurerClockInActif(technicien: techTest, heure: now);

      expect(q.estActif, isTrue);
      expect(repo.getQuartActif(technicien: techTest), isNotNull);

      // Appel répété ne doit pas recréer de quart si déjà actif
      final q2 = await repo.assurerClockInActif(technicien: techTest, heure: now.add(const Duration(minutes: 5)));
      expect(q2.id, equals(q.id));
      expect(q2.punches.length, equals(1));
    });

    test('8. clockOut déclenche le callback de mise en pause des interventions', () async {
      final repo = FeuilleDeTempsRepository.instance;
      await repo.charger();

      String? techPauseRecu;
      FeuilleDeTempsRepository.onInterventionsModifieesParClockOut = (tech) {
        techPauseRecu = tech;
      };

      final q = await repo.clockIn(technicien: 'Alexandre Tremblay');
      expect(q.estActif, isTrue);

      await repo.clockOut(q.id, technicien: 'Alexandre Tremblay');
      expect(q.estActif, isFalse);
      expect(techPauseRecu, equals('Alexandre Tremblay'));

      FeuilleDeTempsRepository.onInterventionsModifieesParClockOut = null;
    });
  });
}

