import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_helpers.dart';

// ==============================================================================
// 📸 COMPOSANT RÉUTILISABLE : GESTION DES PHOTOS DE CHANTIER (WINDOWS & MOBILE)
// ==============================================================================

class WidgetPhotosChantier extends StatefulWidget {
  final Map<String, dynamic> intervention;
  final bool lectureSeule;
  final Future<void> Function()? onPhotosModifiees;

  const WidgetPhotosChantier({
    super.key,
    required this.intervention,
    this.lectureSeule = false,
    this.onPhotosModifiees,
  });

  /// Ouvre un dialogue interactif complet de gestion des photos
  static Future<void> afficherDialogue(
    BuildContext context, {
    required Map<String, dynamic> intervention,
    bool lectureSeule = false,
    Future<void> Function()? onPhotosModifiees,
  }) {
    return showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640, maxHeight: 720),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          const Icon(Icons.photo_camera_back, color: Colors.indigo, size: 22),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Photos du Chantier • ${intervention['nom_client'] ?? 'Intervention'}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Fermer',
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const Divider(),
                Flexible(
                  child: SingleChildScrollView(
                    child: WidgetPhotosChantier(
                      intervention: intervention,
                      lectureSeule: lectureSeule,
                      onPhotosModifiees: onPhotosModifiees,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Ouvre un dialogue pour ajouter ou modifier les notes de service pendant l'intervention
  static Future<void> afficherDialogueNotesDeService(
    BuildContext context, {
    required Map<String, dynamic> intervention,
    bool lectureSeule = false,
    Future<void> Function(String nouvellesNotes)? onNotesSauvegardees,
  }) async {
    final texteInitial = getNotesDeService(intervention);
    final ctrl = TextEditingController(text: texteInitial);

    final bool? valide = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            const Icon(Icons.note_alt_outlined, color: Colors.indigo),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Notes de Service • ${intervention['nom_client'] ?? 'Intervention'}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                lectureSeule
                    ? 'Notes de service saisies pour cette intervention (rapport approuvé, lecture seule) :'
                    : 'Notes techniques, constats de panne, travaux réalisés ou pièces à prévoir (modifiables jusqu\'à l\'approbation finale) :',
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                readOnly: lectureSeule,
                maxLines: 7,
                autofocus: !lectureSeule,
                decoration: InputDecoration(
                  hintText: lectureSeule
                      ? 'Aucune note'
                      : 'Ex: Remplacement du câble de capteur de longueur, calibration sous charge effectuée...',
                  filled: true,
                  fillColor: lectureSeule ? Colors.grey.shade100 : Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(lectureSeule ? 'Fermer' : 'Annuler'),
          ),
          if (!lectureSeule)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.save, size: 16),
              label: const Text('Enregistrer les notes'),
              onPressed: () => Navigator.pop(ctx, true),
            ),
        ],
      ),
    );

    if (valide == true && onNotesSauvegardees != null) {
      await onNotesSauvegardees(ctrl.text.trim());
    }
  }

  @override
  State<WidgetPhotosChantier> createState() => _WidgetPhotosChantierState();
}

class _WidgetPhotosChantierState extends State<WidgetPhotosChantier> {
  bool _enCours = false;

  List<String> get _photos => getPhotosIntervention(widget.intervention);

  Future<void> _capturerPhoto(ImageSource source) async {
    if (widget.lectureSeule) return;
    setState(() => _enCours = true);

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

      if (sourcePaths.isEmpty) {
        setState(() => _enCours = false);
        return;
      }

      final numDossier = getNumeroDossier(widget.intervention);
      final currentPhotos = List<String>.from(_photos);
      int ajoutes = 0;

      for (final src in sourcePaths) {
        final savedPath = await enregistrerPhotoDepuisChemin(
          sourcePath: src,
          numeroCommande: numDossier,
        );
        if (savedPath != null && !currentPhotos.contains(savedPath)) {
          currentPhotos.add(savedPath);
          ajoutes++;
        }
      }

      if (ajoutes > 0) {
        widget.intervention['photos'] = jsonEncode(currentPhotos);

        if (widget.onPhotosModifiees != null) {
          await widget.onPhotosModifiees!();
        }

        if (mounted) {
          setState(() => _enCours = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isWindowsDesktop
                    ? '📸 $ajoutes photo(s) ajoutée(s) dans Pictures\\$numDossier'
                    : '📸 $ajoutes photo(s) ajoutée(s) avec succès !',
              ),
              backgroundColor: Colors.green.shade700,
              duration: const Duration(seconds: 2),
              action: isWindowsDesktop
                  ? SnackBarAction(
                      label: 'Ouvrir dossier',
                      textColor: Colors.white,
                      onPressed: () => ouvrirDossierPhotos(numDossier),
                    )
                  : null,
            ),
          );
        }
      } else {
        if (mounted) setState(() => _enCours = false);
      }
    } catch (e) {
      debugPrint('Erreur capture photo: $e');
      if (mounted) {
        setState(() => _enCours = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors de l\'ajout des photos : $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _supprimerPhoto(int index) async {
    if (widget.lectureSeule) return;
    final currentPhotos = List<String>.from(_photos);
    if (index >= 0 && index < currentPhotos.length) {
      currentPhotos.removeAt(index);
      widget.intervention['photos'] = jsonEncode(currentPhotos);
      setState(() {});

      if (widget.onPhotosModifiees != null) {
        await widget.onPhotosModifiees!();
      }
    }
  }

  void _afficherPhotoPleinEcran(String path) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(
              child: buildImageFromPath(path, fit: BoxFit.contain),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final numDossier = getNumeroDossier(widget.intervention);
    final photosList = _photos;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── En-tête de la carte Photos ───────────────────
            Row(
              children: [
                const Icon(Icons.photo_camera, color: Colors.blueAccent, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Photos du chantier',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: photosList.isNotEmpty ? Colors.blue.shade100 : Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${photosList.length} photo(s)',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: photosList.isNotEmpty ? Colors.blue.shade900 : Colors.grey.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (isWindowsDesktop)
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

            // ─── Boutons d'ajout (si non lecture seule) ───────
            if (!widget.lectureSeule) ...[
              if (_enCours)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 10),
                        Text('Enregistrement de la photo...', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                )
              else
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
                                      content: Text('📸 Caméra Windows ouverte. Après avoir pris la photo, cliquez sur "Choisir photo" pour l\'ajouter au rapport.'),
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
              const SizedBox(height: 12),
            ],

            // ─── Galerie horizontale des photos ───────────────
            if (photosList.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 20),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    Icon(Icons.photo_library_outlined, size: 36, color: Colors.grey.shade400),
                    const SizedBox(height: 6),
                    Text(
                      'Aucune photo ajoutée pour le moment',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    ),
                    if (!widget.lectureSeule) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Ajoutez des photos de l\'équipement ou du trouble avant l\'approbation finale',
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                      ),
                    ],
                  ],
                ),
              )
            else
              SizedBox(
                height: 110,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: photosList.length,
                  itemBuilder: (context, index) {
                    final pPath = photosList[index];
                    return GestureDetector(
                      onTap: () => _afficherPhotoPleinEcran(pPath),
                      child: Container(
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
                            if (!widget.lectureSeule)
                              Positioned(
                                top: 4,
                                right: 4,
                                child: GestureDetector(
                                  onTap: () => _supprimerPhoto(index),
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
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
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
