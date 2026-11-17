import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_helpers.dart';

/// Service complet d'export, sauvegarde Windows et envoi Outlook du rapport PDF
class RapportPdfService {
  static pw.Font? _cachedFontRegular;
  static pw.Font? _cachedFontBold;
  static pw.Font? _cachedFontItalic;

  /// Remplace les ligatures et caractères non supportés par certaines polices standard
  static String assainirTextePdf(dynamic val) {
    if (val == null) return '';
    return val
        .toString()
        .replaceAll('œ', 'oe')
        .replaceAll('Œ', 'OE')
        .replaceAll('✓', '')
        .replaceAll('’', "'")
        .replaceAll('‘', "'")
        .replaceAll('–', '-')
        .replaceAll('—', '-')
        .replaceAll('★', '')
        .replaceAll('☆', '')
        .replaceAll('•', '-');
  }

  /// Détection de l'exécutable Outlook sur Windows
  static String? trouverOutlookPath() {
    if (kIsWeb || !Platform.isWindows) return null;
    const candidates = [
      r'C:\Program Files (x86)\Microsoft Office\Root\Office16\OUTLOOK.EXE',
      r'C:\Program Files\Microsoft Office\Root\Office16\OUTLOOK.EXE',
      r'C:\Program Files (x86)\Microsoft Office\Office16\OUTLOOK.EXE',
      r'C:\Program Files\Microsoft Office\Office16\OUTLOOK.EXE',
      r'C:\Program Files (x86)\Microsoft Office\Office15\OUTLOOK.EXE',
      r'C:\Program Files\Microsoft Office\Office15\OUTLOOK.EXE',
      r'C:\Program Files\Microsoft Office\root\Office19\OUTLOOK.EXE',
    ];
    for (final path in candidates) {
      try {
        if (File(path).existsSync()) return path;
      } catch (_) {}
    }
    return null;
  }

  /// Dialogue principal proposant les options demandées par l'utilisateur
  static Future<void> afficherDialogueExport(
    BuildContext context,
    Map<String, dynamic> intervention, {
    required String Function(Map<String, dynamic>) getNumeroDossier,
    required Directory? Function(String) getDossierPhotos,
    required String Function(int) formatSeconds,
    required String Function(dynamic) formatHeure,
    required bool isWindowsDesktop,
  }) async {
    final numRapport = intervention['numero_rapport'] ?? 'Rapport';
    final nomClient = intervention['nom_client'] ?? 'Client';

    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.indigo.shade50,
                    child: const Icon(Icons.picture_as_pdf, color: Colors.indigo),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Exporter le Rapport d\'Intervention',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        Text(
                          'Nº $numRapport • $nomClient',
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),

              // ─── OPTION 1 : ENREGISTRER À L'EMPLACEMENT DÉSIRÉ ──────
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                leading: CircleAvatar(
                  backgroundColor: Colors.blue.shade50,
                  child: const Icon(Icons.folder_open, color: Colors.blueAccent),
                ),
                title: const Text(
                  'Enregistrer le .PDF (Choisir l\'emplacement)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                subtitle: const Text(
                  'Ouvre l\'explorateur pour choisir le dossier et y placer le rapport.',
                  style: TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: () {
                  Navigator.pop(ctx);
                  enregistrerPdfEmplacementChoisi(
                    context,
                    intervention,
                    formatSeconds: formatSeconds,
                    formatHeure: formatHeure,
                    isWindowsDesktop: isWindowsDesktop,
                  );
                },
              ),
              const SizedBox(height: 8),

              // ─── OPTION 2 : ENVOYER AVEC OUTLOOK ────────────────────
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                leading: CircleAvatar(
                  backgroundColor: Colors.indigo.shade50,
                  child: const Icon(Icons.email, color: Colors.indigo),
                ),
                title: const Text(
                  'Envoyer le .PDF par courriel avec Outlook',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                subtitle: Text(
                  intervention['courriel']?.toString().isNotEmpty == true
                      ? 'Ouvre Outlook avec le PDF joint et le destinataire (${intervention['courriel']}).'
                      : 'Ouvre Outlook avec le PDF joint et le message pré-rempli.',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: () {
                  Navigator.pop(ctx);
                  envoyerParOutlook(
                    context,
                    intervention,
                    getNumeroDossier: getNumeroDossier,
                    getDossierPhotos: getDossierPhotos,
                    formatSeconds: formatSeconds,
                    formatHeure: formatHeure,
                    isWindowsDesktop: isWindowsDesktop,
                  );
                },
              ),
              const SizedBox(height: 8),

              // ─── OPTION 3 : IMPRIMER / APERÇU COMPLET ───────────────
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                leading: CircleAvatar(
                  backgroundColor: Colors.teal.shade50,
                  child: const Icon(Icons.print, color: Colors.teal),
                ),
                title: const Text(
                  'Visualiser & Imprimer',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                subtitle: const Text(
                  'Aperçu pleine page, mise en page et impression directe.',
                  style: TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: () {
                  Navigator.pop(ctx);
                  imprimerApercuPdf(
                    context,
                    intervention,
                    formatSeconds: formatSeconds,
                    formatHeure: formatHeure,
                    getNumeroDossier: getNumeroDossier,
                    getDossierPhotos: getDossierPhotos,
                  );
                },
              ),
              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Fermer', style: TextStyle(color: Colors.grey)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Option 1 : Choisir l'emplacement avec l'Explorateur Windows et enregistrer le PDF
  static Future<void> enregistrerPdfEmplacementChoisi(
    BuildContext context,
    Map<String, dynamic> intervention, {
    required String Function(int) formatSeconds,
    required String Function(dynamic) formatHeure,
    required bool isWindowsDesktop,
  }) async {
    try {
      final numRapport = intervention['numero_rapport'] ?? 'Rapport';
      final cleanClient = (intervention['nom_client'] ?? 'Client')
          .toString()
          .trim()
          .replaceAll('&', 'et')
          .replaceAll(RegExp(r'[\\/:*?"<>| ]'), '_');
      final nomFichierSuggere = 'Rapport_${numRapport}_$cleanClient.pdf';

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⏳ Génération du PDF en cours...'),
            duration: Duration(seconds: 1),
          ),
        );
      }

      final pdfBytes = await genererBytesPdf(
        intervention,
        formatSeconds: formatSeconds,
        formatHeure: formatHeure,
      );

      // Ouvre l'Explorateur / sélecteur d'enregistrement natif Windows ou téléchargement Web
      final Uri? uriChoisi = await FilePicker.saveFile(
        dialogTitle: 'Choisir l\'emplacement où enregistrer le rapport PDF',
        fileName: nomFichierSuggere,
        bytes: pdfBytes,
        mimeType: 'application/pdf',
      );

      if (uriChoisi == null) {
        // L'utilisateur a annulé la sélection
        return;
      }

      String cheminFinal = uriChoisi.path;
      if (!kIsWeb) {
        try {
          cheminFinal = uriChoisi.toFilePath();
        } catch (_) {
          cheminFinal = uriChoisi.path;
        }

        // Vérifier si le fichier a été écrit ou s'il faut l'écrire
        try {
          final f = File(cheminFinal);
          if (!f.existsSync() || f.lengthSync() == 0) {
            await f.writeAsBytes(pdfBytes);
          }
        } catch (_) {}

        // Ouvre l'explorateur Windows avec le fichier sélectionné
        if (isWindowsDesktop) {
          try {
            await Process.run('explorer.exe', ['/select,', cheminFinal]);
          } catch (_) {}
        }
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Rapport enregistré dans : $cheminFinal'),
            backgroundColor: Colors.green.shade700,
            duration: const Duration(seconds: 5),
            action: isWindowsDesktop
                ? SnackBarAction(
                    label: 'Ouvrir',
                    textColor: Colors.white,
                    onPressed: () {
                      Process.run('explorer.exe', ['/select,', cheminFinal]);
                    },
                  )
                : null,
          ),
        );
      }
    } catch (e) {
      debugPrint('Erreur enregistrement PDF: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  /// Ouvre directement un fichier PDF avec l'application par défaut sous Windows
  static Future<void> ouvrirFichier(String filePath) async {
    if (kIsWeb) return;
    try {
      final file = File(filePath);
      if (!file.existsSync()) {
        debugPrint('ouvrirFichier: fichier introuvable: $filePath');
        return;
      }
      if (Platform.isWindows) {
        // Lancer directement via explorer.exe évite que les '&' soient interprétés par cmd.exe
        await Process.run('explorer.exe', [filePath]);
      } else {
        final uri = Uri.file(filePath);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
        }
      }
    } catch (e) {
      debugPrint('Erreur ouverture fichier: $e');
    }
  }

  /// Ouvre l'Explorateur Windows en sélectionnant le fichier indiqué
  static Future<void> selectionnerDansExplorateur(String filePath) async {
    if (kIsWeb || !Platform.isWindows) return;
    try {
      await Process.run('explorer.exe', ['/select,', filePath]);
    } catch (e) {
      debugPrint('Erreur explorer /select: $e');
    }
  }

  /// Enregistre automatiquement les octets du PDF sur le disque dur Windows :
  /// 1. Dans le sous-dossier de la commande : `Pictures\$numDossier\Rapport_\$numRapport_\$client.pdf`
  /// 2. Dans le dossier central des rapports : `Documents\Rapports_Rayco\...`
  static Future<String?> sauvegarderRapportPdfSurDisque({
    required Map<String, dynamic> intervention,
    required Uint8List pdfBytes,
    required String Function(Map<String, dynamic>) getNumeroDossier,
    required Directory? Function(String) getDossierPhotos,
  }) async {
    if (kIsWeb) return null;
    try {
      final numRapport = intervention['numero_rapport'] ?? 'Rapport';
      final cleanNumRapport = numRapport.toString().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final cleanClient = (intervention['nom_client'] ?? 'Client')
          .toString()
          .trim()
          .replaceAll('&', 'et')
          .replaceAll(RegExp(r'[\\/:*?"<>| ]'), '_');
      final fileName = 'Rapport_${cleanNumRapport}_$cleanClient.pdf';

      final numDossier = getNumeroDossier(intervention);
      final dossierPhotos = getDossierPhotos(numDossier);

      String? cheminPrincipal;
      if (dossierPhotos != null) {
        if (!await dossierPhotos.exists()) {
          await dossierPhotos.create(recursive: true);
        }
        final f = File('${dossierPhotos.path}\\$fileName');
        await f.writeAsBytes(pdfBytes);
        cheminPrincipal = f.path;
      }

      // Sauvegarde miroir dans Documents\Rapports_Rayco pour classement général
      if (Platform.isWindows) {
        try {
          final userProfile = Platform.environment['USERPROFILE'] ?? 'C:\\Users\\Default';
          final dirDocs = Directory('$userProfile\\Documents\\Rapports_Rayco');
          if (!await dirDocs.exists()) {
            await dirDocs.create(recursive: true);
          }
          final fDocs = File('${dirDocs.path}\\$fileName');
          await fDocs.writeAsBytes(pdfBytes);
          cheminPrincipal ??= fDocs.path;
        } catch (_) {}
      }

      return cheminPrincipal;
    } catch (e) {
      debugPrint('Erreur sauvegarde automatique PDF: $e');
      return null;
    }
  }

  /// Génère le PDF et le sauvegarde automatiquement sur Windows
  static Future<String?> genererEtSauvegarderAutomatiquement({
    required Map<String, dynamic> intervention,
    required String Function(Map<String, dynamic>) getNumeroDossier,
    required Directory? Function(String) getDossierPhotos,
    required String Function(int) formatSeconds,
    required String Function(dynamic) formatHeure,
  }) async {
    try {
      final pdfBytes = await genererBytesPdf(
        intervention,
        formatSeconds: formatSeconds,
        formatHeure: formatHeure,
      );
      return await sauvegarderRapportPdfSurDisque(
        intervention: intervention,
        pdfBytes: pdfBytes,
        getNumeroDossier: getNumeroDossier,
        getDossierPhotos: getDossierPhotos,
      );
    } catch (e) {
      debugPrint('Erreur genererEtSauvegarderAutomatiquement: $e');
      return null;
    }
  }

  /// Option 2 : Générer le PDF et ouvrir Outlook avec le document joint
  static Future<void> envoyerParOutlook(
    BuildContext context,
    Map<String, dynamic> intervention, {
    required String Function(Map<String, dynamic>) getNumeroDossier,
    required Directory? Function(String) getDossierPhotos,
    required String Function(int) formatSeconds,
    required String Function(dynamic) formatHeure,
    required bool isWindowsDesktop,
  }) async {
    try {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⏳ Préparation du PDF et d\'Outlook...'),
            duration: Duration(seconds: 1),
          ),
        );
      }

      final pdfBytes = await genererBytesPdf(
        intervention,
        formatSeconds: formatSeconds,
        formatHeure: formatHeure,
      );

      final numRapport = intervention['numero_rapport'] ?? 'Rapport';
      final clientName = intervention['nom_client'] ?? 'Client';
      final clientEmail = (intervention['courriel'] ?? '').toString().trim();
      final numCommande = intervention['numero_commande'] ?? '--';
      final dateChantier = intervention['date_chantier'] ?? '';
      final technicien = intervention['nom_technicien'] ?? '';
      final machine = '${intervention['type_machine'] ?? ''} ${intervention['marque'] ?? ''} ${intervention['modele'] ?? ''}'.trim();

      final bonCommande = intervention['numero_bon_commande'] ?? '--';
      final systeme = intervention['systeme_wylie'] ?? 'Rayco Wylie i4500 RCI';
      final camion = intervention['numero_camion'] ?? 'Camion #101';

      final subject = 'Rapport d\'intervention officiel RaycoWylie Nº $numRapport - $clientName';
      final body = '''Bonjour,

Veuillez trouver ci-joint le rapport d'intervention technique officiel Nº $numRapport attestant des travaux réalisés pour $clientName.

RÉCAPITULATIF DE L'INTERVENTION :
• Nº de Rapport : $numRapport
• Date de chantier : $dateChantier
• Bon de commande (P.O.) : $bonCommande
• Nº Commande interne : $numCommande
• Technicien : $technicien ($camion)
• Équipement : $machine
• Système de sécurité : $systeme
• Statut : Travaux terminés, testés et validés conforme

Restant à votre entière disposition pour tout renseignement supplémentaire.

Cordialement,

$technicien
Service Technique & Après-Vente
RAYCO WYLIE SYSTEMS
Systèmes Électroniques Rayco Ltée
2440, rue Dalton, Sainte-Foy (Québec) G1P 3X1 Canada
Tél : (418) 266-6600 • Sans frais : 1-888-252-1954
Courriel : service@raycowylie.com • Web : www.raycowylie.com''';

      // Sur Windows Desktop : Enregistrer le PDF et lancer OUTLOOK.EXE avec la pièce jointe
      if (isWindowsDesktop) {
        final numDossier = getNumeroDossier(intervention);
        final targetDir = getDossierPhotos(numDossier) ?? Directory.systemTemp;
        if (!await targetDir.exists()) {
          await targetDir.create(recursive: true);
        }

        final cleanNumRapport = numRapport.toString().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
        final pdfPath = '${targetDir.path}\\Rapport_$cleanNumRapport.pdf';
        final pdfFile = File(pdfPath);
        await pdfFile.writeAsBytes(pdfBytes);

        final outlookPath = trouverOutlookPath();
        if (outlookPath != null) {
          // Lancement d'Outlook avec le document en pièce jointe (/a) et le message pré-rempli (/m)
          final mailtoArg = clientEmail.isNotEmpty
              ? '$clientEmail?subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}'
              : '?subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}';

          await Process.start(
            outlookPath,
            [
              '/c',
              'ipm.note',
              '/a',
              pdfFile.path,
              '/m',
              mailtoArg,
            ],
            runInShell: true,
          );

          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('✉️ Outlook ouvert avec le rapport Nº $numRapport joint !'),
                backgroundColor: Colors.indigo,
                duration: const Duration(seconds: 4),
              ),
            );
          }
          return;
        }
      }

      // Fallback si Outlook n'est pas trouvé ou sur navigateur Web :
      // On lance le client de messagerie par défaut (mailto)
      final emailUri = Uri(
        scheme: 'mailto',
        path: clientEmail,
        query: 'subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}',
      );
      if (await canLaunchUrl(emailUri)) {
        await launchUrl(emailUri);
      }

      // Sur web, télécharger aussi le PDF pour que l'utilisateur puisse le glisser
      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: 'Rapport_$numRapport.pdf',
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✉️ Courriel préparé et rapport PDF téléchargé.'),
            backgroundColor: Colors.blueAccent,
          ),
        );
      }
    } catch (e) {
      debugPrint('Erreur envoi Outlook: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  /// Option 3 : Visualiser et imprimer le rapport via le lecteur PDF natif Windows ou Printing.layoutPdf
  static Future<void> imprimerApercuPdf(
    BuildContext context,
    Map<String, dynamic> intervention, {
    required String Function(int) formatSeconds,
    required String Function(dynamic) formatHeure,
    String Function(Map<String, dynamic>)? getNumeroDossier,
    Directory? Function(String)? getDossierPhotos,
  }) async {
    try {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⏳ Préparation du document pour visualisation...'), duration: Duration(seconds: 1)),
        );
      }
      final pdfBytes = await genererBytesPdf(
        intervention,
        formatSeconds: formatSeconds,
        formatHeure: formatHeure,
      );
      final numRapport = intervention['numero_rapport'] ?? 'intervention';

      if (!kIsWeb && Platform.isWindows) {
        final path = await sauvegarderRapportPdfSurDisque(
          intervention: intervention,
          pdfBytes: pdfBytes,
          getNumeroDossier: getNumeroDossier ?? ((i) => (i['numero_commande'] ?? 'CMD_${i['id']}').toString()),
          getDossierPhotos: getDossierPhotos ?? ((cmd) {
            final userProfile = Platform.environment['USERPROFILE'] ?? 'C:\\Users\\Default';
            return Directory('$userProfile\\Pictures\\$cmd');
          }),
        );
        if (path != null) {
          await ouvrirFichier(path);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('📄 Rapport ouvert dans votre lecteur PDF Windows :\n$path'),
                backgroundColor: Colors.teal.shade800,
                duration: const Duration(seconds: 5),
                action: SnackBarAction(
                  label: 'Dossier',
                  textColor: Colors.white,
                  onPressed: () => selectionnerDansExplorateur(path),
                ),
              ),
            );
          }
          return;
        }
      }

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdfBytes,
        name: 'Rapport_$numRapport.pdf',
      );
    } catch (e) {
      debugPrint('Erreur aperçu PDF: $e');
    }
  }

  /// Génère les octets (Uint8List) du PDF officiel complet RaycoWylie
  static Future<Uint8List> genererBytesPdf(
    Map<String, dynamic> intervention, {
    required String Function(int) formatSeconds,
    required String Function(dynamic) formatHeure,
  }) async {
    final pdf = pw.Document();

    // ─── POLICES DE CARACTÈRES ───
    pw.Font fontRegular = _cachedFontRegular ?? pw.Font.helvetica();
    pw.Font fontBold = _cachedFontBold ?? pw.Font.helveticaBold();
    pw.Font fontItalic = _cachedFontItalic ?? pw.Font.helveticaOblique();
    if (_cachedFontRegular == null || _cachedFontBold == null || _cachedFontItalic == null) {
      try {
        fontRegular = await PdfGoogleFonts.robotoRegular().timeout(const Duration(milliseconds: 1200));
        fontBold = await PdfGoogleFonts.robotoBold().timeout(const Duration(milliseconds: 1200));
        fontItalic = await PdfGoogleFonts.robotoItalic().timeout(const Duration(milliseconds: 1200));
        _cachedFontRegular = fontRegular;
        _cachedFontBold = fontBold;
        _cachedFontItalic = fontItalic;
      } catch (_) {
        fontRegular = pw.Font.helvetica();
        fontBold = pw.Font.helveticaBold();
        fontItalic = pw.Font.helveticaOblique();
      }
    }

    // ─── CHARGEMENT DU LOGO OFFICIEL RAYCOWYLIE ───
    String? logoSvgString;
    try {
      logoSvgString = await rootBundle.loadString('assets/images/RaycoWylie-Logo.svg');
    } catch (e) {
      debugPrint('Erreur chargement logo SVG bundle: $e');
      try {
        const fallbacksSvg = [
          'assets/images/RaycoWylie-Logo.svg',
          r'c:\Users\popatry\app_technicien\assets\images\RaycoWylie-Logo.svg',
          'build/web/assets/assets/images/RaycoWylie-Logo.svg',
          'data/flutter_assets/assets/images/RaycoWylie-Logo.svg',
        ];
        for (final p in fallbacksSvg) {
          final f = File(p);
          if (f.existsSync()) {
            logoSvgString = f.readAsStringSync();
            break;
          }
        }
      } catch (_) {}
    }

    // ─── PRÉPARATION DE LA SIGNATURE ───
    pw.MemoryImage? signatureImage;
    final signatureBase64 = intervention['signature'] as String?;
    if (signatureBase64 != null && signatureBase64.isNotEmpty) {
      try {
        signatureImage = pw.MemoryImage(base64Decode(signatureBase64));
      } catch (e) {
        debugPrint('Erreur chargement signature PDF: $e');
      }
    }

    // ─── DÉCODAGE DES PIÈCES UTILISÉES ───
    List<Map<String, dynamic>> pieces = [];
    try {
      final piecesJson = intervention['pieces_utilisees'];
      if (piecesJson is String && piecesJson.isNotEmpty) {
        final decoded = jsonDecode(piecesJson) as List;
        pieces = decoded.cast<Map<String, dynamic>>();
      } else if (piecesJson is List) {
        pieces = piecesJson.cast<Map<String, dynamic>>();
      }
    } catch (_) {}

    // ─── DÉCODAGE DES CONTRÔLES DE SÉCURITÉ & CONFORMITÉ COCHÉS ───
    final List<String> controlesSecurite = getControlesSecurite(intervention)
        .map((e) => assainirTextePdf(e))
        .toList();

    // ─── CHARGEMENT DES PHOTOS DU CHANTIER ───
    final List<pw.MemoryImage> photoImages = [];
    try {
      final photoPaths = getPhotosIntervention(intervention);
      for (final p in photoPaths.take(6)) {
        try {
          final file = File(p);
          if (await file.exists()) {
            final bytes = await file.readAsBytes();
            photoImages.add(pw.MemoryImage(bytes));
          } else {
            final xfile = XFile(p);
            final bytes = await xfile.readAsBytes();
            photoImages.add(pw.MemoryImage(bytes));
          }
        } catch (e) {
          debugPrint('Erreur lecture photo PDF ($p): $e');
        }
      }
    } catch (_) {}

    // ─── COULEURS OFFICIELLES RAYCOWYLIE ───
    const raycoRed = PdfColor.fromInt(0xFFD1001F);       // Rouge officiel RaycoWylie
    const raycoDarkRed = PdfColor.fromInt(0xFF8B0000);   // Bordeaux industriel
    const raycoBlack = PdfColor.fromInt(0xFF1E2124);     // Anthracite profond
    const raycoCharcoal = PdfColor.fromInt(0xFF2C3E50);  // Gris ardoise soutenu
    const raycoLightBg = PdfColor.fromInt(0xFFF8F9FA);   // Fond cartes / blocs
    const raycoSectionBg = PdfColor.fromInt(0xFFF1F3F5); // Fond en-têtes secondaires
    const raycoBorder = PdfColor.fromInt(0xFFDEE2E6);    // Bordure fine
    const raycoSuccess = PdfColor.fromInt(0xFF1B5E20);   // Vert validation
    const raycoSuccessBg = PdfColor.fromInt(0xFFE8F5E9); // Vert pâle
    const raycoGrey = PdfColor.fromInt(0xFF6C757D);      // Gris neutre moyen
    const white = PdfColors.white;

    final numRapport = assainirTextePdf(intervention['numero_rapport'] ?? 'RPT-${intervention['id'] ?? '001'}');
    final dateChantier = assainirTextePdf(intervention['date_chantier'] ?? DateTime.now().toString().substring(0, 10));
    final nomClient = assainirTextePdf(intervention['nom_client'] ?? 'Client Inconnu');
    final nomTechnicien = assainirTextePdf(intervention['nom_technicien'] ?? 'Patrick Popatry');
    final bonCommande = assainirTextePdf(intervention['numero_bon_commande'] ?? '--');
    final numCommande = assainirTextePdf(intervention['numero_commande'] ?? '--');
    final numReference = assainirTextePdf(intervention['numero_reference'] ?? '--');
    final systemeWylie = assainirTextePdf(intervention['systeme_wylie'] ?? 'Rayco Wylie i4500 RCI');
    final bool estApprouveSuperviseur = estRapportApprouve(intervention);
    final String nomSuperviseur = assainirTextePdf(getNomSuperviseur(intervention));
    final String dateApprobation = assainirTextePdf(getDateApprobationSuperviseur(intervention));

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.symmetric(horizontal: 26, vertical: 24),
        theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold, italic: fontItalic),
        header: (pw.Context ctx) {
          return pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 10),
            padding: const pw.EdgeInsets.only(bottom: 8),
            child: pw.Column(
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    // GAUCHE : LOGO OFFICIEL RAYCOWYLIE + COORDONNÉES
                    pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        if (logoSvgString != null && logoSvgString.isNotEmpty)
                          pw.Container(
                            width: 135,
                            height: 26,
                            child: pw.SvgImage(svg: logoSvgString, width: 135, height: 26),
                          )
                        else
                          pw.Container(
                            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            decoration: pw.BoxDecoration(
                              color: raycoRed,
                              borderRadius: pw.BorderRadius.circular(4),
                            ),
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text(
                                  'RAYCO WYLIE',
                                  style: pw.TextStyle(
                                    font: fontBold,
                                    fontSize: 14,
                                    color: white,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                                pw.Text(
                                  'SYSTEMS',
                                  style: pw.TextStyle(
                                    fontSize: 7.5,
                                    color: white,
                                    letterSpacing: 2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        pw.SizedBox(width: 10),
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              'RAYCO WYLIE SYSTEMS',
                              style: pw.TextStyle(
                                font: fontBold,
                                fontSize: 10,
                                color: raycoRed,
                                letterSpacing: 0.5,
                              ),
                            ),
                            pw.Text(
                              'Systèmes Électroniques Rayco Ltée',
                              style: pw.TextStyle(font: fontBold, fontSize: 7.5, color: raycoBlack),
                            ),
                            pw.Text(
                              '2440, rue Dalton, Sainte-Foy (Québec) G1P 3X1 Canada',
                              style: const pw.TextStyle(fontSize: 7, color: raycoGrey),
                            ),
                            pw.Text(
                              'Tél: (418) 266-6600 | Sans frais: 1-888-252-1954',
                              style: const pw.TextStyle(fontSize: 7, color: raycoGrey),
                            ),
                            pw.Text(
                              'Courriel: service@raycowylie.com | www.raycowylie.com',
                              style: const pw.TextStyle(fontSize: 7, color: raycoGrey),
                            ),
                          ],
                        ),
                      ],
                    ),

                    // DROITE : TITRE DU RAPPORT + NUMÉRO & DATE
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: pw.BoxDecoration(
                            color: raycoRed,
                            borderRadius: pw.BorderRadius.circular(3),
                          ),
                          child: pw.Text(
                            'RAPPORT DE SERVICE OFFICIEL',
                            style: pw.TextStyle(
                              font: fontBold,
                              fontSize: 9,
                              color: white,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        pw.SizedBox(height: 3),
                        pw.Text(
                          'RAPPORT Nº $numRapport',
                          style: pw.TextStyle(
                            font: fontBold,
                            fontSize: 13,
                            color: raycoBlack,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: pw.BoxDecoration(
                            color: estApprouveSuperviseur ? raycoSuccessBg : const PdfColor.fromInt(0xFFFFF3CD),
                            borderRadius: pw.BorderRadius.circular(3),
                            border: pw.Border.all(
                              color: estApprouveSuperviseur ? raycoSuccess : const PdfColor.fromInt(0xFFFFC107),
                              width: 0.5,
                            ),
                          ),
                          child: pw.Row(
                            mainAxisSize: pw.MainAxisSize.min,
                            children: [
                              pw.Container(
                                width: 4.5,
                                height: 4.5,
                                decoration: pw.BoxDecoration(
                                  color: estApprouveSuperviseur ? raycoSuccess : const PdfColor.fromInt(0xFFD39E00),
                                  shape: pw.BoxShape.circle,
                                ),
                              ),
                              pw.SizedBox(width: 3.5),
                              pw.Text(
                                estApprouveSuperviseur ? 'CLÔTURÉ & CONFORME' : 'EN ATTENTE APPROBATION',
                                style: pw.TextStyle(
                                  font: fontBold,
                                  fontSize: 7,
                                  color: estApprouveSuperviseur ? raycoSuccess : const PdfColor.fromInt(0xFF856404),
                                ),
                              ),
                            ],
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'Date chantier : $dateChantier',
                          style: const pw.TextStyle(fontSize: 7.5, color: raycoGrey),
                        ),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 6),
                // Liseré officiel RaycoWylie (barre rouge vive + filet anthracite)
                pw.Column(
                  children: [
                    pw.Container(height: 2.5, color: raycoRed),
                    pw.SizedBox(height: 1),
                    pw.Container(height: 0.8, color: raycoBlack),
                  ],
                ),
              ],
            ),
          );
        },
        footer: (pw.Context ctx) {
          return pw.Container(
            margin: const pw.EdgeInsets.only(top: 8),
            padding: const pw.EdgeInsets.only(top: 6),
            decoration: const pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(color: raycoRed, width: 1.5)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Rayco Wylie Systems | Qualité & Sécurité Industrielle depuis 1933 | www.raycowylie.com',
                  style: const pw.TextStyle(fontSize: 7.2, color: raycoGrey),
                ),
                pw.Text(
                  'Rapport Nº $numRapport | Page ${ctx.pageNumber} sur ${ctx.pagesCount}',
                  style: pw.TextStyle(fontSize: 7.2, font: fontBold, color: raycoBlack),
                ),
              ],
            ),
          );
        },
        build: (pw.Context ctx) => [
          // ─── 1. CLIENT, CHANTIER & BORDEREAU DE COMMANDE ──────────────
          _buildSectionHeader('1. CLIENT, LOCALISATION & RÉFÉRENCES ADMINISTRATIVES', tag: 'OFFICIEL'),
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              color: raycoLightBg,
              borderRadius: pw.BorderRadius.circular(5),
              border: pw.Border.all(color: raycoBorder),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Colonne Gauche : Client & Coordonnées
                pw.Expanded(
                  flex: 6,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Row(
                        children: [
                          pw.Container(
                            width: 6,
                            height: 6,
                            decoration: const pw.BoxDecoration(color: raycoRed, shape: pw.BoxShape.circle),
                          ),
                          pw.SizedBox(width: 5),
                          pw.Expanded(
                            child: pw.Text(
                              nomClient,
                              style: pw.TextStyle(font: fontBold, fontSize: 11, color: raycoBlack),
                            ),
                          ),
                        ],
                      ),
                      if (intervention['adresse_facturation'] != null &&
                          (intervention['adresse_facturation'] as String).trim().isNotEmpty) ...[
                        pw.SizedBox(height: 3),
                        pw.Text(
                          'Facturation : ${intervention['adresse_facturation']}',
                          style: pw.TextStyle(font: fontBold, fontSize: 8, color: raycoDarkRed),
                        ),
                      ],
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Chantier / Site : ${intervention['adresse_intervention'] ?? intervention['adresse'] ?? '--'}',
                        style: const pw.TextStyle(fontSize: 8, color: raycoCharcoal),
                      ),
                      if (intervention['nom_contact'] != null &&
                          (intervention['nom_contact'] as String).isNotEmpty) ...[
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'Contact sur place : ${intervention['nom_contact']} | Tél : ${intervention['telephone'] ?? '--'}',
                          style: const pw.TextStyle(fontSize: 7.8, color: raycoGrey),
                        ),
                        if (intervention['courriel'] != null &&
                            (intervention['courriel'] as String).isNotEmpty)
                          pw.Text(
                            'Courriel : ${intervention['courriel']}',
                            style: const pw.TextStyle(fontSize: 7.8, color: raycoGrey),
                          ),
                      ],
                    ],
                  ),
                ),
                pw.SizedBox(width: 10),
                // Colonne Droite : Références administratives
                pw.Expanded(
                  flex: 4,
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(6),
                    decoration: pw.BoxDecoration(
                      color: white,
                      borderRadius: pw.BorderRadius.circular(4),
                      border: pw.Border.all(color: raycoBorder),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        _buildPdfRow('Bon commande (P.O.)', bonCommande, fontBold, highlight: bonCommande != '--'),
                        _buildPdfRow('Nº Commande', numCommande, fontBold),
                        _buildPdfRow('Nº Référence', numReference, fontBold),
                        _buildPdfRow('Technicien', nomTechnicien, fontBold),
                        _buildPdfRow('Priorité', intervention['priorite'] ?? 'Normale', fontBold),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 8),

          // ─── 2. ENGIN DE LEVAGE & SYSTÈME RAYCOWYLIE ──────────────────
          _buildSectionHeader('2. ÉQUIPEMENT DE LEVAGE & SYSTÈME DE SÉCURITÉ RAYCOWYLIE', tag: 'TECHNIQUE'),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Machine
              pw.Expanded(
                child: pw.Container(
                  decoration: pw.BoxDecoration(
                    color: white,
                    borderRadius: pw.BorderRadius.circular(5),
                    border: pw.Border.all(color: raycoBorder),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Container(
                        width: double.infinity,
                        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                        decoration: const pw.BoxDecoration(
                          color: raycoDarkRed,
                          borderRadius: pw.BorderRadius.vertical(top: pw.Radius.circular(4)),
                        ),
                        child: pw.Text(
                          'ENGIN DE CHANTIER / GRUE',
                          style: pw.TextStyle(font: fontBold, fontSize: 8, color: white),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(7),
                        child: pw.Column(
                          children: [
                            _buildPdfRow('Intervention', intervention['type_intervention'] ?? 'Service & Maintenance', fontBold),
                            _buildPdfRow('Catégorie', intervention['type_machine'] ?? 'Grue mobile télescopique', fontBold),
                            _buildPdfRow('Marque / Modèle', '${intervention['marque'] ?? ''} ${intervention['modele'] ?? ''}'.trim().isNotEmpty ? '${intervention['marque'] ?? ''} ${intervention['modele'] ?? ''}'.trim() : '--', fontBold),
                            _buildPdfRow('Année', intervention['annee']?.toString() ?? '--', fontBold),
                            _buildPdfRow('Nº Série machine', intervention['numero_serie_machine'] ?? '--', fontBold),
                            if (intervention['numero_unite'] != null && intervention['numero_unite'].toString().trim().isNotEmpty)
                              _buildPdfRow('Nº Unité', intervention['numero_unite'].toString().trim(), fontBold),
                            _buildPdfRow('Alimentation', intervention['alimentation'] ?? '24 VDC', fontBold),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(width: 8),
              // Système RaycoWylie
              pw.Expanded(
                child: pw.Container(
                  decoration: pw.BoxDecoration(
                    color: white,
                    borderRadius: pw.BorderRadius.circular(5),
                    border: pw.Border.all(color: raycoBorder),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Container(
                        width: double.infinity,
                        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                        decoration: const pw.BoxDecoration(
                          color: raycoBlack,
                          borderRadius: pw.BorderRadius.vertical(top: pw.Radius.circular(4)),
                        ),
                        child: pw.Text(
                          'SYSTÈME ÉLECTRONIQUE RAYCOWYLIE',
                          style: pw.TextStyle(font: fontBold, fontSize: 8, color: white),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(7),
                        child: pw.Column(
                          children: [
                            _buildPdfRow('Indicateur / RCI', systemeWylie, fontBold, highlight: true),
                            _buildPdfRow('Nº Série système', intervention['numero_serie_systeme'] ?? '--', fontBold),
                            _buildPdfRow('Version firmware', intervention['version_logiciel'] ?? 'v3.4.2 CAN', fontBold),
                            _buildPdfRow('Engrenage / Rot.', intervention['engrenage'] ?? '--', fontBold),
                            _buildPdfRow('Position bypass', intervention['position_bypass'] ?? 'Normal (Actif)', fontBold),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 8),

          // ─── 3. BILAN HORODATAGE & TEMPS FACTURABLES ─────────────────
          _buildSectionHeader('3. HORODATAGE DÉTAILLÉ & SOMMAIRE DES TEMPS DE SERVICE', tag: 'PAIE & FACTURATION'),
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: raycoBorder),
              color: raycoLightBg,
              borderRadius: pw.BorderRadius.circular(5),
            ),
            child: pw.Column(
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    _buildMetricCard(
                      'Déplacement (Aller)',
                      intervention['duree_trajet'] ?? '--',
                      detail: intervention['distance_km'] != null ? '${intervention['distance_km']}' : null,
                      fontBold: fontBold,
                      borderColor: raycoBorder,
                      accentColor: raycoCharcoal,
                    ),
                    _buildMetricCard(
                      'Travaux & Rapport',
                      intervention['duree_chantier'] ?? '--',
                      detail: 'Chantier + rédaction',
                      fontBold: fontBold,
                      borderColor: raycoBorder,
                      accentColor: raycoCharcoal,
                    ),
                    _buildMetricCard(
                      'Déplacement (Retour)',
                      intervention['duree_retour'] ?? intervention['duree_trajet'] ?? '--',
                      detail: intervention['distance_retour_km'] != null ? '${intervention['distance_retour_km']}' : (intervention['distance_km'] != null ? '${intervention['distance_km']}' : 'Estimé = aller'),
                      fontBold: fontBold,
                      borderColor: raycoBorder,
                      accentColor: raycoCharcoal,
                    ),
                    if (intervention['duree_pause_chantier_secondes'] != null &&
                        (intervention['duree_pause_chantier_secondes'] as int) > 0)
                      _buildMetricCard(
                        'Pause dîner / arrêt',
                        formatSeconds(intervention['duree_pause_chantier_secondes'] as int),
                        detail: 'Déduite de paie',
                        fontBold: fontBold,
                        borderColor: raycoBorder,
                        accentColor: raycoGrey,
                      ),
                    // KILOMÉTRAGE TOTAL (ALLER + RETOUR)
                    _buildMetricCard(
                      'DISTANCE TOTALE',
                      _calculerKilometrageTotal(intervention),
                      detail: 'Aller + Retour',
                      fontBold: fontBold,
                      borderColor: raycoBorder,
                      accentColor: raycoCharcoal,
                    ),
                    // TOTAL FACTURABLE EN ROUGE RAYCOWYLIE
                    _buildMetricCard(
                      'TOTAL FACTURABLE',
                      _calculerTotalFacturable(intervention),
                      detail: 'Aller + Chantier + Retour',
                      fontBold: fontBold,
                      isHighlighted: true,
                      bgColor: raycoRed,
                      textColor: white,
                    ),
                  ],
                ),
                pw.SizedBox(height: 5),
                pw.Text(
                  '* Conformément aux politiques de service RaycoWylie, le temps facturable inclut le trajet aller, le diagnostic/travaux, la rédaction du rapport et le déplacement retour estimé.',
                  style: const pw.TextStyle(fontSize: 6.8, color: raycoGrey),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 8),

          // ─── 4. DIAGNOSTIC & TRAVAUX RÉALISÉS ─────────────────────────
          _buildSectionHeader('4. DIAGNOSTIC TECHNIQUE & TRAVAUX RÉALISÉS', tag: 'RAPPORT TECHNIQUE'),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: raycoBorder),
              color: white,
              borderRadius: pw.BorderRadius.circular(5),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Trouble initial signalé
                if (intervention['trouble'] != null &&
                    (intervention['trouble'] as String).trim().isNotEmpty) ...[
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.all(6),
                    decoration: const pw.BoxDecoration(
                      color: PdfColor.fromInt(0xFFFFF3CD),
                      border: pw.Border(left: pw.BorderSide(color: raycoRed, width: 3)),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'PROBLÈME INITIAL SIGNALÉ PAR LE CLIENT :',
                          style: pw.TextStyle(font: fontBold, fontSize: 7.5, color: raycoDarkRed),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          assainirTextePdf(intervention['trouble'].toString()),
                          style: const pw.TextStyle(fontSize: 8.2, color: raycoBlack),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 6),
                ],

                pw.Text(
                  'DESCRIPTION DES TRAVAUX EXÉCUTÉS & NOTES DE SERVICE :',
                  style: pw.TextStyle(font: fontBold, fontSize: 8, color: raycoBlack),
                ),
                pw.SizedBox(height: 4),
                pw.Container(
                  constraints: const pw.BoxConstraints(minHeight: 120),
                  child: pw.Text(
                    assainirTextePdf(
                      getNotesDeService(intervention).isNotEmpty
                          ? getNotesDeService(intervention)
                          : 'Intervention terminée avec succès. Système inspecté, calibré et validé conforme aux abaques de charge du manufacturier.',
                    ),
                    style: const pw.TextStyle(fontSize: 8.5, height: 1.4, color: raycoBlack),
                  ),
                ),
              ],
            ),
          ),

          // ─── SAUT EXPLICITE VERS LA PAGE 2 POUR ASSURER 2 PAGES PLEINES ───
          pw.NewPage(),

          // ─── 5. CONTRÔLES DE SÉCURITÉ & CONFORMITÉ RAYCOWYLIE ──────────
          _buildSectionHeader(
            '5. CONTRÔLES DE SÉCURITÉ & CONFORMITÉ RAYCOWYLIE',
            tag: '${controlesSecurite.length} / ${kControlesSecuriteStandards.length} VALIDÉS',
          ),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: raycoBorder),
              color: raycoLightBg,
              borderRadius: pw.BorderRadius.circular(5),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'PROTOCOLE DE SÉCURITÉ, D\'INSPECTION ET DE CALIBRATION VALIDÉ :',
                  style: pw.TextStyle(font: fontBold, fontSize: 7.5, color: raycoCharcoal),
                ),
                pw.SizedBox(height: 5),
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: kControlesSecuriteStandards.take(4).map((c) {
                          final cClean = assainirTextePdf(c);
                          final cNorm = cClean.trim().toLowerCase();
                          final isChecked = controlesSecurite.any((item) {
                            final iNorm = assainirTextePdf(item).trim().toLowerCase();
                            return iNorm == cNorm || item.trim().toLowerCase() == c.trim().toLowerCase();
                          });
                          return pw.Padding(
                            padding: const pw.EdgeInsets.only(bottom: 3.5),
                            child: _buildCheckItem(cClean, fontBold, isChecked: isChecked),
                          );
                        }).toList(),
                      ),
                    ),
                    pw.SizedBox(width: 8),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: kControlesSecuriteStandards.skip(4).map((c) {
                          final cClean = assainirTextePdf(c);
                          final cNorm = cClean.trim().toLowerCase();
                          final isChecked = controlesSecurite.any((item) {
                            final iNorm = assainirTextePdf(item).trim().toLowerCase();
                            return iNorm == cNorm || item.trim().toLowerCase() == c.trim().toLowerCase();
                          });
                          return pw.Padding(
                            padding: const pw.EdgeInsets.only(bottom: 3.5),
                            child: _buildCheckItem(cClean, fontBold, isChecked: isChecked),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 8),

          // ─── 6. PIÈCES & COMPOSANTES DE RECHANGE ───────────────────────
          _buildSectionHeader('6. PIÈCES & COMPOSANTES DE RECHANGE', tag: pieces.isNotEmpty ? '${pieces.length} RÉF.' : '0 PIÈCE'),
          if (pieces.isNotEmpty) ...[
            pw.Container(
              width: double.infinity,
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: raycoBorder),
                borderRadius: pw.BorderRadius.circular(5),
              ),
              child: pw.Column(
                children: [
                  pw.TableHelper.fromTextArray(
                    border: null,
                    headerStyle: pw.TextStyle(font: fontBold, fontSize: 8, color: white),
                    headerDecoration: const pw.BoxDecoration(color: raycoRed),
                    cellHeight: 16,
                    cellStyle: const pw.TextStyle(fontSize: 8),
                    headers: ['RÉFÉRENCE RAYCO', 'DESCRIPTION DE LA COMPOSANTE', 'QTÉ', 'UNITÉ', 'STATUT'],
                    data: pieces.map((p) => [
                      p['ref']?.toString() ?? '--',
                      assainirTextePdf(p['nom']?.toString() ?? '--'),
                      p['utilise']?.toString() ?? '1',
                      p['unite']?.toString() ?? 'EA',
                      'Installé & certifié',
                    ]).toList(),
                  ),
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    color: raycoSectionBg,
                    child: pw.Text(
                      'Total : ${pieces.length} référence(s) de pièces installée(s) et validée(s) sur l\'équipement.',
                      style: pw.TextStyle(fontSize: 7.2, font: fontBold, color: raycoCharcoal),
                      textAlign: pw.TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(7),
              decoration: pw.BoxDecoration(
                color: raycoLightBg,
                borderRadius: pw.BorderRadius.circular(4),
                border: pw.Border.all(color: raycoBorder),
              ),
              child: pw.Text(
                'Aucune pièce de rechange requise pour cette intervention. Uniquement diagnostic, main-d\'oeuvre et étalonnage technique.',
                style: const pw.TextStyle(fontSize: 7.5, color: raycoGrey, fontStyle: pw.FontStyle.italic),
              ),
            ),
          ],
          pw.SizedBox(height: 8),

          // ─── 7. ATTESTATION DE CONFORMITÉ, SIGNATURE CLIENT & APPROBATION SUPERVISEUR ───
          _buildSectionHeader(
            '7. ATTESTATION DE CONFORMITÉ, SIGNATURE CLIENT & APPROBATION SUPERVISEUR',
            tag: estApprouveSuperviseur ? 'CERTIFIÉ CONFORME' : 'EN ATTENTE APPROBATION',
          ),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(7),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: raycoBorder),
              color: raycoLightBg,
              borderRadius: pw.BorderRadius.circular(5),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'ATTESTATION OFFICIELLE DE SERVICE RAYCOWYLIE :',
                  style: pw.TextStyle(font: fontBold, fontSize: 7.8, color: raycoBlack),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'Le soussigné confirme que les travaux d\'inspection, de réparation ou de calibration décrits ci-dessus ont été exécutés conformément aux normes de sécurité RaycoWylie Systems. L\'équipement a été vérifié et remis en service opérationnel.',
                  style: const pw.TextStyle(fontSize: 7.2, color: raycoCharcoal),
                ),
                pw.SizedBox(height: 6),
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    // Colonne 1 : Validation Technicien RaycoWylie
                    pw.Expanded(
                      flex: 3,
                      child: pw.Container(
                        padding: const pw.EdgeInsets.all(6),
                        decoration: pw.BoxDecoration(
                          color: white,
                          border: pw.Border.all(color: raycoBorder),
                          borderRadius: pw.BorderRadius.circular(4),
                        ),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('POUR : RAYCO WYLIE',
                                style: pw.TextStyle(font: fontBold, fontSize: 7.2, color: raycoRed)),
                            pw.SizedBox(height: 3),
                            pw.Text('Tech : $nomTechnicien', style: pw.TextStyle(font: fontBold, fontSize: 7.5)),
                            pw.Text('Date : $dateChantier', style: const pw.TextStyle(fontSize: 7, color: raycoGrey)),
                            pw.SizedBox(height: 6),
                            pw.Container(
                              padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                              decoration: pw.BoxDecoration(
                                color: estApprouveSuperviseur ? raycoSuccessBg : const PdfColor.fromInt(0xFFFFF3CD),
                                borderRadius: pw.BorderRadius.circular(3),
                                border: pw.Border.all(
                                  color: estApprouveSuperviseur ? raycoSuccess : const PdfColor.fromInt(0xFFFFC107),
                                  width: 0.5,
                                ),
                              ),
                              child: pw.Row(
                                mainAxisSize: pw.MainAxisSize.min,
                                children: [
                                  pw.Container(
                                    width: 4.5,
                                    height: 4.5,
                                    decoration: pw.BoxDecoration(
                                      color: estApprouveSuperviseur ? raycoSuccess : const PdfColor.fromInt(0xFFD39E00),
                                      shape: pw.BoxShape.circle,
                                    ),
                                  ),
                                  pw.SizedBox(width: 3),
                                  pw.Text(
                                    estApprouveSuperviseur ? 'TRAVAUX VALIDÉS' : 'TRAVAUX SOUMIS',
                                    style: pw.TextStyle(
                                      font: fontBold,
                                      fontSize: 6.5,
                                      color: estApprouveSuperviseur ? raycoSuccess : const PdfColor.fromInt(0xFF856404),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    pw.SizedBox(width: 6),

                    // Colonne 2 : Signature Client
                    pw.Expanded(
                      flex: 4,
                      child: pw.Container(
                        padding: const pw.EdgeInsets.all(6),
                        decoration: pw.BoxDecoration(
                          color: white,
                          border: pw.Border.all(color: raycoBorder),
                          borderRadius: pw.BorderRadius.circular(4),
                        ),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('POUR LE CLIENT : $nomClient',
                                style: pw.TextStyle(font: fontBold, fontSize: 7.2, color: raycoBlack)),
                            pw.SizedBox(height: 2),
                            pw.Text('Signataire : ${intervention['nom_contact'] ?? nomClient}',
                                style: pw.TextStyle(font: fontBold, fontSize: 7.5)),
                            pw.Text(
                              'Date : ${intervention['heure_signature'] != null ? intervention['heure_signature'].toString().substring(0, 16).replaceAll('T', ' ') : dateChantier}',
                              style: const pw.TextStyle(fontSize: 6.8, color: raycoGrey),
                            ),
                            pw.SizedBox(height: 3),
                            pw.Container(
                              height: 46,
                              width: double.infinity,
                              decoration: pw.BoxDecoration(
                                color: white,
                                border: pw.Border.all(color: raycoBorder),
                                borderRadius: pw.BorderRadius.circular(3),
                              ),
                              child: signatureImage != null
                                  ? pw.Padding(
                                      padding: const pw.EdgeInsets.all(2),
                                      child: pw.Image(signatureImage, fit: pw.BoxFit.contain),
                                    )
                                  : pw.Center(
                                      child: pw.Text(
                                        intervention['signature_a_distance_demandee'] == true
                                            ? 'En attente de signature à distance'
                                            : 'Signature électronique enregistrée',
                                        style: const pw.TextStyle(fontSize: 6.5, color: raycoGrey),
                                      ),
                                    ),
                            ),
                            pw.SizedBox(height: 2),
                            pw.Text(
                              intervention['nom_signataire_distant'] != null &&
                                      intervention['nom_signataire_distant'].toString().trim().isNotEmpty
                                  ? 'Signé par : ${assainirTextePdf(intervention['nom_signataire_distant'])}'
                                  : 'Signature autorisée du client',
                              style: const pw.TextStyle(fontSize: 6.2, color: raycoGrey),
                            ),
                          ],
                        ),
                      ),
                    ),
                    pw.SizedBox(width: 6),

                    // Colonne 3 : TAMPON D'APPROBATION DU SUPERVISEUR
                    pw.Expanded(
                      flex: 3,
                      child: pw.Container(
                        padding: const pw.EdgeInsets.all(6),
                        decoration: pw.BoxDecoration(
                          color: estApprouveSuperviseur ? const PdfColor.fromInt(0xFFFFF5F5) : white,
                          border: pw.Border.all(
                            color: estApprouveSuperviseur ? raycoRed : raycoBorder,
                            width: estApprouveSuperviseur ? 1.2 : 1,
                          ),
                          borderRadius: pw.BorderRadius.circular(4),
                        ),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.center,
                          children: [
                            pw.Text(
                              'TAMPON DU SUPERVISEUR',
                              style: pw.TextStyle(
                                font: fontBold,
                                fontSize: 7,
                                color: estApprouveSuperviseur ? raycoRed : raycoCharcoal,
                              ),
                              textAlign: pw.TextAlign.center,
                            ),
                            pw.SizedBox(height: 3),
                            if (estApprouveSuperviseur) ...[
                              pw.Container(
                                width: double.infinity,
                                padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                                decoration: pw.BoxDecoration(
                                  border: pw.Border.all(color: raycoRed, width: 1.2),
                                  borderRadius: pw.BorderRadius.circular(3),
                                  color: const PdfColor.fromInt(0xFFFFF0F0),
                                ),
                                child: pw.Column(
                                  children: [
                                    pw.Row(
                                      mainAxisAlignment: pw.MainAxisAlignment.center,
                                      children: [
                                        pw.Container(width: 8, height: 1.2, color: raycoRed),
                                        pw.SizedBox(width: 4),
                                        pw.Text(
                                          'APPROUVÉ',
                                          style: pw.TextStyle(font: fontBold, fontSize: 8.0, color: raycoRed, letterSpacing: 0.8),
                                        ),
                                        pw.SizedBox(width: 4),
                                        pw.Container(width: 8, height: 1.2, color: raycoRed),
                                      ],
                                    ),
                                    pw.Text(
                                      'CONFORME & DÉCLARÉ',
                                      style: pw.TextStyle(font: fontBold, fontSize: 6.2, color: raycoDarkRed),
                                    ),
                                    pw.SizedBox(height: 1.5),
                                    pw.Text(
                                      'Par : $nomSuperviseur',
                                      style: pw.TextStyle(font: fontBold, fontSize: 6.5, color: raycoBlack),
                                      maxLines: 1,
                                      overflow: pw.TextOverflow.clip,
                                    ),
                                    pw.Text(
                                      dateApprobation,
                                      style: const pw.TextStyle(fontSize: 6, color: raycoGrey),
                                      maxLines: 1,
                                    ),
                                    pw.SizedBox(height: 2),
                                    pw.Container(
                                      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                                      decoration: pw.BoxDecoration(
                                        color: raycoSuccessBg,
                                        borderRadius: pw.BorderRadius.circular(2),
                                        border: pw.Border.all(color: raycoSuccess, width: 0.4),
                                      ),
                                      child: pw.Text(
                                        'CHECKLIST VALIDÉE - PIÈCES DÉDUITES',
                                        style: pw.TextStyle(font: fontBold, fontSize: 5.5, color: raycoSuccess),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ] else ...[
                              pw.Container(
                                height: 50,
                                width: double.infinity,
                                alignment: pw.Alignment.center,
                                decoration: pw.BoxDecoration(
                                  border: pw.Border.all(
                                    color: const PdfColor.fromInt(0xFFFFC107),
                                    width: 0.8,
                                    style: pw.BorderStyle.dashed,
                                  ),
                                  borderRadius: pw.BorderRadius.circular(3),
                                  color: const PdfColor.fromInt(0xFFFFFDF5),
                                ),
                                padding: const pw.EdgeInsets.all(3),
                                child: pw.Column(
                                  mainAxisAlignment: pw.MainAxisAlignment.center,
                                  children: [
                                    pw.Text(
                                      'EN ATTENTE D\'APPROBATION',
                                      style: pw.TextStyle(
                                        font: fontBold,
                                        fontSize: 6.5,
                                        color: const PdfColor.fromInt(0xFFB78103),
                                      ),
                                      textAlign: pw.TextAlign.center,
                                    ),
                                    pw.SizedBox(height: 2),
                                    pw.Text(
                                      'Tampon requis pour conformité & déduction pièces',
                                      style: const pw.TextStyle(fontSize: 5.5, color: raycoGrey),
                                      textAlign: pw.TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 8),

          // ─── 8. PHOTOS DU CHANTIER (DÉPLACÉES EN TOUTE FIN DE RAPPORT) ───
          if (photoImages.isNotEmpty) ...[
            _buildSectionHeader('8. REGISTRE PHOTOGRAPHIQUE DU CHANTIER (${photoImages.length} PHOTOS)', tag: 'PHOTOS'),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: raycoBorder),
                borderRadius: pw.BorderRadius.circular(5),
                color: white,
              ),
              child: pw.Wrap(
                spacing: 10,
                runSpacing: 8,
                children: List.generate(photoImages.length, (i) {
                  return pw.Container(
                    width: 170,
                    height: 105,
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: raycoRed, width: 1),
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.ClipRRect(
                      horizontalRadius: 3,
                      verticalRadius: 3,
                      child: pw.Image(photoImages[i], fit: pw.BoxFit.cover),
                    ),
                  );
                }),
              ),
            ),
            pw.SizedBox(height: 8),
          ],
        ],
      ),
    );

    return pdf.save();
  }

  // ─── WIDGETS D'AIDE MISE EN PAGE PDF ───

  static pw.Widget _buildSectionHeader(String title, {String? tag}) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 6, bottom: 4),
      padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: const pw.BoxDecoration(
        color: PdfColor.fromInt(0xFFF1F3F5),
        border: pw.Border(
          left: pw.BorderSide(color: PdfColor.fromInt(0xFFD1001F), width: 3.5),
          bottom: pw.BorderSide(color: PdfColor.fromInt(0xFFDEE2E6), width: 0.6),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: pw.FontWeight.bold,
              color: const PdfColor.fromInt(0xFF1E2124),
              letterSpacing: 0.4,
            ),
          ),
          if (tag != null)
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: pw.BoxDecoration(
                color: const PdfColor.fromInt(0xFFD1001F),
                borderRadius: pw.BorderRadius.circular(2),
              ),
              child: pw.Text(
                tag,
                style: const pw.TextStyle(
                  fontSize: 6.5,
                  color: PdfColors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }

  static pw.Widget _buildPdfRow(String label, String value, pw.Font fontBold, {bool highlight = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 82,
            child: pw.Text(
              '$label :',
              style: const pw.TextStyle(fontSize: 7.5, color: PdfColor.fromInt(0xFF6C757D)),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(
                font: fontBold,
                fontSize: 8,
                color: highlight ? const PdfColor.fromInt(0xFFD1001F) : const PdfColor.fromInt(0xFF1E2124),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildCheckItem(String text, pw.Font fontBold, {bool isChecked = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Container(
            width: 8.5,
            height: 8.5,
            decoration: pw.BoxDecoration(
              color: isChecked ? const PdfColor.fromInt(0xFFE8F5E9) : PdfColors.white,
              borderRadius: pw.BorderRadius.circular(1.5),
              border: pw.Border.all(
                color: isChecked ? const PdfColor.fromInt(0xFF1B5E20) : const PdfColor.fromInt(0xFF9E9E9E),
                width: isChecked ? 0.9 : 0.7,
              ),
            ),
            child: isChecked
                ? pw.CustomPaint(
                    size: const PdfPoint(8.5, 8.5),
                    painter: (canvas, size) {
                      canvas
                        ..setColor(const PdfColor.fromInt(0xFF1B5E20))
                        ..setLineWidth(1.1)
                        ..moveTo(1.8, 4.5)
                        ..lineTo(3.6, 2.0)
                        ..lineTo(6.8, 6.5)
                        ..strokePath();
                    },
                  )
                : null,
          ),
          pw.SizedBox(width: 4.5),
          pw.Expanded(
            child: pw.Text(
              text,
              style: pw.TextStyle(
                fontSize: 7.0,
                color: isChecked ? const PdfColor.fromInt(0xFF2C3E50) : const PdfColor.fromInt(0xFF757575),
                font: isChecked ? fontBold : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildMetricCard(
    String label,
    String value, {
    String? detail,
    required pw.Font fontBold,
    PdfColor? borderColor,
    PdfColor? accentColor,
    PdfColor? bgColor,
    PdfColor? textColor,
    bool isHighlighted = false,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: pw.BoxDecoration(
        color: bgColor ?? PdfColors.white,
        borderRadius: pw.BorderRadius.circular(4),
        border: pw.Border.all(color: borderColor ?? const PdfColor.fromInt(0xFFDEE2E6), width: isHighlighted ? 1.2 : 0.7),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            value,
            style: pw.TextStyle(
              font: fontBold,
              fontSize: 10,
              color: textColor ?? (accentColor ?? const PdfColor.fromInt(0xFF1E2124)),
            ),
          ),
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 6.8,
              font: isHighlighted ? fontBold : null,
              color: textColor ?? const PdfColor.fromInt(0xFF6C757D),
            ),
          ),
          if (detail != null)
            pw.Text(
              detail,
              style: pw.TextStyle(
                fontSize: 6,
                color: textColor ?? const PdfColor.fromInt(0xFFADB5BD),
              ),
            ),
        ],
      ),
    );
  }

  static String _calculerTotalFacturable(Map<String, dynamic> intervention) {
    if (intervention['duree_totale_facturable'] != null &&
        intervention['duree_totale_facturable'].toString().isNotEmpty &&
        intervention['duree_totale_facturable'] != '--') {
      return intervention['duree_totale_facturable'].toString();
    }
    final trajetSec = dureeChaineVersSecondes(intervention['duree_trajet']);
    final chantierSec = dureeChaineVersSecondes(intervention['duree_chantier']);
    final retourSec = dureeChaineVersSecondes(intervention['duree_retour'] ?? intervention['duree_trajet']);
    final totalSec = trajetSec + chantierSec + retourSec;
    if (totalSec > 0) {
      return formatSeconds(totalSec);
    }
    return intervention['duree_totale']?.toString() ?? 'Facturation en régie';
  }

  static String _calculerKilometrageTotal(Map<String, dynamic> intervention) {
    double totalKm = 0.0;
    bool aDistance = false;

    double? parserKm(dynamic val) {
      if (val == null) return null;
      final str = val.toString().replaceAll(RegExp(r'[^0-9.,]'), '').replaceAll(',', '.').trim();
      return double.tryParse(str);
    }

    final dAller = parserKm(intervention['distance_km']);
    if (dAller != null && dAller > 0) {
      totalKm += dAller;
      aDistance = true;
    }

    final dRetour = parserKm(intervention['distance_retour_km']) ?? dAller;
    if (dRetour != null && dRetour > 0) {
      totalKm += dRetour;
      aDistance = true;
    }

    if (aDistance && totalKm > 0) {
      return totalKm % 1 == 0 ? '${totalKm.toInt()} km' : '${totalKm.toStringAsFixed(1)} km';
    }
    return '--';
  }
}

