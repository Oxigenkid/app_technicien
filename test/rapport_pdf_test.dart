import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:rayco_field_service/app_helpers.dart';
import 'package:rayco_field_service/rapport_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final intervention = <String, dynamic>{
    'id': 'test-123',
    'numero_rapport': '2609290830',
    'nom_client': 'Coffrage Synergique Inc.',
    'adresse': '123 Boulevard Industriel, Québec',
    'nom_technicien': 'Pierre-Olivier Patry',
    'numero_camion': 'Camion #102',
    'date_chantier': '2026-09-29',
    'type_machine': 'Grue télescopique',
    'marque': 'Tadano',
    'modele': 'GR-1000XL',
    'numero_serie_machine': 'TDN-9988',
    'annee': '2022',
    'systeme_wylie': 'Rayco Wylie i4500 RCI',
    'numero_commande': 'CMD-8833',
    'numero_bon_commande': 'PO-7744',
    'numero_reference': 'REF-1122',
    'trouble': 'Calibration capteur angle et longueur à réviser.',
    'notes': 'Calibration complétée avec succès. Système vérifié en charge et conforme.',
    'heure_depart_trajet': '2026-09-29T07:00:00.000Z',
    'heure_arrivee_site': '2026-09-29T08:00:00.000Z',
    'heure_cloture': '2026-09-29T11:30:00.000Z',
    'duree_trajet': '1h 00m',
    'duree_chantier': '3h 30m',
    'duree_chantier_secondes': 12600,
    'distance_km': 65,
    'pieces_utilisees': jsonEncode([
      {'reference': 'CAB-001', 'designation': 'Câble capteur longueur', 'quantite': 1}
    ]),
    'photos': jsonEncode([]),
    // Tiny valid 1x1 png base64
    'signature': 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  };

  test('1. Test génération des octets PDF du rapport d\'intervention', () async {
    final bytes = await RapportPdfService.genererBytesPdf(
      intervention,
      formatSeconds: formatSeconds,
      formatHeure: formatHeure,
    );

    expect(bytes, isNotEmpty);
    expect(bytes.length, greaterThan(1000));
  });

  test('2. Test sauvegarde automatique du rapport PDF sur disque', () async {
    final bytes = await RapportPdfService.genererBytesPdf(
      intervention,
      formatSeconds: formatSeconds,
      formatHeure: formatHeure,
    );

    final tempDir = Directory.systemTemp.createTempSync('rayco_test_pdf_');
    final savedPath = await RapportPdfService.sauvegarderRapportPdfSurDisque(
      intervention: intervention,
      pdfBytes: bytes,
      getNumeroDossier: (i) => 'TEST_DOSSIER',
      getDossierPhotos: (dossier) => Directory('${tempDir.path}\\$dossier'),
    );

    expect(savedPath, isNotNull);
    final savedFile = File(savedPath!);
    expect(savedFile.existsSync(), isTrue);
    expect(savedFile.lengthSync(), equals(bytes.length));

    // Nettoyage temporaire
    tempDir.deleteSync(recursive: true);
  });

  test('3. Test genererEtSauvegarderAutomatiquement', () async {
    final tempDir = Directory.systemTemp.createTempSync('rayco_test_auto_');
    final savedPath = await RapportPdfService.genererEtSauvegarderAutomatiquement(
      intervention: intervention,
      getNumeroDossier: (i) => 'TEST_AUTO_DOSSIER',
      getDossierPhotos: (dossier) => Directory('${tempDir.path}\\$dossier'),
      formatSeconds: formatSeconds,
      formatHeure: formatHeure,
    );

    expect(savedPath, isNotNull);
    expect(File(savedPath!).existsSync(), isTrue);

    tempDir.deleteSync(recursive: true);
  });

  test('4. Test checklist contrôle de sécurité (cochée seulement si validée)', () async {
    // 1. Intervention sans contrôle spécifié : doit retourner une liste vide (aucune case cochée par défaut)
    final interVide = <String, dynamic>{'notes': 'Sans balise'};
    expect(getControlesSecurite(interVide), isEmpty);

    // 2. Intervention avec 2 contrôles validés explicitement
    final checks = [
      'Capteurs d\'angle et de longueur inspectés & calibrés',
      'Interrupteur Anti-Two-Block (A2B) et coupure testés',
    ];
    final interPartielle = <String, dynamic>{
      ...intervention,
      'controles_securite': jsonEncode(checks),
    };
    final recuperes = getControlesSecurite(interPartielle);
    expect(recuperes.length, equals(2));
    expect(recuperes, contains(checks[0]));
    expect(recuperes, contains(checks[1]));

    // 3. Génération du PDF avec checklist partielle
    final bytes = await RapportPdfService.genererBytesPdf(
      interPartielle,
      formatSeconds: formatSeconds,
      formatHeure: formatHeure,
    );
    expect(bytes, isNotEmpty);
  });
}
