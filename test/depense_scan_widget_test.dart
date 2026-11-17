import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rayco_field_service/depenses_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Tests Widget Compte de Dépenses & Scanner IA', () {
    setUp(() async {
      await DepenseService.instance.charger();
    });

    testWidgets('1. Affichage du bouton Scanner Facture (IA) et ouverture du modal', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: DepenseScreen(initialementDeverrouille: true),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Vérifier la présence du bouton de scan IA dans la carte sommaire
      expect(find.text('Scanner Facture (IA)'), findsWidgets);
      expect(find.text('Manuelle'), findsOneWidget);

      // Ouvrir le modal d'ajout de dépense via le bouton Manuelle
      await tester.tap(find.text('Manuelle'));
      await tester.pumpAndSettle();

      // Vérifier la présence du titre et de la bannière IA
      expect(find.text('Nouvelle Dépense en Chantier'), findsOneWidget);
      expect(find.text('Scan & Remplissage Automatique IA'), findsOneWidget);
      expect(find.text('Exemples de test'), findsOneWidget);
    });

    testWidgets('2. Remplissage automatique sans saisie manuelle via un exemple de test', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: DepenseScreen(initialementDeverrouille: true),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(find.text('Manuelle'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Exemples de test'));
      await tester.pumpAndSettle();

      // Choisir l'exemple Pétro-Canada
      final petroExempleFinder = find.text('Pétro-Canada (Carburant Diesel)');
      expect(petroExempleFinder, findsOneWidget);

      await tester.tap(petroExempleFinder);
      await tester.pumpAndSettle(const Duration(milliseconds: 600));

      // Vérifier que la facture a été analysée avec succès
      expect(find.text('Facture analysée avec succès par IA !'), findsOneWidget);

      // Vérifier que le montant, le fournisseur et la description sont remplis automatiquement
      expect(find.widgetWithText(TextField, '164.95'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Petro-Canada'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'TX-849204'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Plein de carburant / Diesel - Petro-Canada'), findsOneWidget);

      // Vérifier la catégorie automatique
      expect(find.text('Carburant / Diesel'), findsWidgets);
    });

    testWidgets('3. Remplissage automatique restaurant avec séparation du pourboire', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: DepenseScreen(initialementDeverrouille: true),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(find.text('Manuelle'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Exemples de test'));
      await tester.pumpAndSettle();

      // Choisir l'exemple St-Hubert
      final stHubertFinder = find.text('St-Hubert (Dîner & Pourboire)');
      expect(stHubertFinder, findsOneWidget);

      await tester.tap(stHubertFinder);
      await tester.pumpAndSettle(const Duration(milliseconds: 600));

      // Vérifier la séparation du repas et du pourboire
      expect(find.text('Facture analysée avec succès par IA !'), findsOneWidget);
      expect(find.widgetWithText(TextField, '35.59'), findsOneWidget); // Repas
      expect(find.widgetWithText(TextField, '5.50'), findsOneWidget);  // Pourboire
      expect(find.widgetWithText(TextField, 'St-Hubert'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'SH-2026-9912'), findsOneWidget);
    });

    testWidgets('4. Facture floue ou illisible affiche une alerte claire', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: DepenseScreen(initialementDeverrouille: true),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(find.text('Manuelle'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Exemples de test'));
      await tester.pumpAndSettle();

      // Choisir l'exemple Facture Floue
      final flouFinder = find.text('Facture Floue / Illisible (Test alerte)');
      expect(flouFinder, findsOneWidget);

      await tester.tap(flouFinder);
      await tester.pumpAndSettle(const Duration(milliseconds: 600));

      // Vérifier la présence du badge d'avertissement
      expect(find.text('Facture difficile à lire ou floue'), findsOneWidget);
    });

    testWidgets('5. Sécurité NIP : Blocage si verrouillé, rejet si erroné, déverrouillage si valide', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // Démarrage en mode verrouillé par défaut (initialementDeverrouille: false)
      await tester.pumpWidget(
        const MaterialApp(
          home: DepenseScreen(initialementDeverrouille: false),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Vérifier que le statut indique Verrouillé
      expect(find.text('Verrouillé'), findsOneWidget);

      // Cliquer sur le bouton "Manuelle" -> Doit ouvrir le dialogue NIP
      await tester.tap(find.text('Manuelle'));
      await tester.pumpAndSettle();

      expect(find.text('Protection par NIP'), findsOneWidget);
      expect(find.text('Sécurisation du compte technicien'), findsOneWidget);

      // Saisir un mauvais NIP (0000)
      final nipField = find.byType(TextField);
      await tester.enterText(nipField, '0000');
      await tester.pump();

      await tester.tap(find.text('Déverrouiller'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Vérifier que l'erreur est affichée et le modal toujours présent
      expect(find.textContaining('Code NIP incorrect'), findsOneWidget);

      // Saisir le bon NIP (Pierre-Olivier Patry = 1020)
      await tester.enterText(find.byType(TextField), '1020');
      await tester.pump();

      await tester.tap(find.text('Déverrouiller'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // Le compte est maintenant déverrouillé et le modal de dépense s'est ouvert
      expect(find.text('Nouvelle Dépense en Chantier'), findsOneWidget);
    });

    testWidgets('6. Indépendance des comptes techniciens : affichage distinct et verrouillage au changement', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: DepenseScreen(initialementDeverrouille: true),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Vérifier que Pierre-Olivier Patry est sélectionné par défaut
      expect(find.textContaining('Pierre-Olivier Patry'), findsWidgets);
      expect(find.text('Déverrouillé'), findsOneWidget);

      // Changer de technicien via le Dropdown vers David Hestin
      await tester.tap(find.byKey(const Key('technicien_dropdown')));
      await tester.pumpAndSettle();

      // Sélectionner David Hestin dans le menu
      final davidOption = find.text('David Hestin').last;
      await tester.tap(davidOption);
      await tester.pumpAndSettle();

      // Le compte de David Hestin doit être actif et reverrouillé pour sécurité
      expect(find.textContaining('David Hestin'), findsWidgets);
      expect(find.text('Verrouillé'), findsOneWidget);

      // Tenter d'ajouter une dépense demande maintenant le NIP de David
      await tester.tap(find.text('Manuelle'));
      await tester.pumpAndSettle();

      expect(find.text('Protection par NIP'), findsOneWidget);
      expect(find.textContaining('David Hestin'), findsWidgets);
    });

    testWidgets('7. Modification d\'une dépense existante via le bouton d\'édition', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: DepenseScreen(initialementDeverrouille: true),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Trouver le bouton d'édition (Icons.edit_outlined)
      final editButton = find.byIcon(Icons.edit_outlined);
      expect(editButton, findsWidgets);

      // Cliquer sur le premier bouton d'édition
      await tester.tap(editButton.first);
      await tester.pumpAndSettle();

      // Vérifier que le modal de modification s'est ouvert avec les données pré-remplies
      expect(find.text('Modifier la Dépense'), findsOneWidget);
      expect(find.text('Enregistrer les modifications'), findsOneWidget);
    });
  });
}
