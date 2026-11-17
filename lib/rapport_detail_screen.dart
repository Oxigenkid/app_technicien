import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_helpers.dart';
import 'feuille_de_temps.dart';
import 'inventaire_donnees.dart';
import 'techniciens_service.dart';
import 'nip_service.dart';
import 'rapport_pdf.dart';
import 'widget_photos_chantier.dart';
import 'signature_distance_service.dart';
import 'package:flutter_svg/flutter_svg.dart';

// ==========================================
// 📄 ÉCRAN : DÉTAIL DU RAPPORT D'INTERVENTION
// ==========================================
class RapportDetailScreen extends StatefulWidget {
  final Map<String, dynamic> intervention;
  const RapportDetailScreen({super.key, required this.intervention});

  @override
  State<RapportDetailScreen> createState() => _RapportDetailScreenState();
}

class _RapportDetailScreenState extends State<RapportDetailScreen> {
  String? _pdfCheminLocal;
  bool _isGeneratingPdf = false;

  @override
  void initState() {
    super.initState();
    _verifierPdfExistant();
  }

  void _verifierPdfExistant() {
    if (!isWindowsDesktop) return;
    _pdfCheminLocal = widget.intervention['rapport_pdf_path'] as String?;
    if (_pdfCheminLocal != null && File(_pdfCheminLocal!).existsSync()) {
      return;
    }

    final numDossier = getNumeroDossier(widget.intervention);
    final numRapport = widget.intervention['numero_rapport'] ?? 'Rapport';
    final cleanNumRapport = numRapport.toString().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final cleanClient = (widget.intervention['nom_client'] ?? 'Client')
        .toString()
        .trim()
        .replaceAll('&', 'et')
        .replaceAll(RegExp(r'[\\/:*?"<>| ]'), '_');
    final expectedPdfName = 'Rapport_${cleanNumRapport}_$cleanClient.pdf';

    final dossierPhotos = getDossierPhotos(numDossier);
    if (dossierPhotos != null && dossierPhotos.existsSync()) {
      final f = File('${dossierPhotos.path}\\$expectedPdfName');
      final fAlt = File('${dossierPhotos.path}\\Rapport_$cleanNumRapport.pdf');
      if (f.existsSync()) {
        _pdfCheminLocal = f.path;
      } else if (fAlt.existsSync()) {
        _pdfCheminLocal = fAlt.path;
      } else {
        try {
          final matches = dossierPhotos.listSync().whereType<File>().where((file) {
            final name = file.uri.pathSegments.last;
            return name.startsWith('Rapport_$cleanNumRapport') && name.endsWith('.pdf');
          });
          if (matches.isNotEmpty) {
            _pdfCheminLocal = matches.first.path;
          }
        } catch (_) {}
      }
    }

    if (_pdfCheminLocal == null) {
      try {
        final userProfile = Platform.environment['USERPROFILE'] ?? 'C:\\Users\\Default';
        final dirDocs = Directory('$userProfile\\Documents\\Rapports_Rayco');
        if (dirDocs.existsSync()) {
          final fDocs = File('${dirDocs.path}\\$expectedPdfName');
          if (fDocs.existsSync()) {
            _pdfCheminLocal = fDocs.path;
          } else {
            final matches = dirDocs.listSync().whereType<File>().where((file) {
              final name = file.uri.pathSegments.last;
              return name.startsWith('Rapport_$cleanNumRapport') && name.endsWith('.pdf');
            });
            if (matches.isNotEmpty) {
              _pdfCheminLocal = matches.first.path;
            }
          }
        }
      } catch (_) {}
    }
  }

  Future<void> _genererPdfMaintenant() async {
    setState(() => _isGeneratingPdf = true);
    try {
      final path = await RapportPdfService.genererEtSauvegarderAutomatiquement(
        intervention: widget.intervention,
        getNumeroDossier: getNumeroDossier,
        getDossierPhotos: getDossierPhotos,
        formatSeconds: formatSeconds,
        formatHeure: formatHeure,
      );
      if (mounted) {
        setState(() {
          _pdfCheminLocal = path;
          widget.intervention['rapport_pdf_path'] = path;
          _isGeneratingPdf = false;
        });
        if (path != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Rapport PDF généré avec succès dans :\n$path'),
              backgroundColor: Colors.green.shade800,
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: 'Ouvrir',
                textColor: Colors.white,
                onPressed: () => RapportPdfService.ouvrirFichier(path),
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isGeneratingPdf = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur génération PDF : $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _approuverParSuperviseur() async {
    final intervention = widget.intervention;

    // Récupérer les pièces utilisées
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

    final techniciensDispos = TechnicienService.instance.techniciens;
    String supervisorName = techniciensDispos.isNotEmpty
        ? techniciensDispos.first.nom
        : 'Superviseur Rayco Wylie';
    final supervisorCtrl = TextEditingController(text: supervisorName);
    final nipCtrl = TextEditingController();
    bool obscureNip = true;
    String? errorMessage;

    // Charger les contrôles existants ou pré-cocher pour l'approbation conforme
    final controlesExistants = getControlesSecurite(intervention);
    final List<String> controlesSelectionnes = controlesExistants.isNotEmpty
        ? List<String>.from(controlesExistants)
        : List<String>.from(kControlesSecuriteStandards);

    final bool? confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDlgState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: Row(
              children: [
                const Icon(Icons.verified_user, color: Color(0xFFD1001F), size: 24),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Apposer le Tampon Superviseur',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 550, maxHeight: 650),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'En tant que superviseur, vous certifiez la conformité de ce rapport aux normes RaycoWylie Systems. '
                      'La checklist sera validée et les pièces indiquées ci-dessous seront déduites de l\'inventaire.',
                      style: TextStyle(fontSize: 12.5, color: Colors.black87),
                    ),
                    const SizedBox(height: 12),

                    // 1. NOM DU SUPERVISEUR
                    const Text(
                      'Nom du superviseur approuveur :',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 5),
                    if (techniciensDispos.isNotEmpty) ...[
                      DropdownButtonFormField<String>(
                        initialValue: techniciensDispos.any((t) => t.nom == supervisorCtrl.text)
                            ? supervisorCtrl.text
                            : techniciensDispos.first.nom,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.person),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: techniciensDispos.map((t) {
                          return DropdownMenuItem<String>(
                            value: t.nom,
                            child: Text('${t.nom} (${t.numeroCamion})', style: const TextStyle(fontSize: 13)),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDlgState(() {
                              supervisorCtrl.text = val;
                              nipCtrl.clear();
                              errorMessage = null;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 10),
                    ] else ...[
                      TextField(
                        controller: supervisorCtrl,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.badge),
                          border: OutlineInputBorder(),
                          isDense: true,
                          hintText: 'Nom du superviseur',
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],

                    // 2. CODE NIP DU SUPERVISEUR (OBLIGATOIRE)
                    const Text(
                      'Code NIP de sécurité du superviseur * :',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 5),
                    TextField(
                      controller: nipCtrl,
                      obscureText: obscureNip,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      decoration: InputDecoration(
                        labelText: 'NIP à 4 chiffres',
                        prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFFD1001F)),
                        suffixIcon: IconButton(
                          icon: Icon(obscureNip ? Icons.visibility_off : Icons.visibility, size: 20),
                          onPressed: () => setDlgState(() => obscureNip = !obscureNip),
                        ),
                        border: const OutlineInputBorder(),
                        isDense: true,
                        counterText: '',
                        hintText: 'NIP requis (ex: 9999 ou NIP superviseur)',
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 3. CHECKLIST DE CONFORMITÉ & CONTRÔLE DE SÉCURITÉ
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(color: Colors.green.shade400, width: 1.2),
                      ),
                      color: Colors.green.shade50.withValues(alpha: 0.5),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      Icon(Icons.checklist_rtl, size: 18, color: Colors.green.shade900),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Checklist d\'approbation & conformité :',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12.5,
                                          color: Colors.green.shade900,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade200,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${controlesSelectionnes.length} / ${kControlesSecuriteStandards.length} cochés',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                      color: Colors.green.shade900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton.icon(
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  icon: const Icon(Icons.done_all, size: 14),
                                  label: const Text('Tout cocher (Conforme)', style: TextStyle(fontSize: 11)),
                                  onPressed: () {
                                    setDlgState(() {
                                      controlesSelectionnes.clear();
                                      controlesSelectionnes.addAll(kControlesSecuriteStandards);
                                    });
                                  },
                                ),
                                TextButton.icon(
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    visualDensity: VisualDensity.compact,
                                    foregroundColor: Colors.grey.shade700,
                                  ),
                                  icon: const Icon(Icons.clear_all, size: 14),
                                  label: const Text('Tout décocher', style: TextStyle(fontSize: 11)),
                                  onPressed: () {
                                    setDlgState(() {
                                      controlesSelectionnes.clear();
                                    });
                                  },
                                ),
                              ],
                            ),
                            const Divider(height: 10),
                            ...kControlesSecuriteStandards.map((item) {
                              final isChecked = controlesSelectionnes.contains(item);
                              return CheckboxListTile(
                                dense: true,
                                controlAffinity: ListTileControlAffinity.leading,
                                contentPadding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                                activeColor: const Color(0xFF1B5E20),
                                title: Text(
                                  item,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: isChecked ? FontWeight.w600 : FontWeight.normal,
                                    color: isChecked ? Colors.black87 : Colors.black45,
                                  ),
                                ),
                                value: isChecked,
                                onChanged: (val) {
                                  setDlgState(() {
                                    if (val == true) {
                                      if (!controlesSelectionnes.contains(item)) {
                                        controlesSelectionnes.add(item);
                                      }
                                    } else {
                                      controlesSelectionnes.remove(item);
                                    }
                                  });
                                },
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // 4. RÉCAPITULATIF DES PIÈCES À DÉDUIRE
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.shade400),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.inventory_2, size: 16, color: Colors.amber.shade900),
                              const SizedBox(width: 6),
                              Text(
                                'Déduction d\'inventaire (${pieces.length} pièce(s)) :',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: Colors.amber.shade900,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          if (pieces.isEmpty)
                            const Text(
                              '• Aucune pièce à déduire (main-d\'oeuvre / calibration uniquement)',
                              style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
                            )
                          else
                            ...pieces.map((p) => Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: Text(
                                    '• ${p['ref'] ?? p['reference'] ?? 'Pièce'} (${p['designation'] ?? p['nom'] ?? 'Composante'}) : Qté ${p['utilise'] ?? p['quantite'] ?? 1}',
                                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500),
                                  ),
                                )),
                        ],
                      ),
                    ),
                    if (errorMessage != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.red.shade300),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, color: Colors.red, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                errorMessage!,
                                style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuler'),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD1001F),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
                icon: const Icon(Icons.approval, size: 18),
                label: const Text('Apposer le Tampon & Déclarer Conforme'),
                onPressed: () async {
                  final nom = supervisorCtrl.text.trim();
                  if (nom.isEmpty) {
                    setDlgState(() => errorMessage = 'Veuillez renseigner le nom du superviseur.');
                    return;
                  }
                  final nipSaisi = nipCtrl.text.trim();
                  if (nipSaisi.length != 4) {
                    setDlgState(() => errorMessage = 'Le code NIP doit comporter exactement 4 chiffres.');
                    return;
                  }

                  // Vérification du NIP
                  final bool estValide = await NipSecuriteService.instance.verifierNip(nom, nipSaisi);
                  if (!dialogCtx.mounted) return;

                  if (!estValide) {
                    setDlgState(() {
                      errorMessage = 'Code NIP incorrect pour $nom. (Passe-partout : 9999)';
                    });
                    return;
                  }

                  Navigator.pop(ctx, true);
                },
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true) return;

    final nomSuperviseurFinal = supervisorCtrl.text.trim().isNotEmpty
        ? supervisorCtrl.text.trim()
        : 'Superviseur Rayco Wylie';
    final now = DateTime.now().toUtc();
    final dateStr = now.toIso8601String().substring(0, 16).replaceAll('T', ' ');

    setState(() => _isGeneratingPdf = true);

    try {
      // 1. Déduction des pièces de l'inventaire du camion
      if (pieces.isNotEmpty && intervention['pieces_deduites'] != true) {
        InventaireService.instance.deduirePieces(
          pieces,
          camion: intervention['numero_camion']?.toString(),
          technicien: intervention['nom_technicien']?.toString(),
        );
      }

      // 2. Mettre à jour l'intervention avec le tampon et la checklist validée
      intervention['controles_securite'] = controlesSelectionnes;
      final tagControles = '[CONTROLES: ${jsonEncode(controlesSelectionnes)}]';

      final baseNotes = (intervention['notes'] ?? '').toString();
      final tagApprobation = '[SUPERVISEUR: APPROUVÉ le $dateStr par $nomSuperviseurFinal]';
      String notesFinales = baseNotes;
      if (notesFinales.contains('[SUPERVISEUR:')) {
        notesFinales = notesFinales.replaceAll(RegExp(r'\[SUPERVISEUR:[^\]]+\]'), tagApprobation);
      } else {
        notesFinales = notesFinales.isNotEmpty ? '$notesFinales\n$tagApprobation' : tagApprobation;
      }

      notesFinales = notesFinales
          .replaceAll(RegExp(r'\[CONTROLES:\s*\[[\s\S]*?\]\s*\]'), '')
          .replaceAll(RegExp(r'\[CONTROLES:[^\]]+\]'), '')
          .trim();
      notesFinales = '$notesFinales\n$tagControles';

      final updates = <String, dynamic>{
        'statut': 'Complété',
        'notes': notesFinales,
        'controles_securite': List<String>.from(controlesSelectionnes),
        'updated_at': now.toIso8601String(),
      };

      try {
        final supabase = Supabase.instance.client;
        final clean = <String, dynamic>{};
        for (final entry in updates.entries) {
          if (kColonnesInterventionsSupabase.contains(entry.key)) {
            clean[entry.key] = entry.value;
          }
        }
        await supabase.from('interventions').update(clean).eq('id', intervention['id']);
      } catch (e) {
        debugPrint('Erreur mise à jour Supabase approbation: $e');
      }

      intervention.addAll(updates);
      intervention['controles_securite'] = List<String>.from(controlesSelectionnes);
      intervention['approuve_par_superviseur'] = true;
      intervention['nom_superviseur'] = nomSuperviseurFinal;
      intervention['date_approbation_superviseur'] = now.toIso8601String();
      intervention['pieces_deduites'] = true;

      try {
        await FeuilleDeTempsRepository.instance.synchroniserIntervention(intervention);
      } catch (_) {}

      // 3. Regénérer le rapport PDF avec le tampon apposé et la checklist cochée
      final nouveauPdfPath = await RapportPdfService.genererEtSauvegarderAutomatiquement(
        intervention: intervention,
        getNumeroDossier: getNumeroDossier,
        getDossierPhotos: getDossierPhotos,
        formatSeconds: formatSeconds,
        formatHeure: formatHeure,
      );

      if (mounted) {
        setState(() {
          _isGeneratingPdf = false;
          _pdfCheminLocal = nouveauPdfPath;
          if (nouveauPdfPath != null) {
            intervention['rapport_pdf_path'] = nouveauPdfPath;
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Tampon apposé par $nomSuperviseurFinal !\nChecklist validée conforme et pièces déduites du camion.'),
            backgroundColor: Colors.green.shade800,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isGeneratingPdf = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de l\'approbation : $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Widget _buildCarteApprobationSuperviseur() {
    final bool estApprouve = estRapportApprouve(widget.intervention);
    final nomSuperviseur = getNomSuperviseur(widget.intervention);
    final dateApprobation = getDateApprobationSuperviseur(widget.intervention);

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: estApprouve ? Colors.green.shade600 : Colors.amber.shade700,
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      estApprouve ? Icons.verified : Icons.admin_panel_settings,
                      color: estApprouve ? Colors.green.shade800 : Colors.amber.shade900,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '🛡️ Approbation Superviseur',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: estApprouve ? Colors.green.shade900 : Colors.amber.shade900,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: estApprouve ? Colors.green.shade100 : Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    estApprouve ? 'APPROUVÉ & CONFORME' : 'EN ATTENTE D\'APPROBATION',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: estApprouve ? Colors.green.shade900 : Colors.amber.shade900,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            if (estApprouve) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade300, width: 1.2),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.green.shade700,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.done_all, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'RAPPORT DÉCLARÉ CONFORME & VALIDÉ',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Color(0xFF1B5E20),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text('Superviseur : $nomSuperviseur',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          Text('Approuvé le : $dateApprobation',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.check_circle, size: 14, color: Colors.green.shade700),
                              const SizedBox(width: 4),
                              Text(
                                'Pièces déduites de l\'inventaire du camion',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.green.shade800,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(Icons.checklist, size: 14, color: Colors.green.shade700),
                              const SizedBox(width: 4),
                              Text(
                                'Checklist de conformité validée (${getControlesSecurite(widget.intervention).length}/${kControlesSecuriteStandards.length} points)',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.green.shade800,
                                  fontWeight: FontWeight.w600,
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
            ] else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade400),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.hourglass_top, color: Colors.amber.shade900, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          'Intervention terminée en attente de validation',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Colors.amber.shade900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Ce rapport a été clôturé et signé par le client. Conformément à la procédure de contrôle, '
                      'les pièces d\'inventaire restent réservées et ne sont pas encore déduites.\n'
                      'L\'approbation formelle du superviseur est requise pour apposer le tampon officiel, déclarer le rapport conforme et déduire les pièces du camion.',
                      style: TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFD1001F),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.approval, size: 18),
                        label: const Text(
                          'Apposer le Tampon Superviseur & Valider la Conformité',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        onPressed: _approuverParSuperviseur,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _afficherDialogueModifierNotes() async {
    final bool estApprouve = estRapportApprouve(widget.intervention);
    await WidgetPhotosChantier.afficherDialogueNotesDeService(
      context,
      intervention: widget.intervention,
      lectureSeule: estApprouve,
      onNotesSauvegardees: (nouvellesNotes) async {
        setNotesDeService(widget.intervention, nouvellesNotes);

        // 1. Sauvegarder dans Supabase
        try {
          final supabase = Supabase.instance.client;
          await supabase.from('interventions').update({
            'notes': widget.intervention['notes'],
          }).eq('id', widget.intervention['id']);
        } catch (e) {
          debugPrint('Erreur mise à jour notes Supabase: $e');
        }

        // 2. Synchroniser localement
        try {
          await FeuilleDeTempsRepository.instance.synchroniserIntervention(widget.intervention);
        } catch (_) {}

        // 3. Regénérer le rapport PDF automatiquement
        setState(() => _isGeneratingPdf = true);
        final nouveauPdfPath = await RapportPdfService.genererEtSauvegarderAutomatiquement(
          intervention: widget.intervention,
          getNumeroDossier: getNumeroDossier,
          getDossierPhotos: getDossierPhotos,
          formatSeconds: formatSeconds,
          formatHeure: formatHeure,
        );

        if (mounted) {
          setState(() {
            _isGeneratingPdf = false;
            _pdfCheminLocal = nouveauPdfPath;
            if (nouveauPdfPath != null) {
              widget.intervention['rapport_pdf_path'] = nouveauPdfPath;
            }
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Notes de service enregistrées et PDF actualisé.'),
              backgroundColor: Colors.indigo,
            ),
          );
        }
      },
    );
  }

  Widget _buildCartePhotos() {
    final bool estApprouve = estRapportApprouve(widget.intervention);
    return WidgetPhotosChantier(
      intervention: widget.intervention,
      lectureSeule: estApprouve,
      onPhotosModifiees: () async {
        // 1. Sauvegarder dans Supabase
        try {
          final supabase = Supabase.instance.client;
          await supabase.from('interventions').update({
            'photos': widget.intervention['photos'],
          }).eq('id', widget.intervention['id']);
        } catch (e) {
          debugPrint('Erreur mise à jour photos Supabase: $e');
        }

        // 2. Synchroniser localement
        try {
          await FeuilleDeTempsRepository.instance.synchroniserIntervention(widget.intervention);
        } catch (_) {}

        // 3. Regénérer le rapport PDF avec les nouvelles photos
        final nouveauPdfPath = await RapportPdfService.genererEtSauvegarderAutomatiquement(
          intervention: widget.intervention,
          getNumeroDossier: getNumeroDossier,
          getDossierPhotos: getDossierPhotos,
          formatSeconds: formatSeconds,
          formatHeure: formatHeure,
        );

        if (mounted) {
          setState(() {
            _pdfCheminLocal = nouveauPdfPath;
            if (nouveauPdfPath != null) {
              widget.intervention['rapport_pdf_path'] = nouveauPdfPath;
            }
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final intervention = widget.intervention;
    final bool estApprouve = estRapportApprouve(intervention);
    final signatureBase64 = intervention['signature'] as String?;
    final cleanNotes = getNotesDeService(intervention);
    final notes = cleanNotes.isNotEmpty ? cleanNotes : 'Travaux terminés avec succès.';
    final heureDepart = intervention['heure_depart_trajet'] != null
        ? DateTime.tryParse(intervention['heure_depart_trajet'].toString())
            ?.toLocal()
            .toString()
            .substring(11, 16)
        : '--:--';
    final heureArrivee = intervention['heure_arrivee_site'] != null
        ? DateTime.tryParse(intervention['heure_arrivee_site'].toString())
            ?.toLocal()
            .toString()
            .substring(11, 16)
        : '--:--';

    // Décode les pièces utilisées
    List<Map<String, dynamic>> piecesUtilisees = [];
    try {
      final piecesJson = intervention['pieces_utilisees'] as String?;
      if (piecesJson != null && piecesJson.isNotEmpty) {
        final decoded = jsonDecode(piecesJson) as List;
        piecesUtilisees = decoded.cast<Map<String, dynamic>>();
      }
    } catch (_) {}

    // Décode les contrôles de sécurité effectivement cochés
    final List<String> controlesSecurite = getControlesSecurite(intervention);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Rapport d\'Intervention',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            if (intervention['numero_rapport'] != null)
              Text(
                'Nº ${intervention['numero_rapport']}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
          ],
        ),
        backgroundColor: const Color(0xFFD1001F),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
            tooltip: 'Exporter / Imprimer / Outlook',
            onPressed: () {
              RapportPdfService.afficherDialogueExport(
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
          IconButton(
            icon: const Icon(Icons.share, color: Colors.white),
            tooltip: 'Partager le rapport',
            onPressed: () {
              RapportPdfService.afficherDialogueExport(
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
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── CARTOUCHE CORPORATIF RAYCOWYLIE ─────────────────────────
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF7A000F), Color(0xFFB71C1C), Color(0xFFD1001F)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SvgPicture.asset(
                      'assets/images/RaycoWylie-Logo.svg',
                      height: 28,
                      width: 120,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'RAYCO WYLIE SYSTEMS',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 0.5),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Systèmes Électroniques Rayco Ltée • Rapport Certifié',
                          style: TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ─── 📄 BANDEAU RAPPORT PDF WINDOWS / DESKTOP ──────────────────
            if (isWindowsDesktop)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _pdfCheminLocal != null ? Colors.green.shade50 : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _pdfCheminLocal != null ? Colors.green.shade600 : Colors.blue.shade400,
                    width: 1.2,
                  ),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: _pdfCheminLocal != null ? Colors.green.shade100 : Colors.blue.shade100,
                      child: Icon(
                        Icons.picture_as_pdf,
                        color: _pdfCheminLocal != null ? Colors.green.shade800 : Colors.blue.shade800,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _pdfCheminLocal != null
                                ? 'Rapport PDF officiel généré'
                                : 'Rapport PDF non généré sur le disque',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: _pdfCheminLocal != null ? Colors.green.shade900 : Colors.blue.shade900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _pdfCheminLocal ?? 'Générez et enregistrez le PDF officiel dans vos dossiers Windows d\'un simple clic.',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_pdfCheminLocal != null) ...[
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        ),
                        icon: const Icon(Icons.open_in_new, size: 15),
                        label: const Text('Ouvrir', style: TextStyle(fontSize: 12)),
                        onPressed: () => RapportPdfService.ouvrirFichier(_pdfCheminLocal!),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: 'Afficher dans l\'explorateur',
                        icon: const Icon(Icons.folder_open, color: Colors.indigo),
                        onPressed: () => RapportPdfService.selectionnerDansExplorateur(_pdfCheminLocal!),
                      ),
                    ] else ...[
                      _isGeneratingPdf
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue.shade700,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              ),
                              icon: const Icon(Icons.download, size: 15),
                              label: const Text('Générer PDF', style: TextStyle(fontSize: 12)),
                              onPressed: _genererPdfMaintenant,
                            ),
                    ],
                  ],
                ),
              ),

            // En-tête Statut & Client
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          intervention['numero_rapport'] != null
                              ? 'RAPPORT Nº ${intervention['numero_rapport']}'
                              : 'BON D\'INTERVENTION #${intervention['id'] ?? '1'}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                        Builder(
                          builder: (context) {
                            final bool estApprouve = estRapportApprouve(intervention);
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: estApprouve ? Colors.green.shade100 : Colors.amber.shade100,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: estApprouve ? Colors.green.shade400 : Colors.amber.shade600,
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    estApprouve ? Icons.verified : Icons.hourglass_top,
                                    size: 14,
                                    color: estApprouve ? Colors.green.shade800 : Colors.amber.shade900,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    estApprouve ? 'Complété & Conforme' : 'En attente d\'approbation',
                                    style: TextStyle(
                                      color: estApprouve ? Colors.green.shade800 : Colors.amber.shade900,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      intervention['nom_client'] ?? 'Client Inconnu',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    // 🏢 ADRESSE DE FACTURATION DU CLIENT
                    if (intervention['adresse_facturation'] != null &&
                        (intervention['adresse_facturation'] as String).trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.receipt_long, color: Colors.indigo, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Facturation : ${intervention['adresse_facturation']}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.indigo,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (intervention['nom_contact'] != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Contact : ${intervention['nom_contact']}  •  ${intervention['telephone'] ?? ''}',
                        style: const TextStyle(color: Colors.blueGrey, fontSize: 13),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.location_on, color: Colors.redAccent, size: 18),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            (intervention['adresse_intervention'] ?? intervention['adresse'] ?? '').toString(),
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ),
                      ],
                    ),
                    if (intervention['numero_bon_commande'] != null &&
                        intervention['numero_bon_commande'].toString().trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD1001F).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFD1001F).withValues(alpha: 0.25)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.assignment, size: 14, color: Color(0xFFD1001F)),
                            const SizedBox(width: 6),
                            Text(
                              'Bon de commande (P.O.) : ${intervention['numero_bon_commande']}',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFD1001F)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // 📊 BILAN TEMPS & DISTANCE
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '⏱️ Bilan Trajet & Chantier',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo,
                      ),
                    ),
                    const Divider(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildMetricBox(
                          'Trajet Aller',
                          intervention['duree_trajet'] ?? '--',
                          Icons.directions_car,
                          Colors.blueAccent,
                        ),
                        _buildMetricBox(
                          'Chantier & Rapport',
                          intervention['duree_chantier'] ?? '--',
                          Icons.handyman,
                          Colors.teal,
                        ),
                        _buildMetricBox(
                          'Trajet Retour',
                          intervention['duree_retour'] ?? intervention['duree_trajet'] ?? '--',
                          Icons.rotate_right,
                          Colors.orangeAccent,
                        ),
                      ],
                    ),
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.teal.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.teal.shade300),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.verified, size: 16, color: Colors.teal),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Builder(
                              builder: (context) {
                                final totalFacturable = (intervention['duree_totale_facturable'] != null &&
                                        intervention['duree_totale_facturable'].toString().isNotEmpty &&
                                        intervention['duree_totale_facturable'] != '--')
                                    ? intervention['duree_totale_facturable'].toString()
                                    : (() {
                                        final t = dureeChaineVersSecondes(intervention['duree_trajet']);
                                        final c = dureeChaineVersSecondes(intervention['duree_chantier']);
                                        final r = dureeChaineVersSecondes(intervention['duree_retour'] ?? intervention['duree_trajet']);
                                        final s = t + c + r;
                                        return s > 0 ? formatSeconds(s) : (intervention['duree_chantier'] ?? '--');
                                      })();
                                return Text(
                                  'Total Facturable : $totalFacturable (incluant déplacement aller, chantier/rédaction et retour)',
                                  style: TextStyle(
                                    color: Colors.teal.shade900,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (intervention['duree_pause_secondes'] != null &&
                        (intervention['duree_pause_secondes'] as int) > 0) ...[
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.pause_circle_outline,
                            size: 16,
                            color: Colors.orange,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Dont temps de pause trajet : ${formatSeconds(intervention['duree_pause_secondes'] as int)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.orange,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (intervention['duree_pause_chantier_secondes'] != null &&
                        (intervention['duree_pause_chantier_secondes'] as int) > 0) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.pause_circle_filled,
                            size: 16,
                            color: Colors.amber.shade900,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Dont temps de pause intervention : ${formatSeconds(intervention['duree_pause_chantier_secondes'] as int)}'
                            '${(intervention['motif_pause_chantier'] != null && (intervention['motif_pause_chantier'] as String).isNotEmpty) ? ' (${intervention['motif_pause_chantier']})' : ''}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.amber.shade900,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Horodatage & GPS
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '⏱️ Horodatage & Déplacements',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const Divider(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildTimeInfo('Départ route', heureDepart ?? '--:--', Icons.directions_car),
                        _buildTimeInfo('Arrivée sur site', heureArrivee ?? '--:--', Icons.place),
                        _buildTimeInfo('Clôture', DateTime.now().toString().substring(11, 16), Icons.check_circle),
                      ],
                    ),
                    if (intervention['gps_arrivee'] != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Coordonnées GPS : ${intervention['gps_arrivee']}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Travaux réalisés / Notes de service
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '📝 Travaux Réalisés / Notes de Service',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        if (!estApprouve)
                          TextButton.icon(
                            icon: const Icon(Icons.edit_note, size: 18),
                            label: const Text('Modifier les notes'),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.indigo,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            ),
                            onPressed: _afficherDialogueModifierNotes,
                          ),
                      ],
                    ),
                    const Divider(height: 20),
                    Text(
                      notes,
                      style: const TextStyle(fontSize: 15, height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Machine & Intervention
            if (intervention['type_machine'] != null || intervention['marque'] != null)
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                color: Colors.orange.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '🏗️ Machine & Type d\'Intervention',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.deepOrange),
                      ),
                      const Divider(height: 20),
                      _buildInfoRow('Type d\'intervention', intervention['type_intervention'] ?? '--'),
                      _buildInfoRow('Type de machine', intervention['type_machine'] ?? '--'),
                      _buildInfoRow('Marque / Modèle',
                        '${intervention['marque'] ?? ''} ${intervention['modele'] ?? ''}'.trim()),
                      _buildInfoRow('Année', intervention['annee'] ?? '--'),
                      _buildInfoRow('N° série machine', intervention['numero_serie_machine'] ?? '--'),
                      if (intervention['numero_unite']?.isNotEmpty == true)
                        _buildInfoRow('N° unité machine', intervention['numero_unite']),
                      _buildInfoRow('Alimentation', intervention['alimentation'] ?? '--'),
                      if (intervention['numero_commande']?.isNotEmpty == true)
                        _buildInfoRow('N° commande', intervention['numero_commande']),
                      if (intervention['numero_reference']?.isNotEmpty == true)
                        _buildInfoRow('N° référence', intervention['numero_reference']),
                      if (intervention['numero_bon_commande']?.isNotEmpty == true)
                        _buildInfoRow('Bon de commande', intervention['numero_bon_commande']),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),

            // Système installé
            if (intervention['numero_produit'] != null || intervention['version_logiciel'] != null)
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                color: Colors.purple.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '⚙️ Système Installé',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.purple),
                      ),
                      const Divider(height: 20),
                      _buildInfoRow('N° produit', intervention['numero_produit'] ?? '--'),
                      _buildInfoRow('N° série système', intervention['numero_serie_systeme'] ?? '--'),
                      _buildInfoRow('Version logiciel', intervention['version_logiciel'] ?? '--'),
                      _buildInfoRow('Engrenage', intervention['engrenage'] ?? '--'),
                      _buildInfoRow('Position bypass', intervention['position_bypass'] ?? '--'),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),

            // Pièces utilisées
            if (piecesUtilisees.isNotEmpty)
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '🔧 Pièces Utilisées',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.redAccent),
                      ),
                      const Divider(height: 20),
                      ...piecesUtilisees.map((piece) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.circle, size: 8, color: Colors.redAccent),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${piece['nom']} (Réf: ${piece['ref']})',
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.redAccent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${piece['utilise']} ${piece['unite']}',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      )),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),

            // Contrôles de sécurité & conformité RaycoWylie
            // Contrôles de sécurité & conformité RaycoWylie
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              color: controlesSecurite.isNotEmpty ? Colors.green.shade50 : Colors.grey.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '🛡️ Contrôles de Sécurité & Conformité',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: controlesSecurite.isNotEmpty ? Colors.green.shade200 : Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${controlesSecurite.length} / ${kControlesSecuriteStandards.length} validés',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: controlesSecurite.isNotEmpty ? Colors.green.shade900 : Colors.grey.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    ...(() {
                      final tous = List<String>.from(kControlesSecuriteStandards);
                      for (final c in controlesSecurite) {
                        if (!tous.contains(c)) tous.add(c);
                      }
                      return tous.map((item) {
                        final bool isChecked = controlesSecurite.any(
                          (c) => c.trim().toLowerCase() == item.trim().toLowerCase(),
                        );
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3.5),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                isChecked ? Icons.check_box : Icons.check_box_outline_blank,
                                color: isChecked ? const Color(0xFF1B5E20) : Colors.grey.shade400,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  item,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: isChecked ? FontWeight.w600 : FontWeight.normal,
                                    color: isChecked ? Colors.black87 : Colors.black45,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList();
                    })(),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ✍️ Signature client
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '✍️ Signature de Validation Client',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const Divider(height: 20),
                    if (signatureBase64 != null && signatureBase64.isNotEmpty) ...[
                      Center(
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                            color: Colors.grey.shade50,
                          ),
                          padding: const EdgeInsets.all(8),
                          child: Image.memory(
                            base64Decode(signatureBase64),
                            height: 120,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      if (intervention['nom_signataire_distant'] != null) ...[
                        const SizedBox(height: 8),
                        Center(
                          child: Text(
                            'Signé par : ${intervention['nom_signataire_distant']}',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.amber.shade200),
                        ),
                        child: Column(
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.pending_actions, color: Colors.amber, size: 22),
                                SizedBox(width: 8),
                                Text(
                                  'En attente de signature du client',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFD1001F),
                                  foregroundColor: Colors.white,
                                ),
                                icon: const Icon(Icons.send_to_mobile, size: 18),
                                label: const Text('Envoyer / Partager le lien de signature'),
                                onPressed: () => SignatureDistanceService.afficherDialoguePartage(
                                  context,
                                  intervention: widget.intervention,
                                  onTokenGenere: () => setState(() {}),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 🛡️ Approbation Superviseur (Tampon Officiel & Déduction Inventaire)
            _buildCarteApprobationSuperviseur(),
            const SizedBox(height: 16),

            // 📸 Photos de l'Intervention (DÉPLACÉES EN TOUTE FIN DU RAPPORT)
            _buildCartePhotos(),
            const SizedBox(height: 24),

            // Bouton Exporter / Partager / Outlook
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text(
                  'Exporter PDF / Envoi Outlook',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal.shade700,
                  foregroundColor: Colors.white,
                  elevation: 2,
                ),
                onPressed: () {
                  RapportPdfService.afficherDialogueExport(
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
            ),
            const SizedBox(height: 12),

            // Bouton retour
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.arrow_back),
                label: const Text('Retour à l\'Agenda'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.indigo,
                  side: const BorderSide(color: Colors.indigo),
                ),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricBox(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Column(
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.black54, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildTimeInfo(String label, String time, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.indigo, size: 24),
        const SizedBox(height: 4),
        Text(time, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(color: Colors.black54, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
