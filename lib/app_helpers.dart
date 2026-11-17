import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

// ==========================================
// 🛠️ FONCTIONS UTILITAIRES & FORMATAGE TEMPS
// ==========================================

String formatSeconds(int totalSeconds) {
  if (totalSeconds < 60) {
    return '$totalSeconds sec';
  }
  final minutes = totalSeconds ~/ 60;
  if (minutes < 60) {
    return '$minutes min';
  }
  final hours = minutes ~/ 60;
  final remainingMinutes = minutes % 60;
  if (remainingMinutes == 0) {
    return '${hours}h';
  }
  return '${hours}h ${remainingMinutes}m';
}

/// Formate un nombre de secondes en chronomètre HH:MM:SS
String formatChrono(int totalSeconds) {
  if (totalSeconds < 0) totalSeconds = 0;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  final h = hours.toString().padLeft(2, '0');
  final m = minutes.toString().padLeft(2, '0');
  final s = seconds.toString().padLeft(2, '0');
  return '$h:$m:$s';
}

/// Arrondit un nombre de minutes au quart d'heure (15 min).
/// [toujoursPlusHaut] : Si true (pour déplacements et temps chantier),
/// arrondit TOUJOURS au quart d'heure supérieur (ex: 1 min -> 15 min, 16 min -> 30 min).
/// Si false (pour repas/pauses), arrondit au quart d'heure le plus proche (ex: 7 min -> 0 min, 8 min -> 15 min).
int arrondirAuQuartDHeureMinutes(int minutes, {bool toujoursPlusHaut = false}) {
  if (minutes <= 0) return 0;
  if (toujoursPlusHaut) {
    return ((minutes + 14) ~/ 15) * 15;
  }
  return ((minutes + 7) ~/ 15) * 15;
}

/// Arrondit un nombre de secondes au quart d'heure (retourne la valeur en secondes).
int arrondirAuQuartDHeureSecondes(int seconds, {bool toujoursPlusHaut = false}) {
  if (seconds <= 0) return 0;
  final minutes = (seconds + 59) ~/ 60;
  return arrondirAuQuartDHeureMinutes(minutes, toujoursPlusHaut: toujoursPlusHaut) * 60;
}

/// Convertit un DateTime en Heure de l'Est (Toronto / Montréal / Québec - EDT/EST).
/// Heure Avancée de l'Est (EDT) = UTC-4 (2e dimanche de mars au 1er dimanche de novembre).
/// Heure Normale de l'Est (EST) = UTC-5 (le reste de l'année).
DateTime versHeureDeLEst(DateTime dt) {
  final utc = dt.isUtc ? dt : dt.toUtc();
  final annee = utc.year;

  // 2e dimanche de mars à 2h00 EST (7h00 UTC)
  DateTime debutAvancee = DateTime.utc(annee, 3, 8);
  while (debutAvancee.weekday != DateTime.sunday) {
    debutAvancee = debutAvancee.add(const Duration(days: 1));
  }
  debutAvancee = DateTime.utc(annee, 3, debutAvancee.day, 7, 0);

  // 1er dimanche de novembre à 2h00 EDT (6h00 UTC)
  DateTime finAvancee = DateTime.utc(annee, 11, 1);
  while (finAvancee.weekday != DateTime.sunday) {
    finAvancee = finAvancee.add(const Duration(days: 1));
  }
  finAvancee = DateTime.utc(annee, 11, finAvancee.day, 6, 0);

  final bool estAvancee = utc.isAfter(debutAvancee) && utc.isBefore(finAvancee);
  final offsetHeures = estAvancee ? -4 : -5;
  final est = utc.add(Duration(hours: offsetHeures));

  return DateTime(
    est.year,
    est.month,
    est.day,
    est.hour,
    est.minute,
    est.second,
    est.millisecond,
  );
}

/// Heure actuelle dans le fuseau de l'Est (Toronto / Montréal - EDT/EST)
DateTime heureActuelleEst() => versHeureDeLEst(DateTime.now());

String formatHeure(dynamic dateStr) {
  if (dateStr == null) return '--:--';
  final d = DateTime.tryParse(dateStr.toString());
  if (d == null) return '--:--';
  final est = versHeureDeLEst(d);
  final h = est.hour.toString().padLeft(2, '0');
  final m = est.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

/// Calcule les secondes écoulées réelles depuis un horodatage ISO ou DateTime.
/// Compare en UTC pour garantir une synchronisation parfaite sans décalage de fuseau horaire.
int calculerSecondesEcoulees(dynamic debutStr, {int pauseSec = 0}) {
  if (debutStr == null) return 0;
  final dt = DateTime.tryParse(debutStr.toString());
  if (dt == null) return 0;
  final nowUtc = DateTime.now().toUtc();
  final debutUtc = dt.isUtc ? dt : dt.toUtc();
  int diff = nowUtc.difference(debutUtc).inSeconds - pauseSec;
  return diff < 0 ? 0 : diff;
}

/// Convertit une chaîne de durée (ex: "45 min", "1h 30m", "2h", "15 sec") en secondes
int dureeChaineVersSecondes(dynamic val) {
  if (val == null) return 0;
  if (val is num) return val.toInt();
  final str = val.toString().trim();
  if (str.isEmpty || str == '--') return 0;

  int totalSec = 0;
  final regH = RegExp(r'(\d+)\s*h');
  final regM = RegExp(r'(\d+)\s*m(?:in)?');
  final regS = RegExp(r'(\d+)\s*s(?:ec)?');

  final matchH = regH.firstMatch(str);
  if (matchH != null) {
    totalSec += (int.tryParse(matchH.group(1)!) ?? 0) * 3600;
  }

  final matchM = regM.firstMatch(str);
  if (matchM != null) {
    totalSec += (int.tryParse(matchM.group(1)!) ?? 0) * 60;
  }

  final matchS = regS.firstMatch(str);
  if (matchS != null && matchH == null && matchM == null) {
    totalSec += (int.tryParse(matchS.group(1)!) ?? 0);
  }

  return totalSec;
}

/// Génère un numéro de rapport unique basé sur la date/heure
/// Format: AAMMJJHHNN → ex: 2609261649 pour le 26/09/26 à 16h49
String genererNumeroRapport() {
  final now = DateTime.now();
  final aa = now.year.toString().substring(2);
  final mm = now.month.toString().padLeft(2, '0');
  final jj = now.day.toString().padLeft(2, '0');
  final hh = now.hour.toString().padLeft(2, '0');
  final nn = now.minute.toString().padLeft(2, '0');
  return '$aa$mm$jj$hh$nn';
}

/// 🔩 Lit les pièces utilisées enregistrées sur une intervention
/// (texte JSON ou liste) et normalise les champs numériques.
List<Map<String, dynamic>> getPiecesUtilisees(Map<String, dynamic> intervention) {
  final raw = intervention['pieces_utilisees'];
  List<dynamic>? liste;
  if (raw is String && raw.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) liste = decoded;
    } catch (_) {}
  } else if (raw is List) {
    liste = raw;
  }
  if (liste == null) return [];
  return liste.whereType<Map>().map((m) {
    final p = Map<String, dynamic>.from(m);
    p['ref'] = (p['ref'] ?? p['reference'] ?? '').toString();
    p['nom'] = (p['nom'] ?? p['designation'] ?? '').toString();
    p['unite'] = (p['unite'] ?? 'pcs').toString();
    p['utilise'] = (p['utilise'] as num?)?.toInt() ?? 1;
    p['quantite'] = (p['quantite'] as num?)?.toInt() ?? 0;
    return p;
  }).where((p) => (p['utilise'] as int) > 0).toList();
}

/// 🏗️ Liste standardisée des types d'équipements et machines RaycoWylie
const List<String> kTypesMachineRayco = [
  'Chariot élévateur',
  'Grue téléscopique',
  'Grue conventionelle',
  'Grue articulée',
  'Pelle',
  'Pépine',
  'Camion',
  'Pompe à béton',
  'Téléhandler',
  'Nacelle',
  'Autre',
];

/// 🛡️ Points de contrôle de sécurité et conformité standardisés RaycoWylie
const List<String> kControlesSecuriteStandards = [
  'Capteurs d\'angle et de longueur inspectés & calibrés',
  'Transducteurs de pression hydraulique vérifiés sous charge',
  'Interrupteur Anti-Two-Block (A2B) et coupure testés',
  'Afficheur cabine, alarmes et seuils limites opérationnels',
  'Câblage, connecteurs et boîtes de jonction vérifiés',
  'Essai de coupure des mouvements (solénoïdes / lockout)',
  'Validation des tables de charges / abaques manufacturier',
  'Vérification visuelle générale de l\'installation et fixations',
];

/// 🛡️ Colonnes réelles et vérifiées de la table Supabase `interventions`
const Set<String> kColonnesInterventionsSupabase = {
  'id',
  'nom_client',
  'adresse_facturation',
  'adresse',
  'statut',
  'numero_commande',
  'numero_rapport',
  'numero_reference',
  'nom_technicien',
  'numero_camion',
  'trouble',
  'type_machine',
  'marque',
  'modele',
  'annee',
  'numero_serie_machine',
  'alimentation',
  'numero_produit',
  'numero_serie_systeme',
  'version_logiciel',
  'engrenage',
  'position_bypass',
  'priorite',
  'date_rendez_vous',
  'heure_rendez_vous',
  'duree_minutes',
  'telephone',
  'courriel',
  'nom_contact',
  'date_chantier',
  'heure_depart_trajet',
  'heure_arrivee_site',
  'heure_debut_redaction_rapport',
  'heure_cloture',
  'heure_signature',
  'duree_trajet',
  'distance_km',
  'duree_chantier',
  'duree_chantier_secondes',
  'duree_redaction_secondes',
  'duree_pause_secondes',
  'duree_pause_chantier_secondes',
  'en_pause',
  'heure_debut_pause',
  'en_pause_chantier',
  'heure_debut_pause_chantier',
  'motif_pause_chantier',
  'gps_depart',
  'gps_lat_depart',
  'gps_lng_depart',
  'gps_arrivee',
  'notes',
  'photos',
  'pieces_utilisees',
  'signature',
  'signature_token',
  'signature_a_distance_demandee',
  'nom_signataire_distant',
  'est_archive',
  'date_archivage',
  'created_at',
  'updated_at',
};

// ==========================================
// 📦 HELPERS ARCHIVAGE DES INTERVENTIONS
// ==========================================

/// Indique si une intervention est archivée
bool estInterventionArchivee(Map intervention) {
  if (intervention['est_archive'] == true ||
      intervention['est_archive'] == 'true' ||
      intervention['est_archive'] == 1) {
    return true;
  }
  final notes = (intervention['notes'] ?? '').toString();
  return notes.contains('[ARCHIVE: OUI]');
}

/// Marque une intervention comme archivée (mémoire + notes)
void archiverIntervention(Map intervention) {
  intervention['est_archive'] = true;
  final nowStr = DateTime.now().toUtc().toIso8601String();
  intervention['date_archivage'] = nowStr;
  final notes = (intervention['notes'] ?? '').toString();
  if (!notes.contains('[ARCHIVE: OUI]')) {
    intervention['notes'] = notes.isEmpty ? '[ARCHIVE: OUI]' : '$notes\n[ARCHIVE: OUI]';
  }
}

/// Restaure une intervention archivée vers l'état actif (mémoire + notes)
void restaurerIntervention(Map intervention) {
  intervention['est_archive'] = false;
  intervention['date_archivage'] = null;
  final notes = (intervention['notes'] ?? '').toString();
  intervention['notes'] = notes
      .replaceAll(RegExp(r'\[ARCHIVE:\s*[^\]]+\]'), '')
      .replaceAll(RegExp(r'\n{2,}'), '\n')
      .trim();
}

// ==========================================
// ✍️ HELPERS SIGNATURE À DISTANCE
// ==========================================

/// Extrait le token de signature à distance depuis l'intervention ou ses notes
String? getSignatureToken(Map<String, dynamic> intervention) {
  if (intervention['signature_token'] != null &&
      intervention['signature_token'].toString().trim().isNotEmpty) {
    return intervention['signature_token'].toString().trim();
  }
  final notes = (intervention['notes'] ?? '').toString();
  final m = RegExp(r'\[SIG_TOKEN:\s*([^\]]+)\]').firstMatch(notes);
  return m?.group(1)?.trim();
}

/// Indique si une signature à distance a été demandée pour cette intervention
bool estSignatureADistanceDemandee(Map<String, dynamic> intervention) {
  if (intervention['signature_a_distance_demandee'] == true) return true;
  final notes = (intervention['notes'] ?? '').toString();
  return notes.contains('[SIG_DISTANTE: OUI]');
}

/// Vérifie si l'intervention possède déjà une signature valide
bool aSignatureClient(Map<String, dynamic> intervention) {
  final sig = intervention['signature'];
  return sig != null && sig.toString().trim().isNotEmpty;
}

// ==========================================
// 📁 GESTION DES PHOTOS ET DOSSIERS (WINDOWS & WEB)
// ==========================================

bool get isWindowsDesktop => !kIsWeb && Platform.isWindows;

String getFileNameFromPath(String path) {
  final parts = path.split(RegExp(r'[\\/]'));
  return parts.isNotEmpty ? parts.last : path;
}

Widget buildImageFromPath(
  String path, {
  BoxFit fit = BoxFit.cover,
  int? cacheWidth,
  int? cacheHeight,
}) {
  if (kIsWeb || path.startsWith('http://') || path.startsWith('https://') || path.startsWith('blob:')) {
    return Image.network(
      path,
      fit: fit,
      errorBuilder: (c, e, s) => Container(
        color: Colors.grey.shade200,
        child: const Icon(Icons.broken_image, color: Colors.grey),
      ),
    );
  } else {
    final file = File(path);
    return Image.file(
      file,
      fit: fit,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
      errorBuilder: (c, e, s) => Container(
        color: Colors.grey.shade200,
        child: const Icon(Icons.broken_image, color: Colors.grey),
      ),
    );
  }
}

String getNumeroDossier(Map<String, dynamic> intervention) {
  if (intervention['numero_commande'] != null &&
      (intervention['numero_commande'] as String).trim().isNotEmpty) {
    return (intervention['numero_commande'] as String)
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }
  if (intervention['numero_bon_commande'] != null &&
      (intervention['numero_bon_commande'] as String).trim().isNotEmpty) {
    return (intervention['numero_bon_commande'] as String)
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }
  if (intervention['numero_rapport'] != null &&
      (intervention['numero_rapport'] as String).trim().isNotEmpty) {
    return (intervention['numero_rapport'] as String)
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }
  return 'CMD_${intervention['id'] ?? 'SANS_NUMERO'}';
}

Directory? getDossierPhotos(String numeroCommande) {
  if (kIsWeb) return null;
  final cleanNum =
      numeroCommande.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  final folderName = cleanNum.isNotEmpty ? cleanNum : 'COMMANDE_SANS_NUMERO';

  if (!kIsWeb && Platform.isWindows) {
    final userProfile =
        Platform.environment['USERPROFILE'] ?? 'C:\\Users\\Default';
    return Directory('$userProfile\\Pictures\\$folderName');
  } else if (!kIsWeb) {
    return Directory('${Directory.systemTemp.path}/Pictures/$folderName');
  }
  return null;
}

/// Enregistre une photo directement par copie rapide de fichier (sans saturer la mémoire RAM)
Future<String?> enregistrerPhotoDepuisChemin({
  required String sourcePath,
  required String numeroCommande,
}) async {
  try {
    if (kIsWeb) return sourcePath;
    final srcFile = File(sourcePath);
    if (!srcFile.existsSync()) return sourcePath;

    final targetDir = getDossierPhotos(numeroCommande);
    if (targetDir != null) {
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }
      final ext = sourcePath.split('.').last;
      final cleanExt = ext.isNotEmpty && ext.length <= 4 ? ext : 'jpg';
      final fileName = 'photo_${DateTime.now().millisecondsSinceEpoch}.$cleanExt';
      final separator = (!kIsWeb && Platform.isWindows) ? '\\' : '/';
      final targetPath = '${targetDir.path}$separator$fileName';

      // Copie directe de fichier (instantanée, sans chargement de mégabytes en mémoire)
      await srcFile.copy(targetPath);
      return targetPath;
    }
    return sourcePath;
  } catch (e) {
    debugPrint('Erreur enregistrement photo depuis chemin: $e');
    return sourcePath;
  }
}

Future<String?> enregistrerPhotoCommande({
  required XFile xFile,
  required String numeroCommande,
}) async {
  return enregistrerPhotoDepuisChemin(
    sourcePath: xFile.path,
    numeroCommande: numeroCommande,
  );
}

Future<void> ouvrirDossierPhotos(String numeroCommande) async {
  if (kIsWeb) {
    debugPrint('Ouverture dossier non disponible sur le web');
    return;
  }
  try {
    final targetDir = getDossierPhotos(numeroCommande);
    if (targetDir != null) {
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }
      if (!kIsWeb && Platform.isWindows) {
        await Process.run('explorer.exe', [targetDir.path]);
      }
    }
  } catch (e) {
    debugPrint('Erreur ouverture dossier: $e');
  }
}

// ==========================================
// 🛡️ GESTION APPROBATION SUPERVISEUR & CONFORMITÉ
// ==========================================

bool estRapportApprouve(Map<String, dynamic> intervention) {
  if (intervention['approuve_par_superviseur'] == true) return true;
  final notes = intervention['notes']?.toString() ?? '';
  if (notes.contains('[SUPERVISEUR: APPROUVÉ')) return true;
  // Si le statut est Complété et qu'il n'y a pas explicitement d'attente d'approbation
  if (intervention['statut'] == 'Complété' && intervention['approuve_par_superviseur'] != false) {
    return true;
  }
  return false;
}

String getNomSuperviseur(Map<String, dynamic> intervention) {
  if (intervention['nom_superviseur'] != null &&
      (intervention['nom_superviseur'] as String).trim().isNotEmpty) {
    return (intervention['nom_superviseur'] as String).trim();
  }
  final notes = intervention['notes']?.toString() ?? '';
  final match = RegExp(r'\[SUPERVISEUR: APPROUVÉ.*?par ([^\]]+)\]').firstMatch(notes);
  if (match != null && match.group(1) != null) {
    return match.group(1)!.trim();
  }
  return 'Superviseur RaycoWylie';
}

String getDateApprobationSuperviseur(Map<String, dynamic> intervention) {
  if (intervention['date_approbation_superviseur'] != null) {
    return intervention['date_approbation_superviseur'].toString();
  }
  final notes = intervention['notes']?.toString() ?? '';
  final match = RegExp(r'\[SUPERVISEUR: APPROUVÉ le ([0-9\- :]+) par').firstMatch(notes);
  if (match != null && match.group(1) != null) {
    return match.group(1)!.trim();
  }
  return intervention['heure_cloture']?.toString() ?? DateTime.now().toIso8601String();
}

// ==========================================
// 🛡️ DÉCODAGE & GESTION CONTRÔLES DE SÉCURITÉ
// ==========================================

/// Récupère la liste exacte des contrôles de sécurité cochés par le technicien.
/// Ne retourne JAMAIS de valeurs par défaut si l'utilisateur ne les a pas cochées.
List<String> getControlesSecurite(Map intervention) {
  try {
    final rawControles = intervention['controles_securite'];
    if (rawControles is List) {
      return rawControles
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
    } else if (rawControles is String && rawControles.trim().isNotEmpty) {
      final decoded = jsonDecode(rawControles.trim());
      if (decoded is List) {
        return decoded
            .map((e) => e.toString().trim())
            .where((s) => s.isNotEmpty)
            .toList();
      }
    }
  } catch (_) {}

  // Vérifier également dans les notes si la balise [CONTROLES: ...] est présente
  final notes = (intervention['notes'] ?? '').toString();
  if (notes.contains('[CONTROLES:')) {
    // 1. Recherche par délimiteurs de crochets pour le tableau JSON (insensible aux virgules/espaces)
    final idx = notes.indexOf('[CONTROLES:');
    final startArray = notes.indexOf('[', idx + 11);
    if (startArray != -1) {
      final endArray = notes.indexOf(']', startArray);
      if (endArray != -1) {
        final cStr = notes.substring(startArray, endArray + 1).trim();
        try {
          final decoded = jsonDecode(cStr);
          if (decoded is List) {
            return decoded
                .map((e) => e.toString().trim())
                .where((s) => s.isNotEmpty)
                .toList();
          }
        } catch (_) {}
      }
    }

    // 2. Fallback regex pour autres formats
    final m = RegExp(r'\[CONTROLES:\s*(\[[\s\S]*?\]|[^\]]+)\]').firstMatch(notes);
    if (m != null) {
      final cStr = m.group(1)?.trim();
      if (cStr != null && cStr.isNotEmpty) {
        try {
          final decoded = jsonDecode(cStr);
          if (decoded is List) {
            return decoded
                .map((e) => e.toString().trim())
                .where((s) => s.isNotEmpty)
                .toList();
          }
        } catch (_) {}
      }
    }
  }

  return [];
}

// ==========================================
// 📸 GESTION CENTRALISÉE DES PHOTOS
// ==========================================

List<String> getPhotosIntervention(Map intervention) {
  final raw = intervention['photos'];
  if (raw is List) {
    return raw.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
  } else if (raw is String && raw.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(raw.trim());
      if (decoded is List) {
        return decoded.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
      }
    } catch (_) {}
  }
  return [];
}

// ==========================================
// 📝 GESTION DES NOTES DE SERVICE
// ==========================================

String getNotesDeService(Map intervention) {
  final notes = (intervention['notes'] ?? '').toString();
  return notes
      .replaceAll(RegExp(r'\[RETOUR:[^\]]+\]'), '')
      .replaceAll(RegExp(r'\[CONTROLES:\s*\[[\s\S]*?\]\s*\]'), '')
      .replaceAll(RegExp(r'\[CONTROLES:[^\]]+\]'), '')
      .replaceAll(RegExp(r'\[SUPERVISEUR:[^\]]+\]'), '')
      .replaceAll(RegExp(r'\[SIG_TOKEN:[^\]]+\]'), '')
      .replaceAll(RegExp(r'\[SIG_DISTANTE:[^\]]+\]'), '')
      .replaceAll(RegExp(r'\[SIG_NOM:[^\]]+\]'), '')
      .replaceAll(RegExp(r'\[ARCHIVE:[^\]]+\]'), '')
      .trim();
}

void setNotesDeService(Map intervention, String texteNotes) {
  final existingNotes = (intervention['notes'] ?? '').toString();
  final tags = <String>[];
  for (final pattern in [
    r'\[RETOUR:[^\]]+\]',
    r'\[CONTROLES:\s*\[[\s\S]*?\]\s*\]',
    r'\[CONTROLES:[^\]]+\]',
    r'\[SUPERVISEUR:[^\]]+\]',
    r'\[SIG_TOKEN:[^\]]+\]',
    r'\[SIG_DISTANTE:[^\]]+\]',
    r'\[SIG_NOM:[^\]]+\]',
    r'\[ARCHIVE:[^\]]+\]',
  ]) {
    final m = RegExp(pattern).firstMatch(existingNotes);
    if (m != null && !tags.contains(m.group(0)!)) {
      tags.add(m.group(0)!);
    }
  }
  final cleanText = texteNotes.trim();
  String result = cleanText;
  for (final tag in tags) {
    result = result.isEmpty ? tag : '$result\n$tag';
  }
  intervention['notes'] = result;
}
