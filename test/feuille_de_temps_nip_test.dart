import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rayco_field_service/nip_service.dart';
import 'package:rayco_field_service/feuille_de_temps.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('🔐 Sécurité NIP & Indépendance Feuilles de Temps', () {
    test('1. Vérification des NIPs par défaut et passe-partout superviseur', () async {
      final nipService = NipSecuriteService.instance;

      // Pierre-Olivier Patry (Camion #102) -> 1020
      expect(await nipService.verifierNip('Pierre-Olivier Patry', '1020'), isTrue);
      expect(await nipService.verifierNip('Patrick Popatry', '1020'), isTrue);
      expect(await nipService.verifierNip('Pierre-Olivier Patry', '0000'), isFalse);

      // David Hestin (Camion #101) -> 1010
      expect(await nipService.verifierNip('David Hestin', '1010'), isTrue);
      expect(await nipService.verifierNip('David Hestin', '1020'), isFalse);

      // Jean-François Allie (Camion #103) -> 1030
      expect(await nipService.verifierNip('Jean-François Allie', '1030'), isTrue);
      expect(await nipService.verifierNip('Jean-François Allie', '1010'), isFalse);

      // Superviseur passe-partout -> 9999 (valide pour tous les techniciens)
      expect(await nipService.verifierNip('Pierre-Olivier Patry', '9999'), isTrue);
      expect(await nipService.verifierNip('David Hestin', '9999'), isTrue);
      expect(await nipService.verifierNip('Jean-François Allie', '9999'), isTrue);
    });

    test('2. Modification du NIP pour un technicien', () async {
      final nipService = NipSecuriteService.instance;

      // Changer le NIP de David Hestin
      await nipService.setNipPourTechnicien('David Hestin', '5555');
      expect(await nipService.verifierNip('David Hestin', '5555'), isTrue);
      expect(await nipService.verifierNip('David Hestin', '1010'), isFalse);

      // Rétablir le NIP par défaut pour les tests suivants
      await nipService.setNipPourTechnicien('David Hestin', '1010');
      expect(await nipService.verifierNip('David Hestin', '1010'), isTrue);
    });

    test('3. Étanchéité et indépendance des périodes de paie par technicien', () async {
      final repo = FeuilleDeTempsRepository.instance;

      // Période David Hestin
      final periodeDavid = await repo.getPeriodePaieActuelle(technicien: 'David Hestin');
      expect(periodeDavid.technicien, equals('David Hestin'));
      expect(periodeDavid.numeroCamion, equals('Camion #101'));

      // Période Pierre-Olivier Patry
      final periodePO = await repo.getPeriodePaieActuelle(technicien: 'Pierre-Olivier Patry');
      expect(periodePO.technicien, equals('Pierre-Olivier Patry'));
      expect(periodePO.numeroCamion, equals('Camion #102'));

      // Période Jean-François Allie
      final periodeJFA = await repo.getPeriodePaieActuelle(technicien: 'Jean-François Allie');
      expect(periodeJFA.technicien, equals('Jean-François Allie'));
      expect(periodeJFA.numeroCamion, equals('Camion #103'));
    });

    test('4. Remise anticipée indépendante par technicien', () async {
      final repo = FeuilleDeTempsRepository.instance;
      final now = DateTime.now();
      final jeudi = now.add(Duration(days: DateTime.thursday - now.weekday));

      // Appliquer une remise anticipée au jeudi pour David Hestin
      await repo.appliquerRemiseAnticipee(
        dateRemise: jeudi,
        minutesParJourRestant: 480,
        technicien: 'David Hestin',
        notes: 'Départ congé David',
      );

      final pDavid = await repo.getPeriodePaieActuelle(technicien: 'David Hestin');
      expect(pDavid.dateRemisePersonnalisee, isNotNull);

      // Vérifier que Pierre-Olivier Patry n'est PAS affecté
      final pPO = await repo.getPeriodePaieActuelle(technicien: 'Pierre-Olivier Patry');
      expect(pPO.dateRemisePersonnalisee, isNull);

      // Rétablir
      await repo.reinitialiserDateRemise(technicien: 'David Hestin');
    });

    testWidgets('5. UI FeuilleDeTempsScreen : En-tête technicien et verrouillage NIP initial', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));

      await tester.pumpWidget(
        const MaterialApp(
          home: FeuilleDeTempsScreen(technicienInitial: 'Pierre-Olivier Patry'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Vérifier la présence du sélecteur technicien et du badge verrouillé
      expect(find.byKey(const Key('technicien_dropdown')), findsOneWidget);
      expect(find.text('Pierre-Olivier Patry'), findsWidgets);
      expect(find.text('Camion #102'), findsWidgets);
      expect(find.text('Verrouillé'), findsOneWidget);
    });

    testWidgets('6. UI FeuilleDeTempsScreen : Demande et validation du NIP lors de la modification', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));

      await tester.pumpWidget(
        const MaterialApp(
          home: FeuilleDeTempsScreen(technicienInitial: 'Pierre-Olivier Patry'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Trouver et cliquer sur le bouton de modification d'une journée
      final editButtons = find.byIcon(Icons.edit_outlined);
      expect(editButtons, findsWidgets);

      await tester.tap(editButtons.first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Le dialogue de NIP doit apparaître
      expect(find.text('Protection par NIP'), findsOneWidget);
      expect(find.byKey(const Key('nip_input_field')), findsOneWidget);

      // 1. Saisir un code erroné
      await tester.enterText(find.byKey(const Key('nip_input_field')), '0000');
      await tester.tap(find.byKey(const Key('valider_nip_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.textContaining('Code NIP incorrect'), findsOneWidget);

      // 2. Saisir le bon code NIP de Pierre-Olivier Patry (1020)
      await tester.enterText(find.byKey(const Key('nip_input_field')), '1020');
      await tester.tap(find.byKey(const Key('valider_nip_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Le modal de modification des heures de la journée doit s'ouvrir
      expect(find.textContaining('Modifier -'), findsOneWidget);

      // Fermer le dialogue
      final closeBtn = find.byIcon(Icons.close);
      if (closeBtn.evaluate().isNotEmpty) {
        await tester.tap(closeBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
      }

      // La session est maintenant déverrouillée
      expect(find.text('Déverrouillé'), findsOneWidget);
    });

    testWidgets('7. UI FeuilleDeTempsScreen : Changement de technicien et reverrouillage automatique anti-tampering', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));

      await tester.pumpWidget(
        const MaterialApp(
          home: FeuilleDeTempsScreen(technicienInitial: 'Pierre-Olivier Patry'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Déverrouiller la session via le bouton badge
      await tester.tap(find.byKey(const Key('nip_lock_toggle_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byKey(const Key('nip_input_field')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('nip_input_field')), '1020');
      await tester.tap(find.byKey(const Key('valider_nip_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Déverrouillé'), findsOneWidget);

      // Changer de technicien vers David Hestin
      await tester.tap(find.byKey(const Key('technicien_dropdown')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final davidItem = find.text('David Hestin').last;
      await tester.tap(davidItem);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Vérifier que la session s'est immédiatement reverrouillée pour la sécurité du compte de David
      expect(find.text('Verrouillé'), findsOneWidget);
      expect(find.text('Camion #101'), findsWidgets);
    });

    testWidgets('8. UI FeuilleDeTempsScreen : Poinçon Clock-in/out protégé par NIP quand verrouillé', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));

      await tester.pumpWidget(
        const MaterialApp(
          home: FeuilleDeTempsScreen(technicienInitial: 'Pierre-Olivier Patry'),
        ),
      );
      await tester.pumpAndSettle();

      // Aller sur l'onglet Aujourd'hui
      await tester.tap(find.text("Aujourd'hui"));
      await tester.pumpAndSettle();

      // Trouver le bouton Clock-in / Clock-out
      final punchBtn = find.textContaining('CLOCK-');
      expect(punchBtn, findsOneWidget);

      await tester.tap(punchBtn);
      await tester.pumpAndSettle();

      // Le dialogue de NIP doit s'afficher car la session est verrouillée
      expect(find.text('Protection par NIP'), findsOneWidget);
      expect(find.byKey(const Key('nip_input_field')), findsOneWidget);

      // Saisir le bon code NIP de Pierre-Olivier Patry (1020)
      await tester.enterText(find.byKey(const Key('nip_input_field')), '1020');
      await tester.tap(find.byKey(const Key('valider_nip_button')));
      await tester.pumpAndSettle();

      // La session est déverrouillée
      expect(find.text('Déverrouillé'), findsOneWidget);
    });
  });
}
