import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:signature/signature.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_helpers.dart';
import 'rapport_detail_screen.dart';
import 'rapport_pdf.dart';
import 'feuille_de_temps.dart';
import 'signature_distance_service.dart';

// ==========================================
// ✍️ ÉCRAN : CLÔTURE & SIGNATURE DU CLIENT
// ==========================================
class ClotureScreen extends StatefulWidget {
  final Map<String, dynamic> intervention;
  const ClotureScreen({super.key, required this.intervention});

  @override
  State<ClotureScreen> createState() => _ClotureScreenState();
}

class _ClotureScreenState extends State<ClotureScreen> {
  final SignatureController _sigController = SignatureController(
    penStrokeWidth: 4,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _distanceRetourCtrl = TextEditingController();
  bool _isUploading = false;
  final List<String> _photos = [];
  int _secondesRetourCustom = 0;
  bool _retourAjusteManuellement = false;

  // ─── Chronomètre temps facturable en direct ──────────────────────────
  Timer? _liveTimer;

  int get _secondesTrajetAller {
    final it = widget.intervention;
    if (it['duree_trajet_secondes'] is num && (it['duree_trajet_secondes'] as num) > 0) {
      return (it['duree_trajet_secondes'] as num).toInt();
    }
    if (it['duree_trajet'] != null) {
      final s = dureeChaineVersSecondes(it['duree_trajet']);
      if (s > 0) return arrondirAuQuartDHeureSecondes(s, toujoursPlusHaut: true);
    }
    final depStr = it['heure_depart_trajet'] as String?;
    final arrStr = it['heure_arrivee_site'] as String?;
    if (depStr != null && arrStr != null) {
      final d = DateTime.tryParse(depStr);
      final a = DateTime.tryParse(arrStr);
      if (d != null && a != null) {
        final diff = a.difference(d).inSeconds;
        return diff > 0 ? arrondirAuQuartDHeureSecondes(diff, toujoursPlusHaut: true) : 0;
      }
    }
    return 0;
  }

  int get _secondesChantierLive {
    final arriveeStr = (widget.intervention['heure_arrivee_site'] ??
        widget.intervention['heure_debut_redaction_rapport']) as String?;
    int pauseChantierSec = (widget.intervention['duree_pause_chantier_secondes'] is num)
        ? (widget.intervention['duree_pause_chantier_secondes'] as num).toInt()
        : 0;
    if ((widget.intervention['en_pause_chantier'] == true ||
            widget.intervention['statut'] == 'Intervention en pause') &&
        widget.intervention['heure_debut_pause_chantier'] != null) {
      final debutPause = DateTime.tryParse(widget.intervention['heure_debut_pause_chantier'].toString());
      if (debutPause != null) {
        pauseChantierSec += DateTime.now().toUtc().difference(debutPause.isUtc ? debutPause : debutPause.toUtc()).inSeconds;
      }
    }
    return calculerSecondesEcoulees(arriveeStr, pauseSec: pauseChantierSec);
  }

  int get _secondesChantierArrondi {
    final live = _secondesChantierLive;
    if (live <= 0) return 0;
    return arrondirAuQuartDHeureSecondes(live, toujoursPlusHaut: true);
  }

  int get _secondesRetour {
    if (_retourAjusteManuellement) return _secondesRetourCustom;
    if (_secondesRetourCustom > 0) return _secondesRetourCustom;
    final it = widget.intervention;
    if (it['duree_retour_secondes'] is num && (it['duree_retour_secondes'] as num) > 0) {
      return (it['duree_retour_secondes'] as num).toInt();
    }
    if (it['duree_retour'] != null) {
      final s = dureeChaineVersSecondes(it['duree_retour']);
      if (s > 0) return s;
    }
    return _secondesTrajetAller;
  }

  int get _secondesTotalFacturable =>
      _secondesTrajetAller + _secondesChantierArrondi + _secondesRetour;


  String _formatChrono(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  void initState() {
    super.initState();

    // Démarrage du chronomètre en direct
    _liveTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });

    final it = widget.intervention;

    // Initialisation trajet retour & km
    final trajetSec = (it['duree_trajet_secondes'] is num)
        ? (it['duree_trajet_secondes'] as num).toInt()
        : dureeChaineVersSecondes(it['duree_trajet']);
    if (it['duree_retour_secondes'] is num && (it['duree_retour_secondes'] as num) > 0) {
      _secondesRetourCustom = (it['duree_retour_secondes'] as num).toInt();
      _retourAjusteManuellement = it['retour_ajuste'] == true;
    } else if (it['duree_retour'] != null) {
      _secondesRetourCustom = dureeChaineVersSecondes(it['duree_retour']);
      _retourAjusteManuellement = it['retour_ajuste'] == true;
    } else {
      _secondesRetourCustom = trajetSec > 0 ? trajetSec : 0;
    }

    final distAller = (it['distance_km'] ?? '').toString();
    final distRetour = (it['distance_retour_km'] ?? distAller).toString();
    _distanceRetourCtrl.text = distRetour;

    if (widget.intervention['photos'] != null) {
      try {
        final dynamic raw = widget.intervention['photos'];
        if (raw is List) {
          _photos.addAll(raw.map((e) => e.toString()));
        } else if (raw is String && raw.isNotEmpty) {
          final decoded = jsonDecode(raw);
          if (decoded is List) {
            _photos.addAll(decoded.map((e) => e.toString()));
          }
        }
      } catch (e) {
        debugPrint('Erreur chargement photos: $e');
      }
    }

    final existingNotes = (widget.intervention['notes'] ?? '').toString();
    final cleanNotes = existingNotes
        .replaceAll(RegExp(r'\[RETOUR:[^\]]+\]'), '')
        .replaceAll(RegExp(r'\[CONTROLES:[^\]]+\]'), '')
        .replaceAll(RegExp(r'\[SUPERVISEUR:[^\]]+\]'), '')
        .trim();
    if (cleanNotes.isNotEmpty) {
      _notesController.text = cleanNotes;
    }
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    _sigController.dispose();
    _notesController.dispose();
    _distanceRetourCtrl.dispose();
    super.dispose();
  }

  Future<void> _capturerPhoto(ImageSource source) async {
    try {
      final List<String> sourcePaths = [];

      if (isWindowsDesktop) {
        // Sur Windows Desktop : Utiliser FilePicker natif (retourne une liste de fichiers)
        final files = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'bmp', 'heic'],
          dialogTitle: 'Sélectionner des photos pour le rapport',
        );
        if (files.isNotEmpty) {
          for (final f in files) {
            if (f.path != null && f.path!.isNotEmpty) {
              sourcePaths.add(f.path!);
            }
          }
        }
      } else {
        // Sur mobile / Android :
        // Pour la galerie, utiliser pickMultiImage() pour sélectionner plusieurs photos à la fois
        final picker = ImagePicker();
        if (source == ImageSource.gallery) {
          final List<XFile> images = await picker.pickMultiImage(
            maxWidth: 1920,
            maxHeight: 1080,
            imageQuality: 85,
          );
          for (final img in images) {
            if (img.path.isNotEmpty) {
              sourcePaths.add(img.path);
            }
          }
        } else {
          // Pour la caméra : prise photo unique
          final XFile? image = await picker.pickImage(
            source: ImageSource.camera,
            maxWidth: 1920,
            maxHeight: 1080,
            imageQuality: 85,
          );
          if (image != null && image.path.isNotEmpty) {
            sourcePaths.add(image.path);
          }
        }
      }

      if (sourcePaths.isEmpty) return;

      final numDossier = getNumeroDossier(widget.intervention);
      int ajoutes = 0;

      for (final src in sourcePaths) {
        final savedPath = await enregistrerPhotoDepuisChemin(
          sourcePath: src,
          numeroCommande: numDossier,
        );
        if (savedPath != null && !_photos.contains(savedPath)) {
          _photos.add(savedPath);
          ajoutes++;
        }
      }

      if (ajoutes > 0) {
        setState(() {
          widget.intervention['photos'] = jsonEncode(_photos);
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isWindowsDesktop
                    ? '📸 $ajoutes photo(s) enregistrée(s) dans Pictures\\$numDossier'
                    : '📸 $ajoutes photo(s) enregistrée(s) avec succès !',
              ),
              backgroundColor: Colors.green.shade700,
              duration: const Duration(seconds: 2),
              action: isWindowsDesktop
                  ? SnackBarAction(
                      label: 'Ouvrir',
                      textColor: Colors.white,
                      onPressed: () => ouvrirDossierPhotos(numDossier),
                    )
                  : null,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Erreur capture photo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur photo: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> soumettreRapport({bool demanderSignatureDistance = false}) async {
    if (!demanderSignatureDistance && _sigController.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Signature client requise (ou choisissez la signature à distance).')),
      );
      return;
    }
    setState(() => _isUploading = true);

    // Exportation de la signature sur place (si renseignée)
    Uint8List? sigBytes;
    if (_sigController.isNotEmpty) {
      sigBytes = await _sigController.toPngBytes();
    }
    final String? sigBase64 = sigBytes != null ? base64Encode(sigBytes) : null;

    final now = DateTime.now().toUtc();
    final arriveeStr = widget.intervention['heure_arrivee_site'] as String?;
    final debutRedactionStr = widget.intervention['heure_debut_redaction_rapport'] as String?;

    int pauseChantierSec = (widget.intervention['duree_pause_chantier_secondes'] is num)
        ? (widget.intervention['duree_pause_chantier_secondes'] as num).toInt()
        : 0;
    if ((widget.intervention['en_pause_chantier'] == true ||
            widget.intervention['statut'] == 'Intervention en pause') &&
        widget.intervention['heure_debut_pause_chantier'] != null) {
      final debut = DateTime.tryParse(
          widget.intervention['heure_debut_pause_chantier'].toString());
      if (debut != null) {
        pauseChantierSec += DateTime.now().toUtc().difference(debut.isUtc ? debut : debut.toUtc()).inSeconds;
      }
    }

    int totalChantierSec = calculerSecondesEcoulees(arriveeStr ?? debutRedactionStr, pauseSec: pauseChantierSec);
    // RÈGLE : TOUJOURS ARR ONDIR LE TEMPS CHANTIER AU QUART D'HEURE SUPÉRIEUR (PLUS HAUT)
    final totalChantierSecArrondi = arrondirAuQuartDHeureSecondes(
        totalChantierSec > 0 ? totalChantierSec : 60,
        toujoursPlusHaut: true);
    final dureeChantierStr = formatSeconds(totalChantierSecArrondi);

    // Durée dédiée à la rédaction du rapport jusqu'à la signature
    int dureeRedactionSec = 0;
    if (debutRedactionStr != null) {
      dureeRedactionSec = calculerSecondesEcoulees(debutRedactionStr);
    }

    final totalFacturableSec = _secondesTotalFacturable;
    final dureeTotaleFacturableStr = formatSeconds(totalFacturableSec);

    final String userNotes = _notesController.text.trim();
    final String existingNotes = (widget.intervention['notes'] ?? '').toString();
    final cleanExistingNotes = existingNotes
        .replaceAll(RegExp(r'\[RETOUR:[^\]]+\]'), '')
        .replaceAll(RegExp(r'\[CONTROLES:[^\]]+\]'), '')
        .replaceAll(RegExp(r'\[SUPERVISEUR:[^\]]+\]'), '')
        .trim();
    final String baseNotes = userNotes.isNotEmpty
        ? userNotes
        : (cleanExistingNotes.isNotEmpty ? cleanExistingNotes : 'Travaux effectués avec succès. Validation client effectuée.');
    final distRetour = _distanceRetourCtrl.text.trim().isNotEmpty
        ? _distanceRetourCtrl.text.trim()
        : (widget.intervention['distance_retour_km'] ??
            widget.intervention['distance_km'] ??
            '--').toString();
    final retourTag = '[RETOUR: ${formatSeconds(_secondesRetour)} | $distRetour]';

    // Conserver la liste exacte des contrôles de sécurité effectivement validés
    final controles = getControlesSecurite(widget.intervention);
    final controlesTag = '[CONTROLES: ${jsonEncode(controles)}]';

    String notesFinales = baseNotes;
    if (notesFinales.contains('[RETOUR:')) {
      notesFinales = notesFinales.replaceAll(RegExp(r'\[RETOUR:[^\]]+\]'), retourTag);
    } else {
      notesFinales = '$notesFinales\n$retourTag';
    }

    if (notesFinales.contains('[CONTROLES:')) {
      notesFinales = notesFinales.replaceAll(RegExp(r'\[CONTROLES:[^\]]+\]'), controlesTag);
    } else {
      notesFinales = '$notesFinales\n$controlesTag';
    }

    if (existingNotes.contains('[SUPERVISEUR:')) {
      final supMatch = RegExp(r'\[SUPERVISEUR:[^\]]+\]').firstMatch(existingNotes);
      if (supMatch != null && !notesFinales.contains('[SUPERVISEUR:')) {
        notesFinales = '$notesFinales\n${supMatch.group(0)}';
      }
    }

    final Map<String, dynamic> updates = {
      'statut': 'En attente d\'approbation',
      'approuve_par_superviseur': false,
      'pieces_deduites': false,
      'en_pause': false,
      'en_pause_chantier': false,
      'heure_cloture': now.toIso8601String(),
      'duree_chantier': dureeChantierStr,
      'duree_chantier_secondes': totalChantierSecArrondi,
      'duree_redaction_secondes': dureeRedactionSec,
      'duree_pause_chantier_secondes': pauseChantierSec,
      'duree_retour': formatSeconds(_secondesRetour),
      'duree_retour_secondes': _secondesRetour,
      'distance_retour_km': distRetour,
      'retour_ajuste': _retourAjusteManuellement,
      'duree_totale_facturable': dureeTotaleFacturableStr,
      'duree_totale_facturable_secondes': totalFacturableSec,
      'controles_securite': jsonEncode(controles),
      'notes': notesFinales,
      'photos': jsonEncode(_photos),
      'updated_at': now.toIso8601String(),
    };
    if (sigBase64 != null) {
      updates['signature'] = sigBase64;
      updates['heure_signature'] = now.toIso8601String();
    } else if (demanderSignatureDistance) {
      final token = SignatureDistanceService.genererTokenSecurise();
      updates['signature_token'] = token;
      updates['signature_a_distance_demandee'] = true;
      updates['notes'] = '$notesFinales\n[SIG_TOKEN: $token]\n[SIG_DISTANTE: OUI]';
    } else if (widget.intervention['heure_signature'] != null) {
      updates['heure_signature'] = widget.intervention['heure_signature'];
    }
    for (final k in [
      'pieces_utilisees', 'controles_securite', 'numero_rapport', 'marque', 'modele', 'annee',
      'numero_serie_machine', 'numero_unite', 'type_intervention', 'type_machine',
      'alimentation', 'numero_produit', 'numero_serie_systeme',
      'version_logiciel', 'engrenage', 'position_bypass', 'adresse_facturation',
      'nom_contact', 'telephone', 'courriel', 'numero_reference', 'numero_bon_commande'
    ]) {
      if (widget.intervention[k] != null) {
        updates[k] = widget.intervention[k];
      }
    }

    try {
      final supabase = Supabase.instance.client;
      final clean = <String, dynamic>{};
      for (final entry in updates.entries) {
        if (kColonnesInterventionsSupabase.contains(entry.key)) {
          clean[entry.key] = entry.value;
        }
      }
      await supabase
          .from('interventions')
          .update(clean)
          .eq('id', widget.intervention['id']);
    } catch (e) {
      debugPrint('Mise à jour Supabase: $e');
    }

    widget.intervention.addAll(updates);
    try {
      await FeuilleDeTempsRepository.instance.synchroniserIntervention(widget.intervention);
    } catch (_) {}

    // 📄 Génération et sauvegarde automatique du rapport PDF officiel RaycoWylie sur Windows
    String? cheminPdfGenere;
    try {
      cheminPdfGenere = await RapportPdfService.genererEtSauvegarderAutomatiquement(
        intervention: widget.intervention,
        getNumeroDossier: getNumeroDossier,
        getDossierPhotos: getDossierPhotos,
        formatSeconds: formatSeconds,
        formatHeure: formatHeure,
      );
      if (cheminPdfGenere != null) {
        widget.intervention['rapport_pdf_path'] = cheminPdfGenere;
      }
    } catch (e) {
      debugPrint('Erreur génération automatique PDF lors de la clôture: $e');
    }

    if (!mounted) return;
    setState(() => _isUploading = false);

    if (cheminPdfGenere != null && isWindowsDesktop) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⏳ Rapport soumis ! En attente de l\'approbation du superviseur pour conformité et déduction des pièces.\nPDF : $cheminPdfGenere'),
          backgroundColor: Colors.amber.shade900,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Ouvrir',
            textColor: Colors.white,
            onPressed: () => RapportPdfService.ouvrirFichier(cheminPdfGenere!),
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('⏳ Rapport soumis ! En attente de l\'approbation du superviseur.'),
          backgroundColor: Colors.amber.shade900,
          duration: const Duration(seconds: 3),
        ),
      );
    }

    // Ouvre immédiatement le rapport généré pour consultation
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => RapportDetailScreen(
          intervention: widget.intervention,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final numDossier = getNumeroDossier(widget.intervention);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fermeture de Fiche',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFFD1001F),
      ),
      body: _isUploading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(14.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.business, color: Colors.blueAccent, size: 28),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.intervention['nom_client'] ?? '',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                                ),
                                if (widget.intervention['adresse_facturation'] != null &&
                                    (widget.intervention['adresse_facturation'] as String).trim().isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.receipt_long, color: Colors.indigo, size: 15),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          'Facturation : ${widget.intervention['adresse_facturation']}',
                                          style: TextStyle(
                                            color: Colors.indigo.shade800,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                const SizedBox(height: 3),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.location_on, color: Colors.grey, size: 15),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        'Chantier : ${widget.intervention['adresse'] ?? ''}',
                                        style: const TextStyle(color: Colors.grey, fontSize: 13),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ─── Photos de chantier ────────────────────────
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(14.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.photo_camera, color: Colors.blueAccent, size: 22),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Photos de Chantier (${_photos.length})',
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                    ),
                                    Text(
                                      'Dossier Windows : Pictures\\$numDossier',
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                    ),
                                  ],
                                ),
                              ),
                              if (isWindowsDesktop)
                                IconButton(
                                  icon: const Icon(Icons.folder_open, color: Colors.indigo),
                                  tooltip: 'Ouvrir le dossier dans Windows',
                                  onPressed: () => ouvrirDossierPhotos(numDossier),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: isWindowsDesktop
                                ? [
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.blueAccent,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(vertical: 10),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                        onPressed: () => _capturerPhoto(ImageSource.gallery),
                                        icon: const Icon(Icons.add_photo_alternate, size: 18),
                                        label: const Text('Choisir photo'),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.blueAccent,
                                          padding: const EdgeInsets.symmetric(vertical: 10),
                                          side: const BorderSide(color: Colors.blueAccent),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                        onPressed: () async {
                                          final cameraUri = Uri.parse('microsoft.windows.camera:');
                                          if (await canLaunchUrl(cameraUri)) {
                                            await launchUrl(cameraUri);
                                          } else {
                                            Process.run('cmd', ['/c', 'start', 'microsoft.windows.camera:'], runInShell: true);
                                          }
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                content: Text('📸 Caméra Windows ouverte. Après avoir pris la photo, cliquez sur "Choisir photo" pour l\'ajouter (dans Images > Pellicule).'),
                                                duration: Duration(seconds: 6),
                                              ),
                                            );
                                          }
                                        },
                                        icon: const Icon(Icons.camera_alt, size: 18),
                                        label: const Text('Caméra Windows'),
                                      ),
                                    ),
                                  ]
                                : [
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.blueAccent,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(vertical: 10),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                        onPressed: () => _capturerPhoto(ImageSource.camera),
                                        icon: const Icon(Icons.camera_alt, size: 18),
                                        label: const Text('Prendre photo'),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.blueAccent,
                                          padding: const EdgeInsets.symmetric(vertical: 10),
                                          side: const BorderSide(color: Colors.blueAccent),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                        onPressed: () => _capturerPhoto(ImageSource.gallery),
                                        icon: const Icon(Icons.photo_library, size: 18),
                                        label: const Text('Galerie'),
                                      ),
                                    ),
                                  ],
                          ),
                          if (_photos.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 110,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: _photos.length,
                                itemBuilder: (context, index) {
                                  final pPath = _photos[index];
                                  return Container(
                                    width: 110,
                                    margin: const EdgeInsets.only(right: 10),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.grey.shade300),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        buildImageFromPath(pPath, fit: BoxFit.cover, cacheWidth: 250),
                                        Positioned(
                                          top: 4,
                                          right: 4,
                                          child: GestureDetector(
                                            onTap: () {
                                              setState(() {
                                                _photos.removeAt(index);
                                                widget.intervention['photos'] = jsonEncode(_photos);
                                              });
                                            },
                                            child: Container(
                                              padding: const EdgeInsets.all(3),
                                              decoration: const BoxDecoration(
                                                color: Colors.black54,
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(Icons.close, color: Colors.white, size: 14),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Travaux effectués & Notes de service :',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _notesController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Ex: Réparation effectuée, câblage testé, système 100% opérationnel...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ⏱️ CHRONOMÈTRE DE FACTURATION (ACTIF JUSQU'À LA SIGNATURE)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.shade600, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.green.withValues(alpha: 0.1),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: Colors.green.shade100,
                              child: Icon(Icons.timer, color: Colors.green.shade800),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'TOTAL FACTURABLE GLOBAL CERTIFIÉ',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.baseline,
                                    textBaseline: TextBaseline.alphabetic,
                                    children: [
                                      Text(
                                        formatSeconds(_secondesTotalFacturable),
                                        style: TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'monospace',
                                          color: Colors.green.shade900,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.green.shade700,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          '1/4h sup.',
                                          style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green.shade200),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.directions_car, color: Colors.blueAccent, size: 15),
                                      const SizedBox(width: 6),
                                      Text('1. Trajet Aller : ${formatSeconds(_secondesTrajetAller)}',
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                  Text('${widget.intervention['distance_km'] ?? '--'}',
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                ],
                              ),
                              const Divider(height: 10),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.handyman, color: Colors.teal, size: 15),
                                      const SizedBox(width: 6),
                                      Text('2. Chantier & Rédaction : ${formatSeconds(_secondesChantierArrondi)}',
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                  Text('Live: ${_formatChrono(Duration(seconds: _secondesChantierLive))}',
                                      style: TextStyle(fontSize: 11, color: Colors.teal.shade800, fontFamily: 'monospace')),
                                ],
                              ),
                              const Divider(height: 10),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.rotate_right, color: Colors.orange, size: 15),
                                      const SizedBox(width: 6),
                                      Text(
                                        _retourAjusteManuellement
                                            ? '3. Trajet Retour (Ajusté) : ${formatSeconds(_secondesRetour)}'
                                            : '3. Trajet Retour (Estimé) : ${formatSeconds(_secondesRetour)}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: _retourAjusteManuellement ? Colors.orange.shade900 : Colors.black87,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton.filledTonal(
                                        visualDensity: VisualDensity.compact,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                        icon: const Icon(Icons.remove, size: 16),
                                        tooltip: 'Moins 15 minutes',
                                        onPressed: () {
                                          setState(() {
                                            _retourAjusteManuellement = true;
                                            _secondesRetourCustom = (_secondesRetour - 900).clamp(0, 86400);
                                          });
                                        },
                                      ),
                                      const SizedBox(width: 4),
                                      IconButton.filledTonal(
                                        visualDensity: VisualDensity.compact,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                        icon: const Icon(Icons.add, size: 16),
                                        tooltip: 'Plus 15 minutes',
                                        onPressed: () {
                                          setState(() {
                                            _retourAjusteManuellement = true;
                                            _secondesRetourCustom = (_secondesRetour + 900).clamp(0, 86400);
                                          });
                                        },
                                      ),
                                      if (_retourAjusteManuellement) ...[
                                        const SizedBox(width: 4),
                                        IconButton(
                                          visualDensity: VisualDensity.compact,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                          icon: const Icon(Icons.restart_alt, size: 16, color: Colors.grey),
                                          tooltip: 'Réinitialiser retour',
                                          onPressed: () {
                                            setState(() {
                                              _retourAjusteManuellement = false;
                                              _secondesRetourCustom = _secondesTrajetAller;
                                              _distanceRetourCtrl.text = (widget.intervention['distance_km'] ?? '--').toString();
                                            });
                                          },
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _distanceRetourCtrl,
                                style: const TextStyle(fontSize: 12),
                                decoration: InputDecoration(
                                  labelText: 'Kilométrage de retour (km)',
                                  hintText: 'Ex: 25 km',
                                  prefixIcon: const Icon(Icons.straighten, size: 16),
                                  isDense: true,
                                  filled: true,
                                  fillColor: Colors.grey.shade50,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                                ),
                                onChanged: (_) {
                                  setState(() => _retourAjusteManuellement = true);
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          '⏱️ Le temps continue d\'être calculé en direct jusqu\'à la signature ci-dessous.',
                          style: TextStyle(fontSize: 11, color: Colors.black87),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),
                  const Text(
                    'Signature du Client :',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Signature(
                      controller: _sigController,
                      height: 150,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.check),
                      onPressed: () => soumettreRapport(demanderSignatureDistance: false),
                      label: const Text(
                        'Valider avec Signature sur Place',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFD1001F),
                        side: const BorderSide(color: Color(0xFFD1001F), width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.send_to_mobile),
                      onPressed: () async {
                        // Partager le lien et soumettre la clôture
                        await SignatureDistanceService.afficherDialoguePartage(
                          context,
                          intervention: widget.intervention,
                        );
                        if (mounted) {
                          await soumettreRapport(demanderSignatureDistance: true);
                        }
                      },
                      label: const Text(
                        'Envoyer le Lien de Signature à Distance (SMS / Courriel)',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 50),
                ],
              ),
            ),
    );
  }
}
