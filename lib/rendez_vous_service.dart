import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import 'techniciens_service.dart';
import 'rapport_pdf.dart';
import 'app_helpers.dart';

// ============================================================================
// 📅 SERVICE CALENDRIER & FICHIER RENDEZ-VOUS (.ICS / iCalendar)
// ============================================================================

class CalendrierRendezVousService {
  /// Génère le contenu au format universel iCalendar (RFC 5545) compatible :
  /// - Microsoft Outlook (PC, Mac, Web)
  /// - Calendrier Android / Google Agenda
  /// - Calendrier Apple (iPhone, iPad, macOS)
  /// - Windows Courrier & Calendrier
  static String genererContenuIcs(Map<String, dynamic> intervention) {
    final nomClient = intervention['nom_client'] ?? 'Client Chantier';
    final noCommande = intervention['numero_commande'] ?? 'CMD-${intervention['id']}';
    final adresseChantier = intervention['adresse'] ?? 'Chantier';
    final trouble = intervention['trouble'] ?? 'Vérification et intervention technique';
    final machine = intervention['type_machine'] ?? 'Grue / Camion';
    final technicien = intervention['nom_technicien'] ?? 'Technicien assigné';
    final camion = intervention['numero_camion'] ?? 'Camion #101';
    final systeme = intervention['systeme_wylie'] ?? 'Système Rayco Wylie';
    final facturation = intervention['adresse_facturation'] ?? adresseChantier;
    final tel = intervention['telephone'] ?? '';
    final courriel = intervention['courriel'] ?? '';

    // Déterminer la date et l'heure du rendez-vous
    DateTime dateDebut;
    final dateStr = intervention['date_rendez_vous'] as String?;
    final heureStr = intervention['heure_rendez_vous'] as String?;

    if (dateStr != null && dateStr.isNotEmpty) {
      final parsedDate = DateTime.tryParse(dateStr);
      if (parsedDate != null) {
        int heure = 8;
        int minute = 30;
        if (heureStr != null && heureStr.contains(':')) {
          final parts = heureStr.split(':');
          heure = int.tryParse(parts[0]) ?? 8;
          minute = int.tryParse(parts[1]) ?? 30;
        }
        dateDebut = DateTime(parsedDate.year, parsedDate.month, parsedDate.day, heure, minute);
      } else {
        final now = DateTime.now();
        dateDebut = DateTime(now.year, now.month, now.day, 8, 30);
      }
    } else {
      final now = DateTime.now();
      dateDebut = DateTime(now.year, now.month, now.day, 8, 30);
    }

    final dureeMin = (intervention['duree_minutes'] is num)
        ? (intervention['duree_minutes'] as num).toInt()
        : 120; // 2 heures par défaut
    final dateFin = dateDebut.add(Duration(minutes: dureeMin));

    String formatIcsDate(DateTime dt) {
      final y = dt.year.toString().padLeft(4, '0');
      final m = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      final h = dt.hour.toString().padLeft(2, '0');
      final min = dt.minute.toString().padLeft(2, '0');
      final s = dt.second.toString().padLeft(2, '0');
      return '$y$m${d}T$h$min$s';
    }

    final uid = 'intervention_${intervention['id'] ?? DateTime.now().millisecondsSinceEpoch}@raycowylie.com';
    final dtStamp = formatIcsDate(DateTime.now());
    final dtStart = formatIcsDate(dateDebut);
    final dtEnd = formatIcsDate(dateFin);

    String escapeIcs(String text) {
      return text
          .replaceAll(r'\', r'\\')
          .replaceAll(';', r'\;')
          .replaceAll(',', r'\,')
          .replaceAll('\n', r'\n')
          .replaceAll('\r', '');
    }

    final summary = 'Intervention Chantier - $nomClient ($noCommande)';
    final description = StringBuffer()
      ..write('INTERVENTION TECHNIQUE RAYCO WYLIE\\n\\n')
      ..write('• Client : ${escapeIcs(nomClient)}\\n')
      ..write('• Nº Commande : ${escapeIcs(noCommande)}\\n')
      ..write('• Technicien : ${escapeIcs(technicien)}\\n')
      ..write('• Véhicule : ${escapeIcs(camion)}\\n')
      ..write('• Équipement : ${escapeIcs(machine)} (${escapeIcs(systeme)})\\n')
      ..write('• Chantier : ${escapeIcs(adresseChantier)}\\n')
      ..write('• Facturation : ${escapeIcs(facturation)}\\n');

    if (tel.isNotEmpty) description.write('• Téléphone contact : ${escapeIcs(tel)}\\n');
    if (courriel.isNotEmpty) description.write('• Courriel : ${escapeIcs(courriel)}\\n');
    description.write('\\nTROUBLE SIGNALÉ :\\n${escapeIcs(trouble)}\\n');

    final courrielTech = (intervention['courriel_technicien'] as String?)?.trim().isNotEmpty == true
        ? (intervention['courriel_technicien'] as String).trim()
        : '';

    return [
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//RaycoFieldService Route//FR',
      'CALSCALE:GREGORIAN',
      'METHOD:REQUEST',
      'BEGIN:VEVENT',
      'UID:$uid',
      'DTSTAMP:$dtStamp',
      'DTSTART:$dtStart',
      'DTEND:$dtEnd',
      'SUMMARY:${escapeIcs(summary)}',
      'DESCRIPTION:${description.toString()}',
      'LOCATION:${escapeIcs(adresseChantier)}',
      'ORGANIZER;CN=Rayco Wylie Service:mailto:dispatch@raycowylie.com',
      if (courrielTech.isNotEmpty)
        'ATTENDEE;ROLE=REQ-PARTICIPANT;PARTSTAT=NEEDS-ACTION;RSVP=TRUE;CN=${escapeIcs(technicien)}:mailto:${escapeIcs(courrielTech)}',
      'STATUS:CONFIRMED',
      'PRIORITY:1',
      'BEGIN:VALARM',
      'TRIGGER:-PT30M',
      'ACTION:DISPLAY',
      'DESCRIPTION:Rappel Intervention Chantier dans 30 min',
      'END:VALARM',
      'END:VEVENT',
      'END:VCALENDAR',
    ].join('\r\n');
  }

  /// Récupère ou crée le dossier Windows local dédié aux rendez-vous
  static Directory? getDossierRendezVousWindows() {
    if (kIsWeb) return null;
    try {
      final userProfile = Platform.environment['USERPROFILE'] ?? 'C:\\Users\\Default';
      final dir = Directory('$userProfile\\Documents\\AppTechnicien\\RendezVous');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      return dir;
    } catch (_) {
      return null;
    }
  }

  /// Sauvegarde temporaire ou locale du fichier .ics
  static Future<File?> sauvegarderFichierIcsLocal(Map<String, dynamic> intervention) async {
    if (kIsWeb) return null;
    try {
      final dir = getDossierRendezVousWindows();
      if (dir == null) return null;

      final cleanNo = (intervention['numero_commande'] ?? 'CMD_${intervention['id']}')
          .toString()
          .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final fileName = 'RendezVous_$cleanNo.ics';
      final file = File('${dir.path}\\$fileName');

      final icsContent = genererContenuIcs(intervention);
      await file.writeAsString(icsContent, encoding: utf8);
      return file;
    } catch (e) {
      debugPrint('Erreur sauvegarde ICS local: $e');
      return null;
    }
  }

  /// Option 1 : Enregistrer à l'emplacement désiré (FilePicker / Explorateur Windows)
  static Future<void> exporterFichierIcs(BuildContext context, Map<String, dynamic> intervention) async {
    final cleanNo = (intervention['numero_commande'] ?? 'CMD_${intervention['id']}')
        .toString()
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final nomFichierSuggere = 'RendezVous_$cleanNo.ics';
    final icsContent = genererContenuIcs(intervention);
    final bytes = Uint8List.fromList(utf8.encode(icsContent));

    final Uri? uriChoisi = await FilePicker.saveFile(
      dialogTitle: 'Enregistrer le fichier de rendez-vous (.ics)',
      fileName: nomFichierSuggere,
      bytes: bytes,
      mimeType: 'text/calendar',
    );

    if (uriChoisi == null) return;

    String cheminFinal = uriChoisi.path;
    if (!kIsWeb) {
      try {
        cheminFinal = uriChoisi.toFilePath();
      } catch (_) {
        cheminFinal = uriChoisi.path;
      }

      try {
        final f = File(cheminFinal);
        if (!await f.exists()) {
          await f.writeAsBytes(bytes);
        }
        if (Platform.isWindows) {
          await Process.run('explorer.exe', ['/select,', cheminFinal]);
        }
      } catch (_) {}
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Rendez-vous exporté avec succès ($nomFichierSuggere) !'),
          backgroundColor: Colors.green.shade800,
        ),
      );
    }
  }

  /// Option 2 : Ouvrir directement dans l'application Calendrier ou Outlook de Windows
  static Future<void> ouvrirDansCalendrierWindows(BuildContext context, Map<String, dynamic> intervention) async {
    if (kIsWeb || !Platform.isWindows) {
      // Fallback web / mobile : ouvrir Google Calendar
      await ouvrirDansGoogleCalendarWeb(intervention);
      return;
    }

    try {
      final file = await sauvegarderFichierIcsLocal(intervention);
      if (file != null && await file.exists()) {
        // Sous Windows, lancer le fichier .ics ouvre automatiquement Outlook ou l'application Calendrier
        await Process.run('explorer.exe', [file.path]);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('📅 Ouverture du rendez-vous dans votre calendrier Windows / Outlook...'),
              backgroundColor: Colors.indigo,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Erreur ouverture calendrier Windows: $e');
    }
  }

  /// Génère l'URL pour ajouter l'événement en 1 clic dans Google Calendar
  static String genererUrlGoogleCalendar(Map<String, dynamic> intervention, {String? courrielTech}) {
    final nomClient = intervention['nom_client'] ?? 'Client Chantier';
    final noCommande = intervention['numero_commande'] ?? '';
    final adresse = intervention['adresse'] ?? '';
    final trouble = intervention['trouble'] ?? '';
    final machine = intervention['type_machine'] ?? '';
    final tech = intervention['nom_technicien'] ?? '';
    final camion = intervention['numero_camion'] ?? '';

    DateTime dateDebut;
    final dateStr = intervention['date_rendez_vous'] as String?;
    final heureStr = intervention['heure_rendez_vous'] as String?;

    if (dateStr != null && dateStr.isNotEmpty) {
      final parsedDate = DateTime.tryParse(dateStr);
      if (parsedDate != null) {
        int h = 8, m = 30;
        if (heureStr != null && heureStr.contains(':')) {
          final p = heureStr.split(':');
          h = int.tryParse(p[0]) ?? 8;
          m = int.tryParse(p[1]) ?? 30;
        }
        dateDebut = DateTime(parsedDate.year, parsedDate.month, parsedDate.day, h, m);
      } else {
        final now = DateTime.now();
        dateDebut = DateTime(now.year, now.month, now.day, 8, 30);
      }
    } else {
      final now = DateTime.now();
      dateDebut = DateTime(now.year, now.month, now.day, 8, 30);
    }

    final dureeMin = (intervention['duree_minutes'] is num)
        ? (intervention['duree_minutes'] as num).toInt()
        : 120;
    final dateFin = dateDebut.add(Duration(minutes: dureeMin));

    String formatGoogleDate(DateTime dt) {
      final y = dt.year.toString().padLeft(4, '0');
      final m = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      final h = dt.hour.toString().padLeft(2, '0');
      final min = dt.minute.toString().padLeft(2, '0');
      final s = dt.second.toString().padLeft(2, '0');
      return '$y$m${d}T$h$min$s';
    }

    final datesParam = '${formatGoogleDate(dateDebut)}/${formatGoogleDate(dateFin)}';
    final titre = 'Intervention - $nomClient ($noCommande)';
    final details = 'Technicien : $tech ($camion)\nMachine : $machine\nTrouble : $trouble\nChantier : $adresse';

    final uri = Uri.parse('https://calendar.google.com/calendar/render').replace(
      queryParameters: {
        'action': 'TEMPLATE',
        'text': titre,
        'dates': datesParam,
        'details': details,
        'location': adresse,
        if (courrielTech != null && courrielTech.isNotEmpty) 'add': courrielTech,
      },
    );
    return uri.toString();
  }

  /// Génère l'URL pour ajouter l'événement en 1 clic dans Outlook Web
  static String genererUrlOutlookWeb(Map<String, dynamic> intervention, {String? courrielTech}) {
    final nomClient = intervention['nom_client'] ?? 'Client Chantier';
    final noCommande = intervention['numero_commande'] ?? '';
    final adresse = intervention['adresse'] ?? '';
    final trouble = intervention['trouble'] ?? '';
    final machine = intervention['type_machine'] ?? '';
    final tech = intervention['nom_technicien'] ?? '';
    final camion = intervention['numero_camion'] ?? '';

    DateTime dateDebut;
    final dateStr = intervention['date_rendez_vous'] as String?;
    final heureStr = intervention['heure_rendez_vous'] as String?;

    if (dateStr != null && dateStr.isNotEmpty) {
      final parsedDate = DateTime.tryParse(dateStr);
      if (parsedDate != null) {
        int h = 8, m = 30;
        if (heureStr != null && heureStr.contains(':')) {
          final p = heureStr.split(':');
          h = int.tryParse(p[0]) ?? 8;
          m = int.tryParse(p[1]) ?? 30;
        }
        dateDebut = DateTime(parsedDate.year, parsedDate.month, parsedDate.day, h, m);
      } else {
        final now = DateTime.now();
        dateDebut = DateTime(now.year, now.month, now.day, 8, 30);
      }
    } else {
      final now = DateTime.now();
      dateDebut = DateTime(now.year, now.month, now.day, 8, 30);
    }

    final dureeMin = (intervention['duree_minutes'] is num)
        ? (intervention['duree_minutes'] as num).toInt()
        : 120;
    final dateFin = dateDebut.add(Duration(minutes: dureeMin));

    final uri = Uri.parse('https://outlook.office.com/calendar/0/deeplink/compose').replace(
      queryParameters: {
        'subject': 'Intervention - $nomClient ($noCommande)',
        'startdt': dateDebut.toIso8601String(),
        'enddt': dateFin.toIso8601String(),
        'location': adresse,
        'body': 'Technicien : $tech ($camion)\nMachine : $machine\nTrouble : $trouble\nChantier : $adresse',
      },
    );
    return uri.toString();
  }

  /// Option 3 : Envoyer l'invitation par courriel avec Outlook (.ics attaché)
  static Future<void> envoyerInvitationOutlook(
    BuildContext context,
    Map<String, dynamic> intervention, {
    String? courrielForce,
    bool automatique = false,
  }) async {
    final nomClient = intervention['nom_client'] ?? 'Client';
    final noCommande = intervention['numero_commande'] ?? 'Intervention';
    final nomTech = intervention['nom_technicien'] ?? 'Technicien';
    final adresse = intervention['adresse'] ?? '';
    final trouble = intervention['trouble'] ?? '';
    final machine = intervention['type_machine'] ?? '';
    final dateStr = intervention['date_rendez_vous'] ?? 'À planifier';
    final heureStr = intervention['heure_rendez_vous'] ?? '08:30';
    final dureeMin = (intervention['duree_minutes'] is num) ? intervention['duree_minutes'] : 120;

    // Trouver le courriel du technicien
    String courrielTech = courrielForce ?? '';
    if (courrielTech.isEmpty && intervention['courriel_technicien'] != null) {
      courrielTech = (intervention['courriel_technicien'] as String).trim();
    }
    if (courrielTech.isEmpty) {
      final techniciens = await TechnicienService.instance.getTechniciens();
      for (final t in techniciens) {
        if (t.nom.trim().toLowerCase() == nomTech.toString().trim().toLowerCase() && t.courriel.isNotEmpty) {
          courrielTech = t.courriel;
          break;
        }
      }
    }
    if (courrielTech.isEmpty) {
      courrielTech = 'technicien@raycowylie.com';
    }

    final googleUrl = genererUrlGoogleCalendar(intervention, courrielTech: courrielTech);
    final outlookWebUrl = genererUrlOutlookWeb(intervention, courrielTech: courrielTech);

    final sujet = '📅 Rendez-vous Chantier : $nomClient ($noCommande) - $dateStr $heureStr';
    final corps = '''Bonjour $nomTech,

Voici les détails de votre rendez-vous pour votre intervention en chantier :

• Client : $nomClient
• Nº de commande : $noCommande
• Date et Heure : $dateStr à $heureStr (Durée estimée : $dureeMin min)
• Chantier : $adresse
• Machine : $machine
• Trouble à résoudre : $trouble

CALENDRIER & SYNCHRONISATION :
1. Fichier rendez-vous (.ics) attaché : Ouvrez ou acceptez l'invitation pour l'insérer directement dans votre agenda Outlook ou sur votre téléphone portable.
2. Ajouter en 1 clic dans Google Calendar :
$googleUrl
3. Ajouter en 1 clic dans Outlook Web :
$outlookWebUrl

Bon travail et restez prudent sur la route,
Service Dispatch & Superviseur Rayco Wylie''';

    if (!kIsWeb && Platform.isWindows) {
      final file = await sauvegarderFichierIcsLocal(intervention);
      final outlookPath = RapportPdfService.trouverOutlookPath();

      if (outlookPath != null && file != null) {
        try {
          await Process.start(outlookPath, [
            '/a',
            file.path,
            '/c',
            'IPM.Note',
            '/m',
            '$courrielTech?subject=${Uri.encodeComponent(sujet)}&body=${Uri.encodeComponent(corps)}',
          ]);

          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('📅 Invitation Outlook avec fichier .ics envoyée à $nomTech ($courrielTech) !'),
                backgroundColor: Colors.blue.shade800,
                duration: const Duration(seconds: 4),
              ),
            );
          }
          return;
        } catch (e) {
          debugPrint('Erreur lancement Outlook: $e');
        }
      }
    }

    // Fallback mailto standard
    final mailtoUri = Uri(
      scheme: 'mailto',
      path: courrielTech,
      queryParameters: {
        'subject': sujet,
        'body': corps,
      },
    );
    try {
      if (await canLaunchUrl(mailtoUri)) {
        await launchUrl(mailtoUri);
      }
    } catch (_) {}

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('📧 Invitation calendrier préparée pour $nomTech ($courrielTech) !'),
          backgroundColor: Colors.indigo,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  /// Option 4 : Lien direct vers Google Calendar Web (1-clic mobile ou bureau)
  static Future<void> ouvrirDansGoogleCalendarWeb(Map<String, dynamic> intervention) async {
    final courrielTech = intervention['courriel_technicien'] as String?;
    final url = genererUrlGoogleCalendar(intervention, courrielTech: courrielTech);
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Erreur ouverture Google Calendar: $e');
    }
  }

  /// Dialogue complet de gestion et partage du rendez-vous
  static Future<void> afficherDialogueRendezVous(
    BuildContext context,
    Map<String, dynamic> intervention, {
    VoidCallback? onModifiee,
  }) async {
    final nomClient = intervention['nom_client'] ?? 'Client';
    final noCommande = intervention['numero_commande'] ?? 'Sans numéro';
    final tech = intervention['nom_technicien'] ?? 'Non assigné';
    final camion = intervention['numero_camion'] ?? 'Camion #101';
    final dateRdv = intervention['date_rendez_vous'] ?? 'Non planifiée';
    final heureRdv = intervention['heure_rendez_vous'] ?? '08:30';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Material(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.indigo.shade100,
                  child: Icon(Icons.event_available, color: Colors.indigo.shade800),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Rendez-vous & Calendrier Technicien',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        '$nomClient • $noCommande',
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
              ],
            ),
            const Divider(height: 24),

            // Encadré récapitulatif du rendez-vous
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.indigo.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_month, color: Colors.indigo.shade800, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '📅 Date prévue : $dateRdv à $heureRdv',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Colors.indigo.shade900),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Technicien : $tech • $camion',
                          style: TextStyle(fontSize: 12, color: Colors.indigo.shade700),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            const Text(
              'CHOISIR UNE ACTION DE PARTAGE :',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.5),
            ),
            const SizedBox(height: 8),

            // Option 1 : Envoyer l'invitation Outlook au technicien
            Card(
              elevation: 0,
              color: Colors.blue.shade50,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: Colors.blue.shade200),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.blue.shade100,
                  child: Icon(Icons.mail, color: Colors.blue.shade900),
                ),
                title: const Text('Envoyer par courriel avec Outlook', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                subtitle: Text('Génère le courriel avec l\'invitation .ics attachée pour $tech', style: const TextStyle(fontSize: 11)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(ctx);
                  envoyerInvitationOutlook(context, intervention);
                },
              ),
            ),
            const SizedBox(height: 8),

            // Option 2 : Ouvrir dans le calendrier Windows / Outlook
            if (!kIsWeb && Platform.isWindows) ...[
              Card(
                elevation: 0,
                color: Colors.indigo.shade50,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: Colors.indigo.shade200),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.indigo.shade100,
                    child: Icon(Icons.desktop_windows, color: Colors.indigo.shade900),
                  ),
                  title: const Text('Ouvrir dans Calendrier / Outlook Windows', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                  subtitle: const Text('Ajoute instantanément le rendez-vous dans votre calendrier PC', style: TextStyle(fontSize: 11)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(ctx);
                    ouvrirDansCalendrierWindows(context, intervention);
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],

            // Option 3 : Ajouter dans Google Calendar (Mobile & Web)
            Card(
              elevation: 0,
              color: Colors.amber.shade50,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: Colors.amber.shade200),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.amber.shade100,
                  child: Icon(Icons.phone_android, color: Colors.amber.shade900),
                ),
                title: const Text('Ajouter à l\'agenda Google / Téléphone', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                subtitle: const Text('Ajout en 1-clic direct dans Google Agenda / Téléphone Android', style: TextStyle(fontSize: 11)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(ctx);
                  ouvrirDansGoogleCalendarWeb(intervention);
                },
              ),
            ),
            const SizedBox(height: 8),

            // Option 4 : Exporter le fichier .ics (Explorateur Windows / Téléchargement)
            Card(
              elevation: 0,
              color: Colors.grey.shade100,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: Colors.grey.shade300),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.grey.shade200,
                  child: const Icon(Icons.file_download, color: Colors.black87),
                ),
                title: const Text('Enregistrer le fichier rendez-vous (.ics)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                subtitle: const Text('Sauvegarder à l\'emplacement désiré pour partage Teams, WhatsApp, etc.', style: TextStyle(fontSize: 11)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(ctx);
                  exporterFichierIcs(context, intervention);
                },
              ),
            ),

            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copier les informations du rendez-vous'),
                onPressed: () {
                  final txt = '📅 RENDEZ-VOUS INTERVENTION :\n'
                      'Client : $nomClient\n'
                      'Nº Commande : $noCommande\n'
                      'Date : $dateRdv à $heureRdv\n'
                      'Technicien : $tech ($camion)\n'
                      'Chantier : ${intervention['adresse']}\n'
                      'Machine : ${intervention['type_machine']}\n'
                      'Trouble : ${intervention['trouble']}';
                  Clipboard.setData(ClipboardData(text: txt));
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('📋 Détails du rendez-vous copiés dans le presse-papiers !')),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }
}

// ============================================================================
// ✏️ MODALE DE MODIFICATION D'UNE INTERVENTION (SUPERVISEUR & DISPATCH)
// ============================================================================

class ModifierInterventionModal extends StatefulWidget {
  final Map<String, dynamic> intervention;
  final Function(Map<String, dynamic> interventionModifiee) onInterventionModifiee;

  const ModifierInterventionModal({
    super.key,
    required this.intervention,
    required this.onInterventionModifiee,
  });

  @override
  State<ModifierInterventionModal> createState() => _ModifierInterventionModalState();
}

class _ModifierInterventionModalState extends State<ModifierInterventionModal> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _clientCtrl;
  late TextEditingController _adresseChantierCtrl;
  late TextEditingController _adresseFacturationCtrl;
  late TextEditingController _commandeCtrl;
  late TextEditingController _referenceCtrl;
  late TextEditingController _bonCommandeCtrl;
  late TextEditingController _troubleCtrl;
  late TextEditingController _nomContactCtrl;
  late TextEditingController _telephoneCtrl;
  late TextEditingController _courrielCtrl;
  late TextEditingController _camionCtrl;

  // 🏗️ Informations Machine & Système Rayco Wylie
  late String _typeMachine;
  late TextEditingController _marqueCtrl;
  late TextEditingController _modeleCtrl;
  late TextEditingController _anneeCtrl;
  late TextEditingController _serieMachineCtrl;
  late TextEditingController _uniteCtrl;
  late String _alimentation;
  late TextEditingController _systemeCtrl;

  List<Technicien> _techniciens = [];
  Technicien? _technicienSelectionne;
  late String _statut;
  bool _isLoading = true;

  // Planification Calendrier
  DateTime _dateRdv = DateTime.now();
  TimeOfDay _heureRdv = const TimeOfDay(hour: 8, minute: 30);
  int _dureeMinutes = 120; // 2 heures par défaut
  bool _envoyerCalendrierAuto = false;

  @override
  void initState() {
    super.initState();
    final item = widget.intervention;

    _clientCtrl = TextEditingController(text: item['nom_client'] ?? '');
    _adresseChantierCtrl = TextEditingController(text: item['adresse'] ?? '');
    _adresseFacturationCtrl = TextEditingController(text: item['adresse_facturation'] ?? '');
    _commandeCtrl = TextEditingController(text: item['numero_commande'] ?? '');
    _referenceCtrl = TextEditingController(text: item['numero_reference'] ?? '');
    _bonCommandeCtrl = TextEditingController(text: item['numero_bon_commande'] ?? '');
    _troubleCtrl = TextEditingController(text: item['trouble'] ?? '');
    _nomContactCtrl = TextEditingController(text: item['nom_contact'] ?? '');
    _telephoneCtrl = TextEditingController(text: item['telephone'] ?? '');
    _courrielCtrl = TextEditingController(text: item['courriel'] ?? '');
    _camionCtrl = TextEditingController(text: item['numero_camion'] ?? 'Camion #101');

    final tInit = item['type_machine'] as String?;
    _typeMachine = (tInit != null && kTypesMachineRayco.contains(tInit))
        ? tInit
        : (kTypesMachineRayco.isNotEmpty ? kTypesMachineRayco.first : 'Grue téléscopique');
    _marqueCtrl = TextEditingController(text: item['marque'] ?? '');
    _modeleCtrl = TextEditingController(text: item['modele'] ?? '');
    _anneeCtrl = TextEditingController(text: item['annee'] ?? '');
    _serieMachineCtrl = TextEditingController(text: item['numero_serie_machine'] ?? '');
    _uniteCtrl = TextEditingController(text: item['numero_unite'] ?? '');
    final alim = item['alimentation']?.toString();
    _alimentation = (alim == '12v' || alim == '24v') ? alim! : '12v';
    _systemeCtrl = TextEditingController(text: item['systeme_wylie'] ?? item['numero_serie_systeme'] ?? 'Rayco Wylie i4500');

    _statut = item['statut'] ?? 'En attente';

    // Initialiser date et heure de rendez-vous
    if (item['date_rendez_vous'] != null && (item['date_rendez_vous'] as String).isNotEmpty) {
      final p = DateTime.tryParse(item['date_rendez_vous'] as String);
      if (p != null) _dateRdv = p;
    }
    if (item['heure_rendez_vous'] != null && (item['heure_rendez_vous'] as String).contains(':')) {
      final parts = (item['heure_rendez_vous'] as String).split(':');
      final h = int.tryParse(parts[0]) ?? 8;
      final m = int.tryParse(parts[1]) ?? 30;
      _heureRdv = TimeOfDay(hour: h, minute: m);
    }
    if (item['duree_minutes'] is num) {
      _dureeMinutes = (item['duree_minutes'] as num).toInt();
    }

    _chargerTechniciens();
  }

  Future<void> _chargerTechniciens() async {
    final list = await TechnicienService.instance.getTechniciens();
    setState(() {
      _techniciens = list;
      final techNom = widget.intervention['nom_technicien'] as String?;
      if (techNom != null && techNom.isNotEmpty) {
        final found = list.where((t) => t.nom == techNom).toList();
        _technicienSelectionne = found.isNotEmpty ? found.first : (list.isNotEmpty ? list.first : null);
      } else {
        _technicienSelectionne = list.isNotEmpty ? list.first : null;
      }
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _clientCtrl.dispose();
    _adresseChantierCtrl.dispose();
    _adresseFacturationCtrl.dispose();
    _commandeCtrl.dispose();
    _referenceCtrl.dispose();
    _bonCommandeCtrl.dispose();
    _troubleCtrl.dispose();
    _nomContactCtrl.dispose();
    _telephoneCtrl.dispose();
    _courrielCtrl.dispose();
    _camionCtrl.dispose();
    _marqueCtrl.dispose();
    _modeleCtrl.dispose();
    _anneeCtrl.dispose();
    _serieMachineCtrl.dispose();
    _uniteCtrl.dispose();
    _systemeCtrl.dispose();
    super.dispose();
  }

  Future<void> _choisirDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateRdv,
      firstDate: DateTime(2025),
      lastDate: DateTime(2030),
      helpText: 'SÉLECTIONNER LA DATE DU RENDEZ-VOUS',
      cancelText: 'Annuler',
      confirmText: 'Confirmer',
    );
    if (picked != null) {
      setState(() => _dateRdv = picked);
    }
  }

  Future<void> _choisirHeure() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _heureRdv,
      helpText: 'HEURE DU RENDEZ-VOUS EN CHANTIER',
      cancelText: 'Annuler',
      confirmText: 'Confirmer',
    );
    if (picked != null) {
      setState(() => _heureRdv = picked);
    }
  }

  Future<void> _sauvegarder() async {
    if (!_formKey.currentState!.validate()) return;

    final dateRdvStr = '${_dateRdv.year}-${_dateRdv.month.toString().padLeft(2, '0')}-${_dateRdv.day.toString().padLeft(2, '0')}';
    final heureRdvStr = '${_heureRdv.hour.toString().padLeft(2, '0')}:${_heureRdv.minute.toString().padLeft(2, '0')}';

    final modifiee = Map<String, dynamic>.from(widget.intervention);
    modifiee['nom_client'] = _clientCtrl.text.trim();
    modifiee['adresse'] = _adresseChantierCtrl.text.trim();
    modifiee['adresse_facturation'] = _adresseFacturationCtrl.text.trim().isNotEmpty
        ? _adresseFacturationCtrl.text.trim()
        : _adresseChantierCtrl.text.trim();
    modifiee['numero_commande'] = _commandeCtrl.text.trim();
    modifiee['numero_reference'] = _referenceCtrl.text.trim();
    modifiee['numero_bon_commande'] = _bonCommandeCtrl.text.trim();
    modifiee['trouble'] = _troubleCtrl.text.trim();
    modifiee['nom_contact'] = _nomContactCtrl.text.trim();
    modifiee['telephone'] = _telephoneCtrl.text.trim();
    modifiee['courriel'] = _courrielCtrl.text.trim();
    modifiee['type_machine'] = _typeMachine;
    modifiee['marque'] = _marqueCtrl.text.trim();
    modifiee['modele'] = _modeleCtrl.text.trim();
    modifiee['annee'] = _anneeCtrl.text.trim();
    modifiee['numero_serie_machine'] = _serieMachineCtrl.text.trim();
    modifiee['numero_unite'] = _uniteCtrl.text.trim();
    modifiee['alimentation'] = _alimentation;
    modifiee['systeme_wylie'] = _systemeCtrl.text.trim();
    modifiee['numero_serie_systeme'] = _systemeCtrl.text.trim();
    modifiee['nom_technicien'] = _technicienSelectionne?.nom ?? 'Non assigné';
    modifiee['numero_camion'] = _camionCtrl.text.trim();
    modifiee['statut'] = _statut;
    modifiee['courriel_technicien'] = _technicienSelectionne?.courriel ?? '';
    modifiee['envoyer_calendrier_auto'] = _envoyerCalendrierAuto;
    modifiee['date_rendez_vous'] = dateRdvStr;
    modifiee['heure_rendez_vous'] = heureRdvStr;
    modifiee['duree_minutes'] = _dureeMinutes;

    widget.onInterventionModifiee(modifiee);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final dateAffichee = '${_dateRdv.year}-${_dateRdv.month.toString().padLeft(2, '0')}-${_dateRdv.day.toString().padLeft(2, '0')}';
    final heureAffichee = '${_heureRdv.hour.toString().padLeft(2, '0')}:${_heureRdv.minute.toString().padLeft(2, '0')}';

    return Material(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 18,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // EN-TÊTE
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: Colors.indigo.shade100,
                          child: Icon(Icons.edit_note, color: Colors.indigo.shade800),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Modifier l\'intervention & Calendrier',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              Text(
                                'Ajuster les détails, l\'assignation et le rendez-vous',
                                style: TextStyle(color: Colors.grey, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                      ],
                    ),
                    const Divider(height: 20),

                    // ─── 📅 SECTION PLANIFICATION CALENDRIER (EN VEDETTE) ───
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.indigo.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.indigo.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.calendar_month, color: Colors.indigo.shade900, size: 18),
                              const SizedBox(width: 6),
                              Text(
                                'PLANIFICATION DU RENDEZ-VOUS',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.indigo.shade900),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: InkWell(
                                  onTap: _choisirDate,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.indigo.shade300),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.event, size: 18, color: Colors.indigo),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Text('Date rendez-vous', style: TextStyle(fontSize: 10, color: Colors.grey)),
                                              Text(dateAffichee, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: InkWell(
                                  onTap: _choisirHeure,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.indigo.shade300),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.access_time, size: 18, color: Colors.indigo),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Text('Heure', style: TextStyle(fontSize: 10, color: Colors.grey)),
                                              Text(heureAffichee, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // Durée estimée
                          Row(
                            children: [
                              const Text('Durée estimée :', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black87)),
                              const SizedBox(width: 8),
                              ...[60, 120, 180, 240].map((mins) {
                                final isSel = _dureeMinutes == mins;
                                final label = mins == 60 ? '1h' : mins == 120 ? '2h' : mins == 180 ? '3h' : '4h';
                                return Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: ChoiceChip(
                                    label: Text(label, style: TextStyle(fontSize: 11, fontWeight: isSel ? FontWeight.bold : FontWeight.normal)),
                                    selected: isSel,
                                    onSelected: (val) {
                                      if (val) setState(() => _dureeMinutes = mins);
                                    },
                                    selectedColor: Colors.indigo.shade200,
                                  ),
                                );
                              }),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ─── INFORMATIONS CLIENT & COMMANDE ───
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextFormField(
                            controller: _clientCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Nom du client / Compagnie *',
                              prefixIcon: Icon(Icons.business),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            validator: (v) => v == null || v.trim().isEmpty ? 'Requis' : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: _commandeCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Nº Commande *',
                              prefixIcon: Icon(Icons.tag),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            validator: (v) => v == null || v.trim().isEmpty ? 'Requis' : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // ─── BON DE COMMANDE CLIENT & RÉFÉRENCE ─────────
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _bonCommandeCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Bon de commande client (#PO-XXXXX)',
                              hintText: 'Ex: #PO-12345678',
                              prefixIcon: Icon(Icons.receipt),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: _referenceCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Nº de référence (TF-XXXXX)',
                              hintText: 'Ex: TF-12345',
                              prefixIcon: Icon(Icons.bookmark_outline),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // TROUBLE SIGNALÉ
                    TextFormField(
                      controller: _troubleCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Trouble signalé / Nature de la panne *',
                        prefixIcon: Icon(Icons.report_problem, color: Colors.amber),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Veuillez préciser le trouble' : null,
                    ),
                    const SizedBox(height: 10),

                    // ADRESSES (CHANTIER & FACTURATION)
                    TextFormField(
                      controller: _adresseChantierCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Adresse du chantier (Lieu d\'intervention) *',
                        prefixIcon: Icon(Icons.location_on, color: Colors.red),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Requis' : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _adresseFacturationCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Adresse de facturation (si différente)',
                        prefixIcon: Icon(Icons.receipt_long, color: Colors.indigo),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // ─── INFORMATIONS MACHINE & SYSTÈME ───
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.precision_manufacturing, color: Colors.orange.shade800, size: 18),
                              const SizedBox(width: 6),
                              Text(
                                'INFORMATIONS MACHINE & SYSTÈME RAYCO WYLIE',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: Colors.orange.shade900,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          // Type de machine déroulant standardisé
                          DropdownButtonFormField<String>(
                            initialValue: _typeMachine,
                            decoration: const InputDecoration(
                              labelText: 'Type de machine *',
                              prefixIcon: Icon(Icons.precision_manufacturing),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: kTypesMachineRayco.map((type) {
                              return DropdownMenuItem<String>(
                                value: type,
                                child: Text(type),
                              );
                            }).toList(),
                            onChanged: (v) {
                              if (v != null) setState(() => _typeMachine = v);
                            },
                          ),
                          const SizedBox(height: 10),
                          // Marque et Modèle
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _marqueCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Marque',
                                    prefixIcon: Icon(Icons.business_center),
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextFormField(
                                  controller: _modeleCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Modèle',
                                    prefixIcon: Icon(Icons.model_training),
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          // Année, Nº de série machine et Nº d'unité
                          Row(
                            children: [
                              Expanded(
                                flex: 1,
                                child: TextFormField(
                                  controller: _anneeCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Année',
                                    prefixIcon: Icon(Icons.calendar_today),
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  controller: _serieMachineCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Nº de série machine',
                                    prefixIcon: Icon(Icons.pin),
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  controller: _uniteCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Nº d\'unité machine',
                                    hintText: 'Ex: Unité #XX-XXXX',
                                    prefixIcon: Icon(Icons.pin_outlined),
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          // Système Rayco Wylie et Alimentation
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                flex: 3,
                                child: TextFormField(
                                  controller: _systemeCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Système Rayco Wylie',
                                    hintText: 'Ex: i4500, i4300, W2245...',
                                    prefixIcon: Icon(Icons.speed),
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Alimentation', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: ['12v', '24v'].map((v) {
                                      final isSel = _alimentation == v;
                                      return Padding(
                                        padding: const EdgeInsets.only(right: 4),
                                        child: ChoiceChip(
                                          label: Text(v, style: TextStyle(fontSize: 11, fontWeight: isSel ? FontWeight.bold : FontWeight.normal)),
                                          selected: isSel,
                                          onSelected: (val) {
                                            if (val) setState(() => _alimentation = v);
                                          },
                                          selectedColor: Colors.orange.shade200,
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),

                    // ─── ASSIGNATION TECHNICIEN & CAMION ───
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: DropdownButtonFormField<Technicien>(
                            initialValue: _technicienSelectionne,
                            decoration: const InputDecoration(
                              labelText: 'Technicien assigné *',
                              prefixIcon: Icon(Icons.person),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: _techniciens.map((t) {
                              return DropdownMenuItem(
                                value: t,
                                child: Text('${t.nom} (${t.numeroCamion})'),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _technicienSelectionne = val;
                                  _camionCtrl.text = val.numeroCamion;
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: _camionCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Camion',
                              prefixIcon: Icon(Icons.local_shipping),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    // ─── INFO COURRIEL DU TECHNICIEN POUR CALENDRIER ───
                    Container(
                      margin: const EdgeInsets.only(top: 6, bottom: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: (_technicienSelectionne?.courriel.isNotEmpty == true)
                            ? Colors.indigo.shade50
                            : Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: (_technicienSelectionne?.courriel.isNotEmpty == true)
                              ? Colors.indigo.shade200
                              : Colors.orange.shade300,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            (_technicienSelectionne?.courriel.isNotEmpty == true)
                                ? Icons.mark_email_read
                                : Icons.warning_amber_rounded,
                            size: 16,
                            color: (_technicienSelectionne?.courriel.isNotEmpty == true)
                                ? Colors.indigo.shade800
                                : Colors.orange.shade900,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              (_technicienSelectionne?.courriel.isNotEmpty == true)
                                  ? 'Courriel calendrier : ${_technicienSelectionne!.courriel}'
                                  : 'Aucun courriel associé à ce technicien',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: (_technicienSelectionne?.courriel.isNotEmpty == true)
                                    ? Colors.indigo.shade900
                                    : Colors.orange.shade900,
                              ),
                            ),
                          ),
                          if (_technicienSelectionne?.courriel.isNotEmpty == true)
                            const Icon(Icons.check_circle, size: 14, color: Colors.green),
                        ],
                      ),
                    ),
                    CheckboxListTile(
                      value: _envoyerCalendrierAuto,
                      onChanged: (val) => setState(() => _envoyerCalendrierAuto = val ?? false),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Renvoyer / mettre à jour l\'invitation dans le calendrier du technicien',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      subtitle: const Text(
                        'Envoie la mise à jour .ics vers son adresse courriel',
                        style: TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    const SizedBox(height: 10),

                    // ─── CONTACT SUR PLACE (NOM & TÉLÉPHONE RELIÉS) ───
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextFormField(
                            controller: _nomContactCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Nom du contact sur place',
                              prefixIcon: Icon(Icons.person),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: _telephoneCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Téléphone contact',
                              prefixIcon: Icon(Icons.phone),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            keyboardType: TextInputType.phone,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // ─── COURRIEL CONTACT & STATUT ACTUEL ───
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextFormField(
                            controller: _courrielCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Courriel contact',
                              prefixIcon: Icon(Icons.email),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            keyboardType: TextInputType.emailAddress,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<String>(
                            initialValue: _statut,
                            decoration: const InputDecoration(
                              labelText: 'Statut actuel',
                              prefixIcon: Icon(Icons.sync),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: const [
                              DropdownMenuItem(value: 'En attente', child: Text('En attente')),
                              DropdownMenuItem(value: 'En route', child: Text('En route')),
                              DropdownMenuItem(value: 'Arrivé', child: Text('Arrivé')),
                              DropdownMenuItem(value: 'En attente d\'approbation', child: Text('En attente d\'approbation')),
                              DropdownMenuItem(value: 'Complété', child: Text('Complété')),
                            ],
                            onChanged: (v) => setState(() => _statut = v ?? 'En attente'),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 18),

                    // BOUTONS D'ACTION
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.save, size: 18),
                            label: const Text('Enregistrer modifications', style: TextStyle(fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.indigo.shade800,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: _sauvegarder,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.share, size: 18),
                            label: const Text('Rendez-vous (.ics)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              side: BorderSide(color: Colors.indigo.shade400),
                            ),
                            onPressed: () {
                              final currentMap = Map<String, dynamic>.from(widget.intervention);
                              currentMap['nom_client'] = _clientCtrl.text.trim();
                              currentMap['numero_commande'] = _commandeCtrl.text.trim();
                              currentMap['adresse'] = _adresseChantierCtrl.text.trim();
                              currentMap['nom_technicien'] = _technicienSelectionne?.nom ?? '';
                              currentMap['numero_camion'] = _camionCtrl.text.trim();
                              currentMap['trouble'] = _troubleCtrl.text.trim();
                              currentMap['type_machine'] = _typeMachine;
                              currentMap['marque'] = _marqueCtrl.text.trim();
                              currentMap['modele'] = _modeleCtrl.text.trim();
                              currentMap['systeme_wylie'] = _systemeCtrl.text.trim();
                              currentMap['nom_contact'] = _nomContactCtrl.text.trim();
                              currentMap['telephone'] = _telephoneCtrl.text.trim();
                              currentMap['courriel'] = _courrielCtrl.text.trim();
                              currentMap['date_rendez_vous'] = dateAffichee;
                              currentMap['heure_rendez_vous'] = heureAffichee;
                              currentMap['duree_minutes'] = _dureeMinutes;

                              CalendrierRendezVousService.afficherDialogueRendezVous(context, currentMap);
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
      ),
    );
  }
}
