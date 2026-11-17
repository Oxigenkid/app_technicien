import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'rapport_pdf.dart';
import 'receipt_scanner_service.dart';
import 'techniciens_service.dart';
import 'nip_service.dart';

// ============================================================================
// 🧾 MODÈLE DE DONNÉES : DÉPENSE & REÇU
// ============================================================================

enum CategorieDepense {
  essence,        // Carburant / Diesel camion
  repas,          // Dîner / Restauration chantier
  outillage,      // Quincaillerie, attaches, outillage
  stationnement,  // Stationnement / Péages
  pieces,         // Pièces urgentes achetées localement
  hebergement,    // Hôtel / Nuitée déplacement
  autre,          // Divers
}

class Depense {
  final String id;
  DateTime date;
  String technicien;
  double montant; // Montant de la dépense / repas hors pourboire
  double pourboire; // Pourboire distinct (notamment pour les repas de chantier)
  CategorieDepense categorie;
  String description;
  String fournisseur;
  String? numeroCommande;
  String? photoPath; // Fichier photo du reçu
  String modePaiement; // "Personnel (À rembourser)", "Carte Entreprise"

  Depense({
    required this.id,
    required this.date,
    required this.technicien,
    required this.montant,
    this.pourboire = 0.0,
    required this.categorie,
    required this.description,
    this.fournisseur = '',
    this.numeroCommande,
    this.photoPath,
    this.modePaiement = 'Personnel (À rembourser)',
  });

  /// Montant total incluant le pourboire
  double get montantTotal => montant + pourboire;

  bool get aRembourser => modePaiement.contains('À rembourser') || modePaiement.contains('Personnel');

  String get libelleCategorie {
    switch (categorie) {
      case CategorieDepense.essence:
        return 'Carburant / Diesel';
      case CategorieDepense.repas:
        return 'Repas / Dîner';
      case CategorieDepense.outillage:
        return 'Outillage & Quincaillerie';
      case CategorieDepense.stationnement:
        return 'Stationnement & Péage';
      case CategorieDepense.pieces:
        return 'Pièces urgentes';
      case CategorieDepense.hebergement:
        return 'Hébergement / Hôtel';
      case CategorieDepense.autre:
        return 'Autre dépense';
    }
  }

  IconData get icone {
    switch (categorie) {
      case CategorieDepense.essence:
        return Icons.local_gas_station_rounded;
      case CategorieDepense.repas:
        return Icons.restaurant_rounded;
      case CategorieDepense.outillage:
        return Icons.build_rounded;
      case CategorieDepense.stationnement:
        return Icons.local_parking_rounded;
      case CategorieDepense.pieces:
        return Icons.handyman_rounded;
      case CategorieDepense.hebergement:
        return Icons.hotel_rounded;
      case CategorieDepense.autre:
        return Icons.receipt_long_rounded;
    }
  }

  Color get couleur {
    switch (categorie) {
      case CategorieDepense.essence:
        return Colors.blue.shade700;
      case CategorieDepense.repas:
        return Colors.orange.shade800;
      case CategorieDepense.outillage:
        return Colors.teal.shade700;
      case CategorieDepense.stationnement:
        return Colors.indigo.shade600;
      case CategorieDepense.pieces:
        return Colors.purple.shade700;
      case CategorieDepense.hebergement:
        return Colors.amber.shade900;
      case CategorieDepense.autre:
        return Colors.blueGrey;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'technicien': technicien,
        'montant': montant,
        'pourboire': pourboire,
        'categorie': categorie.name,
        'description': description,
        'fournisseur': fournisseur,
        'numeroCommande': numeroCommande,
        'numero_commande': numeroCommande,
        'photoPath': photoPath,
        'photo_path': photoPath,
        'modePaiement': modePaiement,
        'mode_paiement': modePaiement,
      };

  Map<String, dynamic> toSupabase() => {
        'id': id,
        'date': date.toIso8601String(),
        'technicien': technicien,
        'montant': montant,
        'pourboire': pourboire,
        'categorie': categorie.name,
        'description': description,
        'fournisseur': fournisseur,
        'numero_commande': numeroCommande,
        'photo_path': photoPath,
        'mode_paiement': modePaiement,
      };

  factory Depense.fromJson(Map<String, dynamic> json) => Depense(
        id: json['id'] as String,
        date: DateTime.parse(json['date'] as String),
        technicien: json['technicien'] as String? ?? 'Patrick Popatry',
        montant: (json['montant'] as num).toDouble(),
        pourboire: (json['pourboire'] as num?)?.toDouble() ?? 0.0,
        categorie: CategorieDepense.values.firstWhere(
          (c) => c.name == json['categorie'],
          orElse: () => CategorieDepense.autre,
        ),
        description: json['description'] as String? ?? '',
        fournisseur: json['fournisseur'] as String? ?? '',
        numeroCommande: (json['numero_commande'] ?? json['numeroCommande']) as String?,
        photoPath: (json['photo_path'] ?? json['photoPath']) as String?,
        modePaiement: (json['mode_paiement'] ?? json['modePaiement']) as String? ?? 'Personnel (À rembourser)',
      );
}

// ============================================================================
// 💾 GESTION DE LA PERSISTANCE & DOSSIERS PHOTOS REÇUS (LOCAL & SUPABASE)
// ============================================================================

class DepenseService {
  static final DepenseService instance = DepenseService._();
  DepenseService._();

  List<Depense> _depenses = [];
  bool _initialise = false;

  Future<List<Depense>> getDepenses() async {
    if (!_initialise) {
      await charger();
    }
    return _depenses;
  }

  /// Récupère ou crée le dossier Windows dédié aux reçus de dépenses
  Directory? getDossierRecusWindows() {
    if (kIsWeb) return null;
    try {
      final userProfile =
          Platform.environment['USERPROFILE'] ?? 'C:\\Users\\Default';
      final dir = Directory('$userProfile\\Pictures\\Depenses');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      return dir;
    } catch (_) {
      return null;
    }
  }

  /// Ouvre le dossier des reçus dans l'explorateur Windows
  Future<void> ouvrirDossierRecusDansWindows() async {
    if (kIsWeb) return;
    try {
      final dir = getDossierRecusWindows();
      if (dir != null && Platform.isWindows) {
        await Process.run('explorer.exe', [dir.path]);
      }
    } catch (e) {
      debugPrint('Erreur ouverture dossier reçus: $e');
    }
  }

  File? _getFichierSauvegarde() {
    if (kIsWeb) return null;
    try {
      final userProfile =
          Platform.environment['USERPROFILE'] ?? 'C:\\Users\\Default';
      final dir = Directory('$userProfile\\Documents\\AppTechnicien');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      return File('${dir.path}\\depenses.json');
    } catch (_) {
      return null;
    }
  }

  Future<void> charger() async {
    _initialise = true;
    await NipSecuriteService.instance.chargerNips();

    // 1. Essai de chargement depuis Supabase
    try {
      final response = await Supabase.instance.client
          .from('depenses')
          .select()
          .order('date', ascending: false);
      if (response.isNotEmpty) {
        _depenses = List<Map<String, dynamic>>.from(response)
            .map((item) => Depense.fromJson(item))
            .toList();
        await _sauvegarderLocal();
        return;
      }
    } catch (e) {
      debugPrint('Supabase depenses indisponible (mode local): $e');
    }

    // 2. Fallback cache local
    try {
      final file = _getFichierSauvegarde();
      if (file != null && await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> jsonList = jsonDecode(content) as List<dynamic>;
        _depenses = jsonList
            .map((item) => Depense.fromJson(item as Map<String, dynamic>))
            .toList();
        if (_depenses.isNotEmpty) return;
      }
    } catch (e) {
      debugPrint('Erreur chargement depenses: $e');
    }

    // 3. Données par défaut pour démonstration immédiate par technicien
    final now = DateTime.now();
    _depenses = [
      // Dépenses pour Pierre-Olivier Patry (Camion #102)
      Depense(
        id: 'dep_po_01',
        date: DateTime(now.year, now.month, now.day - 2),
        technicien: 'Pierre-Olivier Patry',
        montant: 142.50,
        categorie: CategorieDepense.essence,
        fournisseur: 'Pétro-Canada',
        description: 'Plein de diesel pour Camion #102',
        modePaiement: 'Personnel (À rembourser)',
        numeroCommande: 'CO-2026-0891',
      ),
      Depense(
        id: 'dep_po_02',
        date: DateTime(now.year, now.month, now.day - 1),
        technicien: 'Pierre-Olivier Patry',
        montant: 18.50,
        pourboire: 3.35,
        categorie: CategorieDepense.repas,
        fournisseur: 'Subway Lebourgneuf',
        description: 'Dîner chantier - Intervention Tadano',
        modePaiement: 'Personnel (À rembourser)',
        numeroCommande: 'CO-2026-0944',
      ),
      Depense(
        id: 'dep_po_03',
        date: DateTime(now.year, now.month, now.day),
        technicien: 'Pierre-Olivier Patry',
        montant: 36.40,
        pourboire: 0.0,
        categorie: CategorieDepense.outillage,
        fournisseur: 'BMR / Quincaillerie',
        description: 'Boulons inox et attaches capteur Wylie',
        modePaiement: 'Personnel (À rembourser)',
        numeroCommande: 'CO-2026-1012',
      ),

      // Dépenses pour David Hestin (Camion #101)
      Depense(
        id: 'dep_dh_01',
        date: DateTime(now.year, now.month, now.day - 1),
        technicien: 'David Hestin',
        montant: 155.00,
        categorie: CategorieDepense.essence,
        fournisseur: 'Shell Canada',
        description: 'Diesel Camion #101 - Déplacement Port de Québec',
        modePaiement: 'Personnel (À rembourser)',
        numeroCommande: 'CO-2026-0775',
      ),
      Depense(
        id: 'dep_dh_02',
        date: DateTime(now.year, now.month, now.day),
        technicien: 'David Hestin',
        montant: 26.50,
        pourboire: 4.25,
        categorie: CategorieDepense.repas,
        fournisseur: 'St-Hubert Express',
        description: 'Dîner chantier déplacement longue distance',
        modePaiement: 'Personnel (À rembourser)',
        numeroCommande: 'CO-2026-0780',
      ),

      // Dépenses pour Jean-François Allie (Camion #103)
      Depense(
        id: 'dep_jf_01',
        date: DateTime(now.year, now.month, now.day - 3),
        technicien: 'Jean-François Allie',
        montant: 84.20,
        categorie: CategorieDepense.pieces,
        fournisseur: 'NAPA Pièces d\'auto',
        description: 'Relais et fusibles d\'urgence grue Grove',
        modePaiement: 'Personnel (À rembourser)',
        numeroCommande: 'CO-2026-0610',
      ),
    ];
    await _sauvegarderLocal();

    // Synchroniser vers Supabase
    for (final d in _depenses) {
      try {
        await Supabase.instance.client.from('depenses').upsert(d.toSupabase());
      } catch (_) {}
    }
  }

  Future<void> _sauvegarderLocal() async {
    try {
      final file = _getFichierSauvegarde();
      if (file != null) {
        final jsonStr = jsonEncode(_depenses.map((d) => d.toJson()).toList());
        await file.writeAsString(jsonStr);
      }
    } catch (e) {
      debugPrint('Erreur sauvegarde depenses: $e');
    }
  }

  Future<void> sauvegarder() async {
    await _sauvegarderLocal();
  }

  // ============================================================================
  // 🔐 GESTION DES CODES NIP PAR TECHNICIEN
  // ============================================================================


  /// Récupère le code NIP configuré pour un technicien
  Future<String> getNipPourTechnicien(String nomTechnicien) =>
      NipSecuriteService.instance.getNipPourTechnicien(nomTechnicien);

  /// Enregistre un nouveau code NIP pour un technicien
  Future<void> setNipPourTechnicien(String nomTechnicien, String nouveauNip) =>
      NipSecuriteService.instance.setNipPourTechnicien(nomTechnicien, nouveauNip);

  /// Vérifie la validité du NIP (avec passe-partout superviseur 9999)
  Future<bool> verifierNip(String nomTechnicien, String nipSaisi) =>
      NipSecuriteService.instance.verifierNip(nomTechnicien, nipSaisi);

  // ============================================================================
  // 📋 FILTRAGE INDÉPENDANT PAR COMPTE TECHNICIEN
  // ============================================================================

  static String _normaliserNomTechnicien(String nom) =>
      NipSecuriteService.normaliserNomTechnicien(nom);

  /// Liste des dépenses spécifique au compte d'un technicien
  List<Depense> getDepensesPourTechnicien(String nomTechnicien) {
    final norm = _normaliserNomTechnicien(nomTechnicien).toLowerCase();
    final brut = nomTechnicien.trim().toLowerCase();
    return _depenses.where((d) {
      final dNorm = _normaliserNomTechnicien(d.technicien).toLowerCase();
      final dBrut = d.technicien.trim().toLowerCase();
      return dNorm == norm || dBrut == brut;
    }).toList();
  }

  double totalARembourserPour(String nomTechnicien) {
    return getDepensesPourTechnicien(nomTechnicien)
        .where((d) => d.aRembourser)
        .fold(0.0, (sum, d) => sum + d.montantTotal);
  }

  double totalRepasHorsPourboirePour(String nomTechnicien) {
    return getDepensesPourTechnicien(nomTechnicien)
        .where((d) => d.categorie == CategorieDepense.repas && d.aRembourser)
        .fold(0.0, (s, d) => s + d.montant);
  }

  double totalPourboiresPour(String nomTechnicien) {
    return getDepensesPourTechnicien(nomTechnicien)
        .where((d) => d.aRembourser)
        .fold(0.0, (s, d) => s + d.pourboire);
  }

  double totalAutresFraisPour(String nomTechnicien) {
    return getDepensesPourTechnicien(nomTechnicien)
        .where((d) => d.categorie != CategorieDepense.repas && d.aRembourser)
        .fold(0.0, (s, d) => s + d.montantTotal);
  }

  // ============================================================================
  // ✍️ ACTIONS CRUD (AJOUTER, MODIFIER, SUPPRIMER)
  // ============================================================================

  Future<void> ajouterDepense(Depense depense) async {
    _depenses.insert(0, depense);
    await _sauvegarderLocal();
    try {
      await Supabase.instance.client.from('depenses').upsert(depense.toSupabase());
    } catch (e) {
      debugPrint('Erreur Supabase ajouterDepense: $e');
    }
  }

  Future<void> modifierDepense(Depense depense) async {
    final index = _depenses.indexWhere((d) => d.id == depense.id);
    if (index >= 0) {
      _depenses[index] = depense;
      await _sauvegarderLocal();
      try {
        await Supabase.instance.client.from('depenses').upsert(depense.toSupabase());
      } catch (e) {
        debugPrint('Erreur Supabase modifierDepense: $e');
      }
    }
  }

  Future<void> supprimerDepense(String id) async {
    _depenses.removeWhere((d) => d.id == id);
    await _sauvegarderLocal();
    try {
      await Supabase.instance.client.from('depenses').delete().eq('id', id);
    } catch (e) {
      debugPrint('Erreur Supabase supprimerDepense: $e');
    }
  }

  double get totalARembourser => _depenses
      .where((d) => d.aRembourser)
      .fold(0.0, (sum, d) => sum + d.montantTotal);

  double get totalRepasHorsPourboire => _depenses
      .where((d) => d.categorie == CategorieDepense.repas && d.aRembourser)
      .fold(0.0, (s, d) => s + d.montant);

  double get totalPourboires => _depenses
      .where((d) => d.aRembourser)
      .fold(0.0, (s, d) => s + d.pourboire);

  double get totalAutresFrais => _depenses
      .where((d) => d.categorie != CategorieDepense.repas && d.aRembourser)
      .fold(0.0, (s, d) => s + d.montantTotal);

  /// Capture ou sélection de photo selon la plateforme demandée par l'utilisateur :
  /// - Android : Déclenche directement la caméra
  /// - Windows : Ouvre l'explorateur / sélecteur de fichiers Windows
  Future<String?> capturerOuSelectionnerPhotoRecu(BuildContext context) async {
    try {
      // 1. Sur Téléphone Android (ou iOS natif) : Prendre directement une photo
      if (!kIsWeb && Platform.isAndroid) {
        final picker = ImagePicker();
        final xfile = await picker.pickImage(
          source: ImageSource.camera,
          maxWidth: 1920,
          maxHeight: 1920,
          imageQuality: 85,
        );
        if (xfile != null) {
          return xfile.path;
        }
        return null;
      }

      // 2. Sur Windows Desktop : Ouvrir l'explorateur Windows / sélecteur d'image natif
      if (!kIsWeb && Platform.isWindows) {
        final files = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'bmp', 'heic', 'pdf'],
          dialogTitle: 'Sélectionner le reçu ou la facture',
        );
        if (files.isNotEmpty && files.first.path != null) {
          final originalPath = files.first.path!;
          // Copier dans le dossier permanent des reçus Windows
          final dossier = getDossierRecusWindows();
          if (dossier != null) {
            final ext = originalPath.split('.').last;
            final destName = 'recu_${DateTime.now().millisecondsSinceEpoch}.$ext';
            final destFile = File('${dossier.path}\\$destName');
            await File(originalPath).copy(destFile.path);
            return destFile.path;
          }
          return originalPath;
        }
        return null;
      }

      // 3. Fallback Web ou autre
      final picker = ImagePicker();
      final xfile = await picker.pickImage(source: ImageSource.gallery);
      return xfile?.path;
    } catch (e) {
      debugPrint('Erreur capture/sélection reçu: $e');
      return null;
    }
  }
}

// ============================================================================
// 📄 SERVICE PDF : RAPPORT DE REMBOURSEMENT DE DÉPENSES
// ============================================================================

class DepensePdfService {
  static pw.Font? _cachedFontRegular;
  static pw.Font? _cachedFontBold;

  static Future<Uint8List> genererBytesPdf(List<Depense> depenses, {String technicien = 'Patrick Popatry'}) async {
    final pdf = pw.Document();

    pw.Font fontRegular = _cachedFontRegular ?? pw.Font.helvetica();
    pw.Font fontBold = _cachedFontBold ?? pw.Font.helveticaBold();
    if (_cachedFontRegular == null || _cachedFontBold == null) {
      try {
        fontRegular = await PdfGoogleFonts.robotoRegular().timeout(const Duration(milliseconds: 1200));
        fontBold = await PdfGoogleFonts.robotoBold().timeout(const Duration(milliseconds: 1200));
        _cachedFontRegular = fontRegular;
        _cachedFontBold = fontBold;
      } catch (_) {
        fontRegular = pw.Font.helvetica();
        fontBold = pw.Font.helveticaBold();
      }
    }

    final theme = pw.ThemeData.withFont(base: fontRegular, bold: fontBold);

    final primary = PdfColor.fromHex('#1E3A8A');
    final accentGreen = PdfColor.fromHex('#047857');
    final greyBg = PdfColor.fromHex('#F8FAFC');

    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final totalRemboursement = depenses
        .where((d) => d.aRembourser)
        .fold(0.0, (sum, d) => sum + d.montantTotal);

    final totalRepasNourriture = depenses
        .where((d) => d.categorie == CategorieDepense.repas && d.aRembourser)
        .fold(0.0, (s, d) => s + d.montant);

    final totalPourboires = depenses
        .where((d) => d.aRembourser)
        .fold(0.0, (s, d) => s + d.pourboire);

    final totalAutres = depenses
        .where((d) => d.categorie != CategorieDepense.repas && d.aRembourser)
        .fold(0.0, (s, d) => s + d.montantTotal);

    // Charger les images de reçus disponibles
    final Map<String, pw.MemoryImage> imagesRecus = {};
    for (final d in depenses) {
      if (d.photoPath != null && d.photoPath!.isNotEmpty) {
        try {
          if (!kIsWeb) {
            final f = File(d.photoPath!);
            if (f.existsSync()) {
              final bytes = f.readAsBytesSync();
              imagesRecus[d.id] = pw.MemoryImage(bytes);
            }
          }
        } catch (_) {}
      }
    }

    // ─── PAGE 1 : ÉTAT DE COMPTE ET SOMMAIRE ─────────────────────────
    pdf.addPage(
      pw.Page(
        theme: theme,
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(36),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // EN-TÊTE
              pw.Container(
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  color: primary,
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'COMPTE DE DÉPENSES & REMBOURSEMENT',
                          style: pw.TextStyle(color: PdfColors.white, fontSize: 16, fontWeight: pw.FontWeight.bold),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          'Service Technique Route • Frais remboursables',
                          style: const pw.TextStyle(color: PdfColors.white, fontSize: 10),
                        ),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          'DATE : $dateStr',
                          style: pw.TextStyle(color: PdfColors.white, fontSize: 11, fontWeight: pw.FontWeight.bold),
                        ),
                        pw.Text(
                          'Total réclamé : ${totalRemboursement.toStringAsFixed(2)} \$',
                          style: pw.TextStyle(color: PdfColors.green100, fontSize: 11, fontWeight: pw.FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 14),

              // INFORMATIONS DEMANDEUR
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: greyBg,
                  borderRadius: pw.BorderRadius.circular(6),
                  border: pw.Border.all(color: PdfColors.grey300),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('TECHNICIEN DEMANDEUR :', style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey600)),
                        pw.Text(technicien, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
                        pw.Text('Camion de service Rayco Wylie', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
                      ],
                    ),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.green50,
                        borderRadius: pw.BorderRadius.circular(6),
                        border: pw.Border.all(color: PdfColors.green400),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text('MONTANT TOTAL À REMBOURSER', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: accentGreen)),
                          pw.Text(
                            '${totalRemboursement.toStringAsFixed(2)} \$ CAD',
                            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: accentGreen),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 16),

              pw.Text('DÉTAIL DES DÉPENSES ENGAGÉES', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: primary)),
              pw.SizedBox(height: 6),

              // TABLEAU DES DÉPENSES
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300),
                columnWidths: const {
                  0: pw.FixedColumnWidth(65),  // Date
                  1: pw.FixedColumnWidth(110), // Catégorie
                  2: pw.FlexColumnWidth(),     // Fournisseur & Description
                  3: pw.FixedColumnWidth(70),  // Nº Commande
                  4: pw.FixedColumnWidth(60),  // Reçu
                  5: pw.FixedColumnWidth(65),  // Montant
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      _th('DATE'),
                      _th('CATÉGORIE'),
                      _th('DESCRIPTION / FOURNISSEUR'),
                      _th('Nº CMD'),
                      _th('JUSTIF.'),
                      _th('MONTANT'),
                    ],
                  ),
                  ...depenses.map((d) {
                    final dStr = '${d.date.month.toString().padLeft(2, '0')}-${d.date.day.toString().padLeft(2, '0')}';
                    final aRecu = imagesRecus.containsKey(d.id) || (d.photoPath != null && d.photoPath!.isNotEmpty);
                    String descTexte = d.fournisseur.isNotEmpty ? '${d.fournisseur} - ${d.description}' : d.description;
                    if (d.categorie == CategorieDepense.repas || d.pourboire > 0) {
                      descTexte += '\n[Repas : ${d.montant.toStringAsFixed(2)} \$ | Pourboire : ${d.pourboire.toStringAsFixed(2)} \$]';
                    }

                    return pw.TableRow(
                      children: [
                        _td(dStr),
                        _td(d.libelleCategorie),
                        _td(descTexte),
                        _td(d.numeroCommande ?? '--'),
                        _td(aRecu ? 'OUI' : 'NON', color: aRecu ? PdfColors.green800 : PdfColors.grey600, isBold: aRecu),
                        _td('${d.montantTotal.toStringAsFixed(2)} \$', isBold: true, color: PdfColors.black),
                      ],
                    );
                  }),
                ],
              ),

              pw.SizedBox(height: 10),

              // ENCADRÉ VENTILATION COMPTABLE (REPAS & POURBOIRE)
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: pw.BorderRadius.circular(6),
                  border: pw.Border.all(color: PdfColors.grey300),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('VENTILATION COMPTABLE & DÉDUCTION FISCALE :', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: primary)),
                        pw.SizedBox(height: 3),
                        pw.Text(
                          '• Repas (Nourriture) : ${totalRepasNourriture.toStringAsFixed(2)} \$   • Pourboires déclarés : ${totalPourboires.toStringAsFixed(2)} \$   • Autres frais : ${totalAutres.toStringAsFixed(2)} \$',
                          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey800),
                        ),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('TOTAL DU RAPPORT', style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600)),
                        pw.Text('${totalRemboursement.toStringAsFixed(2)} \$ CAD', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: accentGreen)),
                      ],
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 10),

              // Règle
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(color: PdfColors.grey100, borderRadius: pw.BorderRadius.circular(4)),
                child: pw.Text(
                  'Déclaration : Les dépenses ci-dessus ont été engagées exclusivement dans le cadre de l\'exécution des interventions techniques sur la route. '
                  'Les reçus et factures originaux ont été scannés / photographiés pour contrôle comptable.',
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                ),
              ),

              pw.Spacer(),

              // SIGNATURES
              pw.Divider(color: PdfColors.grey400),
              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('SIGNATURE DU TECHNICIEN DEMANDEUR', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 25),
                      pw.Container(width: 170, decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 1)))),
                      pw.SizedBox(height: 2),
                      pw.Text(technicien, style: const pw.TextStyle(fontSize: 8)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('APPROBATION SUPERVISEUR / COMPTABILITÉ', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 25),
                      pw.Container(width: 170, decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 1)))),
                      pw.SizedBox(height: 2),
                      pw.Text('Bon pour remboursement', style: const pw.TextStyle(fontSize: 8)),
                    ],
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    // ─── PAGE 2 (SI PHOTOS DE REÇUS PRÉSENTES) : PIÈCES JUSTIFICATIVES
    if (imagesRecus.isNotEmpty) {
      pdf.addPage(
        pw.Page(
          theme: theme,
          pageFormat: PdfPageFormat.letter,
          margin: const pw.EdgeInsets.all(36),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('PIÈCES JUSTIFICATIVES & REÇUS EN CHANTIER', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: primary)),
                pw.SizedBox(height: 4),
                pw.Text('Photos des factures et preuves de paiement numérisées', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
                pw.Divider(color: PdfColors.grey300),
                pw.SizedBox(height: 10),

                pw.Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: depenses.where((d) => imagesRecus.containsKey(d.id)).map((d) {
                    final img = imagesRecus[d.id]!;
                    return pw.Container(
                      width: 250,
                      padding: const pw.EdgeInsets.all(8),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: PdfColors.grey300),
                        borderRadius: pw.BorderRadius.circular(6),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            (d.categorie == CategorieDepense.repas || d.pourboire > 0)
                                ? '${d.fournisseur} - ${d.montantTotal.toStringAsFixed(2)} \$ (Repas: ${d.montant.toStringAsFixed(2)} \$ + Pourb: ${d.pourboire.toStringAsFixed(2)} \$)'
                                : '${d.fournisseur} - ${d.montant.toStringAsFixed(2)} \$',
                            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                          ),
                          pw.Text(d.libelleCategorie, style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600)),
                          pw.SizedBox(height: 6),
                          pw.Container(
                            height: 180,
                            width: 234,
                            child: pw.Image(img, fit: pw.BoxFit.contain),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            );
          },
        ),
      );
    }

    return pdf.save();
  }

  static pw.Widget _th(String texte) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(texte, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
    );
  }

  static pw.Widget _td(String texte, {PdfColor? color, bool isBold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(
        texte,
        style: pw.TextStyle(
          fontSize: 8,
          color: color ?? PdfColors.black,
          fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  /// Dialogue proposant les 3 options d'export du compte de dépenses
  static Future<void> afficherDialogueExport(
    BuildContext context,
    List<Depense> depenses, {
    String technicien = 'Pierre-Olivier Patry',
  }) async {
    final total = depenses.where((d) => d.aRembourser).fold(0.0, (sum, d) => sum + d.montantTotal);

    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
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
                    backgroundColor: Colors.teal.shade50,
                    child: const Icon(Icons.receipt_long, color: Colors.teal),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Rapport de Remboursement - $technicien',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        Text(
                          '${depenses.length} dépenses • Total réclamé : ${total.toStringAsFixed(2)} \$',
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),

              // OPTION 1 : ENREGISTRER SOUS... (EXPLORATEUR)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                leading: CircleAvatar(
                  backgroundColor: Colors.blue.shade50,
                  child: const Icon(Icons.folder_open, color: Colors.blueAccent),
                ),
                title: const Text('Enregistrer le .PDF (Choisir l\'emplacement)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: const Text('Ouvre l\'explorateur pour choisir le dossier et le nom du fichier.', style: TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: () {
                  Navigator.pop(ctx);
                  enregistrerPdfEmplacementChoisi(context, depenses, technicien: technicien);
                },
              ),

              // OPTION 2 : ENVOYER PAR COURRIEL AVEC OUTLOOK
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                leading: CircleAvatar(
                  backgroundColor: Colors.teal.shade50,
                  child: const Icon(Icons.mail_outline, color: Colors.teal),
                ),
                title: const Text('Envoyer par courriel avec Outlook', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: const Text('Ouvre Outlook avec le PDF de remboursement joint pour la comptabilité.', style: TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: () {
                  Navigator.pop(ctx);
                  envoyerParOutlook(context, depenses, technicien: technicien);
                },
              ),

              // OPTION 3 : APERÇU ET IMPRESSION
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                leading: CircleAvatar(
                  backgroundColor: Colors.purple.shade50,
                  child: const Icon(Icons.print_outlined, color: Colors.purple),
                ),
                title: const Text('Aperçu & Imprimer', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: const Text('Visualiser toutes les pages avec les reçus et imprimer.', style: TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: () {
                  Navigator.pop(ctx);
                  imprimerApercuPdf(context, depenses, technicien: technicien);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> enregistrerPdfEmplacementChoisi(
    BuildContext context,
    List<Depense> depenses, {
    String technicien = 'Pierre-Olivier Patry',
  }) async {
    try {
      final now = DateTime.now();
      final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final techSafe = technicien.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final nomFichierSuggere = 'CompteDeDepenses_${techSafe}_$dateStr.pdf';

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⏳ Génération du rapport de remboursement...'), duration: Duration(seconds: 1)),
        );
      }

      final pdfBytes = await genererBytesPdf(depenses, technicien: technicien);

      final Uri? uriChoisi = await FilePicker.saveFile(
        dialogTitle: 'Choisir l\'emplacement où enregistrer le compte de dépenses',
        fileName: nomFichierSuggere,
        bytes: pdfBytes,
        mimeType: 'application/pdf',
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
          if (!f.existsSync() || f.lengthSync() == 0) {
            await f.writeAsBytes(pdfBytes);
          }
        } catch (_) {}

        if (!kIsWeb && Platform.isWindows) {
          try {
            await Process.run('explorer.exe', ['/select,', cheminFinal]);
          } catch (_) {}
        }
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Rapport de dépenses enregistré : $cheminFinal'),
            backgroundColor: Colors.green.shade700,
            duration: const Duration(seconds: 5),
            action: (!kIsWeb && Platform.isWindows)
                ? SnackBarAction(
                    label: 'Ouvrir',
                    textColor: Colors.white,
                    onPressed: () => Process.run('explorer.exe', ['/select,', cheminFinal]),
                  )
                : null,
          ),
        );
      }
    } catch (e) {
      debugPrint('Erreur sauvegarde PDF dépenses: $e');
    }
  }

  static Future<void> envoyerParOutlook(
    BuildContext context,
    List<Depense> depenses, {
    String technicien = 'Pierre-Olivier Patry',
    String courrielCompta = 'comptabilite@raycowylie.com',
  }) async {
    try {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⏳ Préparation du PDF et d\'Outlook...'), duration: Duration(seconds: 1)),
        );
      }

      final pdfBytes = await genererBytesPdf(depenses, technicien: technicien);
      final now = DateTime.now();
      final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final total = depenses.where((d) => d.aRembourser).fold(0.0, (sum, d) => sum + d.montantTotal);
      final totalRepas = depenses.where((d) => d.categorie == CategorieDepense.repas && d.aRembourser).fold(0.0, (s, d) => s + d.montant);
      final totalPourboires = depenses.where((d) => d.aRembourser).fold(0.0, (s, d) => s + d.pourboire);
      final totalAutres = depenses.where((d) => d.categorie != CategorieDepense.repas && d.aRembourser).fold(0.0, (s, d) => s + d.montantTotal);
      final techSafe = technicien.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');

      final subject = 'Demande de remboursement dépenses - $technicien - $dateStr';
      final body = '''Bonjour au service de la comptabilité,

Veuillez trouver ci-joint ma demande de remboursement de compte de dépenses pour les interventions route.

RÉSUMÉ DE LA RÉCLAMATION :
• Technicien : $technicien
• Date de la demande : $dateStr
• Nombre de dépenses : ${depenses.length}
• Repas (Nourriture) : ${totalRepas.toStringAsFixed(2)} \$ CAD
• Pourboires déclarés : ${totalPourboires.toStringAsFixed(2)} \$ CAD
• Autres frais de route : ${totalAutres.toStringAsFixed(2)} \$ CAD
• MONTANT TOTAL RÉCLAMÉ : ${total.toStringAsFixed(2)} \$ CAD

Le rapport détaillé comprenant la ventilation repas/pourboire et les photos des reçus numérisés est attaché en format PDF.

Merci de procéder au virement de remboursement.

Cordialement,
$technicien
Technicien de service''';

      if (!kIsWeb && Platform.isWindows) {
        final userProfile =
            Platform.environment['USERPROFILE'] ?? 'C:\\Users\\Default';
        final targetDir = Directory('$userProfile\\Documents\\AppTechnicien\\PDF');
        if (!await targetDir.exists()) {
          await targetDir.create(recursive: true);
        }

        final pdfPath = '${targetDir.path}\\CompteDeDepenses_${techSafe}_$dateStr.pdf';
        final pdfFile = File(pdfPath);
        await pdfFile.writeAsBytes(pdfBytes);

        final outlookPath = RapportPdfService.trouverOutlookPath();
        if (outlookPath != null) {
          final uriMailto = Uri(
            scheme: 'mailto',
            path: courrielCompta,
            queryParameters: {
              'subject': subject,
              'body': body,
            },
          );
          final mailParam = uriMailto.toString().replaceFirst('mailto:', '');

          await Process.start(
            outlookPath,
            [
              '/c',
              'ipm.note',
              '/a',
              pdfPath,
              '/m',
              mailParam,
            ],
            mode: ProcessStartMode.detached,
          );

          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('📧 Outlook ouvert avec le compte de dépenses joint ($courrielCompta) !'),
                backgroundColor: Colors.teal.shade700,
                duration: const Duration(seconds: 4),
              ),
            );
          }
          return;
        }
      }

      // Fallback
      final emailLaunchUri = Uri(
        scheme: 'mailto',
        path: courrielCompta,
        queryParameters: {
          'subject': subject,
          'body': body,
        },
      );
      if (await canLaunchUrl(emailLaunchUri)) {
        await launchUrl(emailLaunchUri);
      }

      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: 'CompteDeDepenses_${techSafe}_$dateStr.pdf',
      );
    } catch (e) {
      debugPrint('Erreur envoi Outlook dépenses: $e');
    }
  }

  /// Enregistre automatiquement le compte de dépenses sur disque dans Documents\RaycoWylie_Documents\Depenses\
  static Future<String?> sauvegarderPdfSurDisque(List<Depense> depenses, String technicien, Uint8List pdfBytes) async {
    if (kIsWeb) return null;
    try {
      final now = DateTime.now();
      final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final techSafe = technicien.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final fileName = 'CompteDeDepenses_${techSafe}_$dateStr.pdf';

      if (!kIsWeb && Platform.isWindows) {
        final userProfile = Platform.environment['USERPROFILE'] ?? 'C:\\Users\\Default';
        final targetDir = Directory('$userProfile\\Documents\\RaycoWylie_Documents\\Depenses');
        if (!await targetDir.exists()) {
          await targetDir.create(recursive: true);
        }
        final f = File('${targetDir.path}\\$fileName');
        await f.writeAsBytes(pdfBytes);
        return f.path;
      } else {
        final temp = Directory('${Directory.systemTemp.path}/Depenses');
        if (!await temp.exists()) await temp.create(recursive: true);
        final f = File('${temp.path}/$fileName');
        await f.writeAsBytes(pdfBytes);
        return f.path;
      }
    } catch (e) {
      debugPrint('Erreur sauvegarde disque dépenses: $e');
      return null;
    }
  }

  /// Option 3 : Visualiser et imprimer le compte de dépenses via le lecteur PDF natif Windows ou Printing.layoutPdf
  static Future<void> imprimerApercuPdf(
    BuildContext context,
    List<Depense> depenses, {
    String technicien = 'Pierre-Olivier Patry',
  }) async {
    try {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⏳ Préparation du compte de dépenses pour visualisation...'), duration: Duration(seconds: 1)),
        );
      }
      final pdfBytes = await genererBytesPdf(depenses, technicien: technicien);

      if (!kIsWeb && Platform.isWindows) {
        // Sous Windows : Sauvegarder sur disque et ouvrir immédiatement dans le lecteur PDF officiel Windows
        final path = await sauvegarderPdfSurDisque(depenses, technicien, pdfBytes);
        if (path != null) {
          await RapportPdfService.ouvrirFichier(path);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('📄 Compte de dépenses ouvert dans votre lecteur Windows :\n$path'),
                backgroundColor: Colors.teal.shade800,
                duration: const Duration(seconds: 5),
                action: SnackBarAction(
                  label: 'Dossier',
                  textColor: Colors.white,
                  onPressed: () => RapportPdfService.selectionnerDansExplorateur(path),
                ),
              ),
            );
          }
          return;
        }
      }

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdfBytes,
        name: 'CompteDeDepenses_$technicien.pdf',
      );
    } catch (e) {
      debugPrint('Erreur aperçu dépenses: $e');
    }
  }
}

// ============================================================================
// 📱 ÉCRAN PRINCIPAL : COMPTES DE DÉPENSES ROUTE
// ============================================================================

class DepenseScreen extends StatefulWidget {
  final bool initialementDeverrouille;
  final String? technicienInitial;

  const DepenseScreen({
    super.key,
    this.initialementDeverrouille = false,
    this.technicienInitial,
  });

  @override
  State<DepenseScreen> createState() => _DepenseScreenState();
}

class _DepenseScreenState extends State<DepenseScreen> {
  final DepenseService _service = DepenseService.instance;
  bool _isLoading = true;

  // 👷 Techniciens & Gestion des comptes indépendants
  List<Technicien> _techniciens = [
    Technicien(id: 't_popatry', nom: 'Pierre-Olivier Patry', numeroCamion: 'Camion #102'),
    Technicien(id: 't_hestin', nom: 'David Hestin', numeroCamion: 'Camion #101'),
    Technicien(id: 't_allie', nom: 'Jean-François Allie', numeroCamion: 'Camion #103'),
  ];
  Technicien? _technicienSelectionne;

  // 🔐 Sécurité par code NIP (4 chiffres)
  late bool _estDeverrouille;

  @override
  void initState() {
    super.initState();
    _estDeverrouille = widget.initialementDeverrouille;
    if (_technicienSelectionne == null) {
      if (widget.technicienInitial != null) {
        _technicienSelectionne = _techniciens.firstWhere(
          (t) => t.nom.toLowerCase() == widget.technicienInitial!.toLowerCase(),
          orElse: () => _techniciens.first,
        );
      } else {
        _technicienSelectionne = _techniciens.first;
      }
    }
    _charger();
  }

  Future<void> _charger() async {
    // 1. Synchroniser avec les techniciens déjà en mémoire si disponibles
    if (TechnicienService.instance.techniciens.isNotEmpty) {
      _techniciens = List.from(TechnicienService.instance.techniciens);
    }

    // 2. Définir le technicien sélectionné
    if (widget.technicienInitial != null) {
      _technicienSelectionne = _techniciens.firstWhere(
        (t) => t.nom.toLowerCase() == widget.technicienInitial!.toLowerCase(),
        orElse: () => _techniciens.first,
      );
    } else {
      _technicienSelectionne ??= _techniciens.first;
    }

    // 3. Charger les dépenses (synchrone si déjà initialisé en cache/mock)
    await _service.getDepenses();

    if (mounted) {
      setState(() => _isLoading = false);
    }

    // Mettre à jour en arrière-plan si le service réseau est joignable
    try {
      final techs = await TechnicienService.instance.getTechniciens();
      if (techs.isNotEmpty && mounted) {
        setState(() => _techniciens = techs);
      }
    } catch (_) {}
  }

  void _changerTechnicien(Technicien tech) {
    if (_technicienSelectionne?.nom == tech.nom) return;
    setState(() {
      _technicienSelectionne = tech;
      _estDeverrouille = false; // Verrouiller immédiatement pour sécurité anti-tampering
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🔒 Compte de ${tech.nom} sélectionné (Protégé par NIP).'),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.blueGrey.shade800,
      ),
    );
  }

  /// Demande et vérifie le code NIP (4 chiffres) du technicien actif.
  /// Si la session est déjà déverrouillée, retourne true sans redemander.
  /// En cas de succès, marque la session comme déverrouillée (_estDeverrouille = true).
  Future<bool> _demanderNipSecurise({String action = 'modifier ce compte de dépenses'}) async {
    if (_estDeverrouille) return true;

    final String nomTech = _technicienSelectionne?.nom ?? 'Pierre-Olivier Patry';
    final String camion = _technicienSelectionne?.numeroCamion ?? 'Camion #102';

    final nipCtrl = TextEditingController();
    bool cacherNip = true;
    String? messageErreur;
    bool enVerification = false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          Future<void> valider() async {
            final code = nipCtrl.text.trim();
            if (code.length != 4) {
              setDlgState(() {
                messageErreur = 'Le NIP doit contenir exactement 4 chiffres.';
              });
              return;
            }

            setDlgState(() {
              enVerification = true;
              messageErreur = null;
            });

            final valide = await _service.verifierNip(nomTech, code);

            if (!dialogCtx.mounted) return;

            if (valide) {
              Navigator.pop(dialogCtx, true);
            } else {
              setDlgState(() {
                enVerification = false;
                messageErreur = 'Code NIP incorrect pour $nomTech. Réessayez.';
                nipCtrl.clear();
              });
            }
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD1001F).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.lock_rounded, color: Color(0xFFD1001F), size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Protection par NIP',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                      ),
                      Text(
                        'Sécurisation du compte technicien',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.person, size: 20, color: Colors.teal),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(nomTech, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              Text(camion, style: const TextStyle(fontSize: 11, color: Colors.black54)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Entrez le code NIP (4 chiffres) associé à ce compte pour $action.',
                    style: const TextStyle(fontSize: 12.5, color: Colors.black87),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: nipCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    autofocus: true,
                    obscureText: cacherNip,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 22, letterSpacing: 8, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      hintText: '••••',
                      counterText: '',
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      suffixIcon: IconButton(
                        icon: Icon(cacherNip ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        onPressed: () => setDlgState(() => cacherNip = !cacherNip),
                      ),
                    ),
                    onSubmitted: (_) => valider(),
                  ),
                  if (messageErreur != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              messageErreur!,
                              style: TextStyle(color: Colors.red.shade900, fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, size: 14, color: Colors.blue),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'NIPs par défaut : David (1010), Pierre-Olivier (1020), Jean-François (1030). Passe-partout : 9999.',
                            style: TextStyle(fontSize: 10, color: Colors.blueGrey),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx, false),
                child: const Text('Annuler'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD1001F),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: enVerification ? null : valider,
                child: Text(enVerification ? 'Vérification...' : 'Déverrouiller'),
              ),
            ],
          );
        },
      ),
    );

    if (result == true) {
      if (!mounted) return true;
      setState(() => _estDeverrouille = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🔓 Compte de $nomTech déverrouillé avec succès.'),
          backgroundColor: Colors.teal.shade800,
          duration: const Duration(seconds: 2),
        ),
      );
      return true;
    }

    return false;
  }

  /// Modal permettant au technicien de modifier son code NIP
  Future<void> _changerNipModal() async {
    final String nomTech = _technicienSelectionne?.nom ?? 'Pierre-Olivier Patry';
    final nipActuelCtrl = TextEditingController();
    final nouveauNipCtrl = TextEditingController();
    final confirmNipCtrl = TextEditingController();
    String? erreur;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.pin, color: Colors.teal),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Modifier le NIP ($nomTech)',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nipActuelCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Code NIP actuel *',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: nouveauNipCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Nouveau code NIP (4 chiffres) *',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: confirmNipCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Confirmer le nouveau NIP *',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  if (erreur != null) ...[
                    const SizedBox(height: 8),
                    Text(erreur!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700, foregroundColor: Colors.white),
                onPressed: () async {
                  final actuel = nipActuelCtrl.text.trim();
                  final nouveau = nouveauNipCtrl.text.trim();
                  final confirm = confirmNipCtrl.text.trim();

                  final checkActuel = await _service.verifierNip(nomTech, actuel);
                  if (!checkActuel) {
                    setModalState(() => erreur = 'Code NIP actuel incorrect.');
                    return;
                  }
                  if (nouveau.length != 4 || int.tryParse(nouveau) == null) {
                    setModalState(() => erreur = 'Le nouveau NIP doit contenir exactement 4 chiffres.');
                    return;
                  }
                  if (nouveau != confirm) {
                    setModalState(() => erreur = 'Les deux nouveaux NIPs ne correspondent pas.');
                    return;
                  }

                  await _service.setNipPourTechnicien(nomTech, nouveau);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('✅ Code NIP de $nomTech modifié avec succès !'),
                        backgroundColor: Colors.green.shade700,
                      ),
                    );
                  }
                },
                child: const Text('Enregistrer'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Ouvre directement le scanner d'appareil photo / sélection et lance l'analyse automatique IA
  Future<void> _scannerFactureDirectement() async {
    // Protection par NIP
    if (!await _demanderNipSecurise(action: 'scanner une facture pour ce compte')) return;
    if (!mounted) return;

    final chemin = await _service.capturerOuSelectionnerPhotoRecu(context);
    if (chemin == null) return;

    if (!mounted) return;

    // Afficher une boîte de dialogue de chargement avec animation pendant l'analyse OCR
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 28.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: const CircularProgressIndicator(strokeWidth: 3, color: Colors.teal),
                ),
                const SizedBox(height: 20),
                const Text(
                  '🔍 Analyse de la facture...',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Extraction automatique du montant, taxes, date et commerçant en cours...',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final result = await ReceiptScannerService.instance.analyserFacture(filePath: chemin);

    if (mounted) {
      Navigator.pop(context); // Fermer le loader
      await _ajouterDepenseModal(preRempli: result, photoInitiale: chemin);
    }
  }

  Future<void> _ajouterDepenseModal({
    ReceiptScanResult? preRempli,
    String? photoInitiale,
  }) async {
    // Protection par NIP
    if (!await _demanderNipSecurise(action: 'ajouter une dépense à ce compte')) return;
    if (!mounted) return;

    final nomTechActuel = _technicienSelectionne?.nom ?? 'Pierre-Olivier Patry';

    final montantCtrl = TextEditingController(
      text: (preRempli?.montantTotal != null && preRempli!.montantTotal! > 0)
          ? preRempli.montantTotal!.toStringAsFixed(2)
          : '',
    );
    final pourboireCtrl = TextEditingController(
      text: (preRempli?.pourboire != null && preRempli!.pourboire! > 0)
          ? preRempli.pourboire!.toStringAsFixed(2)
          : '0.00',
    );
    final descriptionCtrl = TextEditingController(
      text: preRempli?.description ?? '',
    );
    final fournisseurCtrl = TextEditingController(
      text: preRempli?.fournisseur ?? '',
    );
    final commandeCtrl = TextEditingController(
      text: preRempli?.numeroCommande ?? '',
    );
    CategorieDepense categorie = preRempli?.categorie ?? CategorieDepense.repas;
    DateTime dateDepense = preRempli?.date ?? DateTime.now();
    String modePaiement = 'Personnel (À rembourser)';
    String? photoSelectionnee = photoInitiale;
    ReceiptScanResult? dernierResultatScan = preRempli;
    bool isScanning = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          final isAndroid = !kIsWeb && Platform.isAndroid;
          final isWindows = !kIsWeb && Platform.isWindows;
          final bool estRepas = categorie == CategorieDepense.repas;

          // Fonction de numérisation et scan automatique de reçu
          Future<void> capturerEtAnalyser({ImageSource source = ImageSource.camera}) async {
            setDlgState(() => isScanning = true);
            try {
              String? chemin;
              if (!kIsWeb && Platform.isAndroid) {
                final picker = ImagePicker();
                final xfile = await picker.pickImage(
                  source: source,
                  maxWidth: 1600,
                  maxHeight: 1600,
                  imageQuality: 80,
                );
                chemin = xfile?.path;
              } else {
                chemin = await _service.capturerOuSelectionnerPhotoRecu(context);
              }

              if (chemin != null) {
                photoSelectionnee = chemin;
                final scanResult = await ReceiptScannerService.instance.analyserFacture(filePath: chemin);
                dernierResultatScan = scanResult;

                // Remplissage automatique des champs sans avoir à les entrer !
                if ((scanResult.montantTotal ?? 0) > 0) {
                  montantCtrl.text = scanResult.montantTotal!.toStringAsFixed(2);
                }
                if (scanResult.pourboire != null && scanResult.pourboire! > 0) {
                  pourboireCtrl.text = scanResult.pourboire!.toStringAsFixed(2);
                }
                if (scanResult.fournisseur != null && scanResult.fournisseur!.isNotEmpty) {
                  fournisseurCtrl.text = scanResult.fournisseur!;
                }
                if (scanResult.categorie != null) {
                  categorie = scanResult.categorie!;
                }
                if (scanResult.description != null && scanResult.description!.isNotEmpty) {
                  descriptionCtrl.text = scanResult.description!;
                }
                if (scanResult.numeroCommande != null && scanResult.numeroCommande!.isNotEmpty) {
                  commandeCtrl.text = scanResult.numeroCommande!;
                }
                if (scanResult.date != null) {
                  dateDepense = scanResult.date!;
                }
              }
            } catch (e) {
              debugPrint('Erreur scan reçu: $e');
            } finally {
              setDlgState(() => isScanning = false);
            }
          }

          // Test avec un reçu d'exemple
          void testerExemple(({String nom, String texte, String icone}) ex) {
            setDlgState(() => isScanning = true);
            Future.delayed(const Duration(milliseconds: 300), () {
              final scanResult = ReceiptScannerService.instance.parseReceiptText(ex.texte);
              dernierResultatScan = scanResult;
              if ((scanResult.montantTotal ?? 0) > 0) {
                montantCtrl.text = scanResult.montantTotal!.toStringAsFixed(2);
              }
              if (scanResult.pourboire != null && scanResult.pourboire! > 0) {
                pourboireCtrl.text = scanResult.pourboire!.toStringAsFixed(2);
              }
              if (scanResult.fournisseur != null && scanResult.fournisseur!.isNotEmpty) {
                fournisseurCtrl.text = scanResult.fournisseur!;
              }
              if (scanResult.categorie != null) {
                categorie = scanResult.categorie!;
              }
              if (scanResult.description != null && scanResult.description!.isNotEmpty) {
                descriptionCtrl.text = scanResult.description!;
              }
              if (scanResult.numeroCommande != null && scanResult.numeroCommande!.isNotEmpty) {
                commandeCtrl.text = scanResult.numeroCommande!;
              }
              if (scanResult.date != null) {
                dateDepense = scanResult.date!;
              }
              setDlgState(() => isScanning = false);
            });
          }

          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.teal.shade100,
                        child: const Icon(Icons.receipt_long, color: Colors.teal),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Nouvelle Dépense en Chantier',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            Text(
                              'Compte : $nomTechActuel',
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                    ],
                  ),
                  const Divider(height: 16),

                  // ─── 📸 BANNIÈRE ANALYSE AUTOMATIQUE DE LA FACTURE ─────
                  if (isScanning) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.teal.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.teal.shade300),
                      ),
                      child: const Row(
                        children: [
                          CircularProgressIndicator(strokeWidth: 3, color: Colors.teal),
                          SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '🔍 Analyse automatique de la facture...',
                                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal, fontSize: 13),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Extraction du commerçant, montant, taxes et date...',
                                  style: TextStyle(fontSize: 11, color: Colors.black87),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ] else if (dernierResultatScan != null) ...[
                    // Résultat de l'analyse affiché
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: dernierResultatScan!.isReadable ? const Color(0xFFF0FDF4) : const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: dernierResultatScan!.isReadable ? const Color(0xFF86EFAC) : const Color(0xFFFDE68A),
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                dernierResultatScan!.isReadable
                                    ? Icons.check_circle_rounded
                                    : Icons.warning_amber_rounded,
                                color: dernierResultatScan!.isReadable ? Colors.green.shade700 : Colors.orange.shade800,
                                size: 22,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  dernierResultatScan!.isReadable
                                      ? 'Facture analysée avec succès par IA !'
                                      : 'Facture difficile à lire ou floue',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: dernierResultatScan!.isReadable ? Colors.green.shade900 : Colors.orange.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            dernierResultatScan!.messageStatut,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: dernierResultatScan!.isReadable ? Colors.green.shade900 : Colors.orange.shade900,
                            ),
                          ),
                          if (dernierResultatScan!.isReadable) ...[
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                if (dernierResultatScan!.fournisseur != null)
                                  Chip(
                                    labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                                    avatar: const Icon(Icons.store, size: 14, color: Colors.teal),
                                    label: Text(dernierResultatScan!.fournisseur!, style: const TextStyle(fontSize: 11)),
                                    backgroundColor: Colors.white,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                if (dernierResultatScan!.montantTotal != null)
                                  Chip(
                                    labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                                    avatar: const Icon(Icons.attach_money, size: 14, color: Colors.green),
                                    label: Text('${dernierResultatScan!.montantTotal!.toStringAsFixed(2)} \$ CAD', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                    backgroundColor: Colors.white,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                if (dernierResultatScan!.tps != null)
                                  Chip(
                                    labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                                    label: Text('TPS: ${dernierResultatScan!.tps!.toStringAsFixed(2)} \$', style: const TextStyle(fontSize: 10)),
                                    backgroundColor: Colors.white,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                if (dernierResultatScan!.tvq != null)
                                  Chip(
                                    labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                                    label: Text('TVQ: ${dernierResultatScan!.tvq!.toStringAsFixed(2)} \$', style: const TextStyle(fontSize: 10)),
                                    backgroundColor: Colors.white,
                                    visualDensity: VisualDensity.compact,
                                  ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton.icon(
                                icon: const Icon(Icons.refresh, size: 16),
                                label: const Text('Rescanner une photo', style: TextStyle(fontSize: 11)),
                                onPressed: () => capturerEtAnalyser(source: ImageSource.camera),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ] else ...[
                    // Carte héro d'invitation à scanner
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.teal.shade800, Colors.teal.shade900],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.teal.withValues(alpha: 0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.document_scanner_rounded, color: Colors.white, size: 24),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Scan & Remplissage Automatique IA',
                                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13.5),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Prenez une photo de votre facture : elle sera automatiquement analysée pour remplir le commerce, les montants, taxes et dates.',
                            style: TextStyle(color: Colors.white70, fontSize: 11.5),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              ElevatedButton.icon(
                                icon: Icon(isAndroid ? Icons.camera_alt : Icons.upload_file, size: 16),
                                label: Text(isAndroid ? 'Prendre photo' : 'Sélectionner reçu'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: Colors.teal.shade900,
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                ),
                                onPressed: () => capturerEtAnalyser(source: ImageSource.camera),
                              ),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.science_outlined, size: 16, color: Colors.white),
                                label: const Text('Exemples de test', style: TextStyle(color: Colors.white, fontSize: 12)),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Colors.white70),
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                ),
                                onPressed: () {
                                  showModalBottomSheet<void>(
                                    context: context,
                                    isScrollControlled: true,
                                    builder: (subCtx) => SafeArea(
                                      child: SingleChildScrollView(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Padding(
                                              padding: EdgeInsets.all(16.0),
                                              child: Text('Tester avec un exemple de reçu', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                            ),
                                            ...ReceiptScannerService.exemplesRecus.map((ex) {
                                              return ListTile(
                                                leading: Text(ex.icone, style: const TextStyle(fontSize: 22)),
                                                title: Text(ex.nom, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                                onTap: () {
                                                  Navigator.pop(subCtx);
                                                  testerExemple(ex);
                                                },
                                              );
                                            }),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // ─── 📅 DATE DE LA DÉPENSE (DÉTECTÉE OU CHOISIE) ───────
                  InkWell(
                    onTap: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: dateDepense,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                      );
                      if (d != null) {
                        setDlgState(() => dateDepense = d);
                      }
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.grey.shade50,
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today_rounded, size: 18, color: Colors.teal),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Date de la dépense / facture *', style: TextStyle(fontSize: 10, color: Colors.grey)),
                              Text(
                                '${dateDepense.year}-${dateDepense.month.toString().padLeft(2, '0')}-${dateDepense.day.toString().padLeft(2, '0')}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ],
                          ),
                          const Spacer(),
                          const Icon(Icons.edit_calendar, size: 18, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 1. CHOIX DE LA CATÉGORIE
                  DropdownButtonFormField<CategorieDepense>(
                    key: ValueKey(categorie),
                    initialValue: categorie,
                    decoration: const InputDecoration(
                      labelText: 'Catégorie de dépense *',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: CategorieDepense.values.map((c) {
                      final depDummy = Depense(
                        id: '',
                        date: DateTime.now(),
                        technicien: '',
                        montant: 0,
                        categorie: c,
                        description: '',
                      );
                      return DropdownMenuItem(
                        value: c,
                        child: Row(
                          children: [
                            Icon(depDummy.icone, color: depDummy.couleur, size: 18),
                            const SizedBox(width: 8),
                            Text(depDummy.libelleCategorie),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setDlgState(() {
                          categorie = val;
                          if (val != CategorieDepense.repas) {
                            pourboireCtrl.text = '0.00';
                          }
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 12),

                  // 2. CHAMPS MONTANT ET FOURNISSEUR (AVEC SÉPARATION DU POURBOIRE POUR REPAS)
                  if (estRepas) ...[
                    TextField(
                      controller: fournisseurCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Restaurant / Établissement *',
                        prefixIcon: Icon(Icons.restaurant, color: Colors.orange),
                        hintText: 'St-Hubert, Tim Hortons, Subway...',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: montantCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            onChanged: (_) => setDlgState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'Montant Repas (\$ CAD) *',
                              prefixIcon: Icon(Icons.fastfood, color: Colors.orange),
                              hintText: 'ex: 22.50',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: pourboireCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            onChanged: (_) => setDlgState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'Pourboire (\$ CAD)',
                              prefixIcon: Icon(Icons.volunteer_activism, color: Colors.indigo),
                              hintText: 'ex: 3.50',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Boutons de pourboire rapide
                    Row(
                      children: [
                        const Text('Pourboire rapide :', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 6),
                        ...[0, 10, 15, 18, 20].map((pct) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(4),
                              onTap: () {
                                final mVal = double.tryParse(montantCtrl.text.replaceAll(',', '.').trim()) ?? 0.0;
                                final tip = (mVal * pct / 100.0);
                                pourboireCtrl.text = tip.toStringAsFixed(2);
                                setDlgState(() {});
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.indigo.shade50,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.indigo.shade200),
                                ),
                                child: Text(
                                  pct == 0 ? '0 \$' : '$pct %',
                                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.indigo.shade900),
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Encadré total calculé
                    Builder(builder: (c) {
                      final mVal = double.tryParse(montantCtrl.text.replaceAll(',', '.').trim()) ?? 0.0;
                      final pVal = double.tryParse(pourboireCtrl.text.replaceAll(',', '.').trim()) ?? 0.0;
                      final totalLigne = mVal + pVal;
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Text(
                                '🍽️ Repas : ${mVal.toStringAsFixed(2)} \$  +  🪙 Pourb. : ${pVal.toStringAsFixed(2)} \$',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.orange.shade900),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Total : ${totalLigne.toStringAsFixed(2)} \$',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.orange.shade900),
                            ),
                          ],
                        ),
                      );
                    }),
                  ] else ...[
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: montantCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Montant (\$ CAD) *',
                              prefixIcon: Icon(Icons.attach_money, color: Colors.green),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: fournisseurCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Fournisseur / Commerce',
                              prefixIcon: Icon(Icons.store),
                              hintText: 'Pétro-Can, BMR...',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),

                  // DESCRIPTION & Nº COMMANDE
                  TextField(
                    controller: descriptionCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Description / Raison du frais *',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: commandeCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Nº Commande / Facture',
                            prefixIcon: Icon(Icons.tag),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: modePaiement,
                          decoration: const InputDecoration(
                            labelText: 'Paiement',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: const [
                            DropdownMenuItem(value: 'Personnel (À rembourser)', child: Text('Personnel (Remb.)', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: 'Carte Entreprise', child: Text('Carte Entreprise', overflow: TextOverflow.ellipsis)),
                          ],
                          onChanged: (val) {
                            if (val != null) setDlgState(() => modePaiement = val);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ─── PHOTO DU REÇU ATTACHÉE ───────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.blueGrey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(isAndroid ? Icons.camera_alt : Icons.folder_open, color: Colors.indigo, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              photoSelectionnee != null ? 'Reçu photographié' : 'Preuve / Photo du reçu',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (photoSelectionnee != null) ...[
                          Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  width: 60,
                                  height: 60,
                                  color: Colors.grey.shade300,
                                  child: (!kIsWeb && File(photoSelectionnee!).existsSync())
                                      ? Image.file(File(photoSelectionnee!), fit: BoxFit.cover)
                                      : const Icon(Icons.receipt),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('✅ Reçu attaché avec succès !', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 12)),
                                    Text(
                                      photoSelectionnee!.split(RegExp(r'[\\/]')).last,
                                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                tooltip: 'Supprimer photo',
                                onPressed: () => setDlgState(() {
                                  photoSelectionnee = null;
                                  dernierResultatScan = null;
                                }),
                              ),
                            ],
                          ),
                        ] else ...[
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  icon: Icon(isAndroid ? Icons.camera_alt : Icons.file_upload_outlined),
                                  label: Text(
                                    isAndroid ? 'Prendre photo (Caméra)' : 'Sélectionner photo reçu',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.indigo.shade800,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                  ),
                                  onPressed: () => capturerEtAnalyser(source: ImageSource.camera),
                                ),
                              ),
                              if (isWindows) ...[
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  icon: const Icon(Icons.folder, size: 18),
                                  label: const Text('Dossier'),
                                  onPressed: () => _service.ouvrirDossierRecusDansWindows(),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  // BOUTON VALIDER
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.check, size: 20),
                      label: const Text('Enregistrer la dépense', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () async {
                        final m = double.tryParse(montantCtrl.text.replaceAll(',', '.').trim());
                        if (m == null || m <= 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Veuillez entrer un montant valide.')),
                          );
                          return;
                        }
                        double p = 0.0;
                        if (categorie == CategorieDepense.repas) {
                          p = double.tryParse(pourboireCtrl.text.replaceAll(',', '.').trim()) ?? 0.0;
                          if (p < 0) p = 0.0;
                        }
                        if (descriptionCtrl.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Veuillez entrer une description.')),
                          );
                          return;
                        }

                        final d = Depense(
                          id: 'dep_${DateTime.now().millisecondsSinceEpoch}',
                          date: dateDepense,
                          technicien: nomTechActuel,
                          montant: m,
                          pourboire: p,
                          categorie: categorie,
                          description: descriptionCtrl.text.trim(),
                          fournisseur: fournisseurCtrl.text.trim(),
                          numeroCommande: commandeCtrl.text.trim().isNotEmpty ? commandeCtrl.text.trim() : null,
                          modePaiement: modePaiement,
                          photoPath: photoSelectionnee,
                        );

                        await _service.ajouterDepense(d);
                        if (ctx.mounted) Navigator.pop(ctx);
                        await _charger();
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Modal pour éditer une dépense existante
  Future<void> _editerDepenseModal(Depense depenseInitiale) async {
    // Protection par NIP
    if (!await _demanderNipSecurise(action: 'modifier cette dépense')) return;
    if (!mounted) return;

    final montantCtrl = TextEditingController(
      text: depenseInitiale.montant > 0 ? depenseInitiale.montant.toStringAsFixed(2) : '',
    );
    final pourboireCtrl = TextEditingController(
      text: depenseInitiale.pourboire > 0 ? depenseInitiale.pourboire.toStringAsFixed(2) : '0.00',
    );
    final descriptionCtrl = TextEditingController(text: depenseInitiale.description);
    final fournisseurCtrl = TextEditingController(text: depenseInitiale.fournisseur);
    final commandeCtrl = TextEditingController(text: depenseInitiale.numeroCommande ?? '');
    CategorieDepense categorie = depenseInitiale.categorie;
    DateTime dateDepense = depenseInitiale.date;
    String modePaiement = depenseInitiale.modePaiement;
    String? photoSelectionnee = depenseInitiale.photoPath;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          final isAndroid = !kIsWeb && Platform.isAndroid;
          final isWindows = !kIsWeb && Platform.isWindows;
          final bool estRepas = categorie == CategorieDepense.repas;

          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.teal.shade100,
                        child: const Icon(Icons.edit_note, color: Colors.teal),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Modifier la Dépense',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            Text(
                              'Compte : ${depenseInitiale.technicien}',
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                    ],
                  ),
                  const Divider(height: 16),

                  // ─── 📅 DATE DE LA DÉPENSE ───────
                  InkWell(
                    onTap: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: dateDepense,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                      );
                      if (d != null) {
                        setDlgState(() => dateDepense = d);
                      }
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.grey.shade50,
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today_rounded, size: 18, color: Colors.teal),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Date de la dépense / facture *', style: TextStyle(fontSize: 10, color: Colors.grey)),
                              Text(
                                '${dateDepense.year}-${dateDepense.month.toString().padLeft(2, '0')}-${dateDepense.day.toString().padLeft(2, '0')}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ],
                          ),
                          const Spacer(),
                          const Icon(Icons.edit_calendar, size: 18, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 1. CHOIX DE LA CATÉGORIE
                  DropdownButtonFormField<CategorieDepense>(
                    key: ValueKey(categorie),
                    initialValue: categorie,
                    decoration: const InputDecoration(
                      labelText: 'Catégorie de dépense *',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: CategorieDepense.values.map((c) {
                      final depDummy = Depense(
                        id: '',
                        date: DateTime.now(),
                        technicien: '',
                        montant: 0,
                        categorie: c,
                        description: '',
                      );
                      return DropdownMenuItem(
                        value: c,
                        child: Row(
                          children: [
                            Icon(depDummy.icone, color: depDummy.couleur, size: 18),
                            const SizedBox(width: 8),
                            Text(depDummy.libelleCategorie),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setDlgState(() {
                          categorie = val;
                          if (val != CategorieDepense.repas) {
                            pourboireCtrl.text = '0.00';
                          }
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 12),

                  // 2. CHAMPS MONTANT ET FOURNISSEUR
                  if (estRepas) ...[
                    TextField(
                      controller: fournisseurCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Restaurant / Établissement *',
                        prefixIcon: Icon(Icons.restaurant, color: Colors.orange),
                        hintText: 'St-Hubert, Tim Hortons, Subway...',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: montantCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            onChanged: (_) => setDlgState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'Montant Repas (\$ CAD) *',
                              prefixIcon: Icon(Icons.fastfood, color: Colors.orange),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: pourboireCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            onChanged: (_) => setDlgState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'Pourboire (\$ CAD)',
                              prefixIcon: Icon(Icons.volunteer_activism, color: Colors.indigo),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Boutons de pourboire rapide
                    Row(
                      children: [
                        const Text('Pourboire rapide :', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 6),
                        ...[0, 10, 15, 18, 20].map((pct) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(4),
                              onTap: () {
                                final mVal = double.tryParse(montantCtrl.text.replaceAll(',', '.').trim()) ?? 0.0;
                                final tip = (mVal * pct / 100.0);
                                pourboireCtrl.text = tip.toStringAsFixed(2);
                                setDlgState(() {});
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.indigo.shade50,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.indigo.shade200),
                                ),
                                child: Text(
                                  pct == 0 ? '0 \$' : '$pct %',
                                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.indigo.shade900),
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Encadré total calculé
                    Builder(builder: (c) {
                      final mVal = double.tryParse(montantCtrl.text.replaceAll(',', '.').trim()) ?? 0.0;
                      final pVal = double.tryParse(pourboireCtrl.text.replaceAll(',', '.').trim()) ?? 0.0;
                      final totalLigne = mVal + pVal;
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Text(
                                '🍽️ Repas : ${mVal.toStringAsFixed(2)} \$  +  🪙 Pourb. : ${pVal.toStringAsFixed(2)} \$',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.orange.shade900),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Total : ${totalLigne.toStringAsFixed(2)} \$',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.orange.shade900),
                            ),
                          ],
                        ),
                      );
                    }),
                  ] else ...[
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: montantCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Montant (\$ CAD) *',
                              prefixIcon: Icon(Icons.attach_money, color: Colors.green),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: fournisseurCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Fournisseur / Commerce',
                              prefixIcon: Icon(Icons.store),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),

                  // DESCRIPTION & Nº COMMANDE
                  TextField(
                    controller: descriptionCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Description / Raison du frais *',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: commandeCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Nº Commande / Facture',
                            prefixIcon: Icon(Icons.tag),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: modePaiement,
                          decoration: const InputDecoration(
                            labelText: 'Paiement',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: const [
                            DropdownMenuItem(value: 'Personnel (À rembourser)', child: Text('Personnel (Remb.)', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: 'Carte Entreprise', child: Text('Carte Entreprise', overflow: TextOverflow.ellipsis)),
                          ],
                          onChanged: (val) {
                            if (val != null) setDlgState(() => modePaiement = val);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ─── PHOTO DU REÇU ATTACHÉE ───────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.blueGrey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(isAndroid ? Icons.camera_alt : Icons.folder_open, color: Colors.indigo, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              photoSelectionnee != null ? 'Reçu photographié' : 'Preuve / Photo du reçu',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (photoSelectionnee != null) ...[
                          Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  width: 60,
                                  height: 60,
                                  color: Colors.grey.shade300,
                                  child: (!kIsWeb && File(photoSelectionnee!).existsSync())
                                      ? Image.file(File(photoSelectionnee!), fit: BoxFit.cover)
                                      : const Icon(Icons.receipt),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('✅ Reçu attaché', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 12)),
                                    Text(
                                      photoSelectionnee!.split(RegExp(r'[\\/]')).last,
                                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                tooltip: 'Supprimer photo',
                                onPressed: () => setDlgState(() => photoSelectionnee = null),
                              ),
                            ],
                          ),
                        ] else ...[
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  icon: Icon(isAndroid ? Icons.camera_alt : Icons.file_upload_outlined),
                                  label: Text(
                                    isAndroid ? 'Prendre photo (Caméra)' : 'Sélectionner photo reçu',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.indigo.shade800,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                  ),
                                  onPressed: () async {
                                    final p = await _service.capturerOuSelectionnerPhotoRecu(context);
                                    if (p != null) {
                                      setDlgState(() => photoSelectionnee = p);
                                    }
                                  },
                                ),
                              ),
                              if (isWindows) ...[
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  icon: const Icon(Icons.folder, size: 18),
                                  label: const Text('Dossier'),
                                  onPressed: () => _service.ouvrirDossierRecusDansWindows(),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  // BOUTON ENREGISTRER MODIFICATIONS
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.save, size: 20),
                      label: const Text('Enregistrer les modifications', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () async {
                        final m = double.tryParse(montantCtrl.text.replaceAll(',', '.').trim());
                        if (m == null || m <= 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Veuillez entrer un montant valide.')),
                          );
                          return;
                        }
                        double p = 0.0;
                        if (categorie == CategorieDepense.repas) {
                          p = double.tryParse(pourboireCtrl.text.replaceAll(',', '.').trim()) ?? 0.0;
                          if (p < 0) p = 0.0;
                        }
                        if (descriptionCtrl.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Veuillez entrer une description.')),
                          );
                          return;
                        }

                        final depModifiee = Depense(
                          id: depenseInitiale.id,
                          date: dateDepense,
                          technicien: depenseInitiale.technicien,
                          montant: m,
                          pourboire: p,
                          categorie: categorie,
                          description: descriptionCtrl.text.trim(),
                          fournisseur: fournisseurCtrl.text.trim(),
                          numeroCommande: commandeCtrl.text.trim().isNotEmpty ? commandeCtrl.text.trim() : null,
                          modePaiement: modePaiement,
                          photoPath: photoSelectionnee,
                        );

                        await _service.modifierDepense(depModifiee);
                        if (ctx.mounted) Navigator.pop(ctx);
                        await _charger();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('✅ Dépense mise à jour avec succès !'), backgroundColor: Colors.teal),
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _voirPhotoRecu(Depense d) {
    if (d.photoPath == null || d.photoPath!.isEmpty) return;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: Text('Reçu : ${d.fournisseur} (${d.montantTotal.toStringAsFixed(2)} \$)'),
              backgroundColor: Colors.indigo.shade800,
              foregroundColor: Colors.white,
              leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
              actions: [
                if (!kIsWeb && Platform.isWindows)
                  IconButton(
                    icon: const Icon(Icons.folder_open),
                    tooltip: 'Ouvrir dans l\'explorateur',
                    onPressed: () {
                      try {
                        Process.run('explorer.exe', ['/select,', d.photoPath!]);
                      } catch (_) {}
                    },
                  ),
              ],
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 500, maxWidth: 500),
              child: (!kIsWeb && File(d.photoPath!).existsSync())
                  ? Image.file(File(d.photoPath!), fit: BoxFit.contain)
                  : const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('Image non disponible'))),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBandeauPdfDepenses(List<Depense> depenses, String technicien) {
    final total = depenses.where((d) => d.aRembourser).fold(0.0, (s, d) => s + d.montantTotal);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.teal.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.teal.shade300, width: 1.2),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.teal.shade100,
            child: const Icon(Icons.picture_as_pdf, color: Colors.teal, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Compte de dépenses officiel ($technicien)',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Colors.teal.shade900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${depenses.length} dépense(s) • Total réclamé : ${total.toStringAsFixed(2)} \$ • Visualisation Windows native',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal.shade800,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            icon: const Icon(Icons.print, size: 15),
            label: const Text('Aperçu & Imprimer', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            onPressed: () => DepensePdfService.imprimerApercuPdf(
              context,
              depenses,
              technicien: technicien,
            ),
          ),
          const SizedBox(width: 6),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            icon: const Icon(Icons.email, size: 15),
            label: const Text('Outlook', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            onPressed: () => DepensePdfService.envoyerParOutlook(
              context,
              depenses,
              technicien: technicien,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String nomActuel = _technicienSelectionne?.nom ?? 'Pierre-Olivier Patry';
    final String camionActuel = _technicienSelectionne?.numeroCamion ?? 'Camion #102';

    // Dépenses et calculs stricts pour le technicien sélectionné
    final depensesAffichees = _service.getDepensesPourTechnicien(nomActuel);
    final totalRemboursement = _service.totalARembourserPour(nomActuel);
    final totalRepasNourriture = _service.totalRepasHorsPourboirePour(nomActuel);
    final totalPourboires = _service.totalPourboiresPour(nomActuel);

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Compte de Dépenses Route',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
            ),
            Text(
              '$nomActuel ($camionActuel)',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
        backgroundColor: const Color(0xFFD1001F),
        actions: [
          if (!kIsWeb && Platform.isWindows)
            IconButton(
              icon: const Icon(Icons.folder_shared, color: Colors.white),
              tooltip: 'Dossier Reçus Windows',
              onPressed: () => _service.ouvrirDossierRecusDansWindows(),
            ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
            tooltip: 'Générer rapport de remboursement PDF',
            onPressed: () => DepensePdfService.afficherDialogueExport(
              context,
              depensesAffichees,
              technicien: nomActuel,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _charger,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _charger,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                children: [
                  // ─── 🛡️ SÉLECTEUR DE COMPTE TECHNICIEN INDÉPENDANT & STATUT NIP ───
                  Card(
                    elevation: 2,
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: const Color(0xFFD1001F).withValues(alpha: 0.1),
                            radius: 20,
                            child: const Icon(Icons.badge_outlined, color: Color(0xFFD1001F), size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'COMPTE TECHNICIEN INDÉPENDANT',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                                DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    key: const Key('technicien_dropdown'),
                                    isExpanded: true,
                                    value: _technicienSelectionne?.nom,
                                    icon: const Icon(Icons.arrow_drop_down, color: Colors.black87),
                                    style: const TextStyle(
                                      color: Colors.black87,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                    items: _techniciens.map((t) {
                                      return DropdownMenuItem<String>(
                                        value: t.nom,
                                        child: Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                t.nom,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.grey.shade200,
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                t.numeroCamion,
                                                style: const TextStyle(fontSize: 10, color: Colors.black54, fontWeight: FontWeight.normal),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (nom) {
                                      if (nom != null) {
                                        final tech = _techniciens.firstWhere((t) => t.nom == nom);
                                        _changerTechnicien(tech);
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Badge interactif de verrouillage NIP
                          InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () {
                              if (_estDeverrouille) {
                                setState(() => _estDeverrouille = false);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('🔒 Session reverrouillée avec succès.'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              } else {
                                _demanderNipSecurise(action: 'déverrouiller votre session de travail');
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: _estDeverrouille ? Colors.green.shade50 : Colors.amber.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _estDeverrouille ? Colors.green.shade400 : Colors.amber.shade400,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _estDeverrouille ? Icons.lock_open_rounded : Icons.lock_rounded,
                                    size: 15,
                                    color: _estDeverrouille ? Colors.green.shade800 : Colors.amber.shade900,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    _estDeverrouille ? 'Déverrouillé' : 'Verrouillé',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: _estDeverrouille ? Colors.green.shade900 : Colors.amber.shade900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert, size: 20, color: Colors.grey),
                            tooltip: 'Options de sécurité',
                            onSelected: (val) {
                              if (val == 'changer_nip') {
                                _changerNipModal();
                              } else if (val == 'verrouiller') {
                                setState(() => _estDeverrouille = false);
                              }
                            },
                            itemBuilder: (ctx) => [
                              const PopupMenuItem(
                                value: 'changer_nip',
                                child: Row(
                                  children: [
                                    Icon(Icons.pin, size: 18, color: Colors.teal),
                                    SizedBox(width: 8),
                                    Text('Modifier mon code NIP', style: TextStyle(fontSize: 13)),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'verrouiller',
                                enabled: _estDeverrouille,
                                child: const Row(
                                  children: [
                                    Icon(Icons.lock, size: 18, color: Colors.red),
                                    SizedBox(width: 8),
                                    Text('Verrouiller la session', style: TextStyle(fontSize: 13)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ─── 📄 BANDEAU RAPPORT PDF COMPTE DE DÉPENSES WINDOWS ────
                  if (!kIsWeb && Platform.isWindows)
                    _buildBandeauPdfDepenses(depensesAffichees, nomActuel),

                  // CARTE SOMMAIRE REMBOURSEMENT DU TECHNICIEN SÉLECTIONNÉ
                  Card(
                    elevation: 3,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: LinearGradient(
                          colors: [Colors.teal.shade900, Colors.teal.shade700],
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'TOTAL À REMBOURSER',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.1,
                                    ),
                                  ),
                                  Text(
                                    '$nomActuel • $camionActuel',
                                    style: const TextStyle(color: Colors.white, fontSize: 13),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${depensesAffichees.length} reçus',
                                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '${totalRemboursement.toStringAsFixed(2)} \$ CAD',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (totalPourboires > 0 || totalRepasNourriture > 0) ...[
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.restaurant, size: 13, color: Colors.white70),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Repas : ${totalRepasNourriture.toStringAsFixed(2)} \$  •  Pourboires : ${totalPourboires.toStringAsFixed(2)} \$',
                                    style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w500),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: ElevatedButton.icon(
                                  icon: const Icon(Icons.document_scanner_rounded, size: 18),
                                  label: const Text('Scanner Facture (IA)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: Colors.teal.shade900,
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    elevation: 2,
                                  ),
                                  onPressed: _scannerFactureDirectement,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: OutlinedButton.icon(
                                  icon: const Icon(Icons.edit_note, size: 18, color: Colors.white),
                                  label: const Text('Manuelle', style: TextStyle(color: Colors.white, fontSize: 12)),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: Colors.white70),
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                  ),
                                  onPressed: () => _ajouterDepenseModal(),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
                                tooltip: 'Générer rapport PDF',
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                                ),
                                onPressed: () => DepensePdfService.afficherDialogueExport(
                                  context,
                                  depensesAffichees,
                                  technicien: nomActuel,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // TITRE LISTE
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Reçus de $nomActuel (${depensesAffichees.length})',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      if (!kIsWeb && Platform.isWindows)
                        InkWell(
                          onTap: () => _service.ouvrirDossierRecusDansWindows(),
                          child: const Row(
                            children: [
                              Icon(Icons.folder, size: 16, color: Colors.teal),
                              SizedBox(width: 4),
                              Text('Dossier Windows', style: TextStyle(fontSize: 12, color: Colors.teal, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  if (depensesAffichees.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: Text(
                            'Aucune dépense enregistrée pour le compte de $nomActuel.\nScannez une facture ou cliquez sur "Manuelle" pour en ajouter.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ),
                      ),
                    )
                  else
                    ...depensesAffichees.map((d) {
                      final hasPhoto = d.photoPath != null && d.photoPath!.isNotEmpty;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                          leading: CircleAvatar(
                            backgroundColor: d.couleur.withValues(alpha: 0.15),
                            child: Icon(d.icone, color: d.couleur, size: 20),
                          ),
                          title: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  d.fournisseur.isNotEmpty ? d.fournisseur : d.libelleCategorie,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                              ),
                              Text(
                                '${d.montantTotal.toStringAsFixed(2)} \$',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Colors.teal.shade900,
                                ),
                              ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(d.description, style: const TextStyle(fontSize: 12)),
                              if (d.categorie == CategorieDepense.repas || d.pourboire > 0) ...[
                                const SizedBox(height: 2),
                                Text(
                                  '🍽️ Repas : ${d.montant.toStringAsFixed(2)} \$ • 🪙 Pourboire : ${d.pourboire.toStringAsFixed(2)} \$',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.orange.shade900,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Text(
                                    '${d.date.day}/${d.date.month}/${d.date.year}',
                                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                                  ),
                                  if (d.numeroCommande != null) ...[
                                    const SizedBox(width: 8),
                                    Text('• Cmd: ${d.numeroCommande}', style: const TextStyle(fontSize: 11, color: Colors.indigo)),
                                  ],
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: d.aRembourser ? Colors.green.shade50 : Colors.blue.shade50,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      d.aRembourser ? 'À rembourser' : 'Carte Cie',
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.bold,
                                        color: d.aRembourser ? Colors.green.shade900 : Colors.blue.shade900,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (hasPhoto)
                                IconButton(
                                  icon: const Icon(Icons.image, color: Colors.teal),
                                  tooltip: 'Voir reçu',
                                  onPressed: () => _voirPhotoRecu(d),
                                )
                              else
                                IconButton(
                                  icon: const Icon(Icons.add_a_photo_outlined, color: Colors.grey),
                                  tooltip: 'Ajouter photo reçu',
                                  onPressed: () async {
                                    if (!await _demanderNipSecurise(action: 'ajouter une photo à cette dépense')) return;
                                    if (!mounted) return;
                                    final p = await _service.capturerOuSelectionnerPhotoRecu(this.context);
                                    if (p != null) {
                                      d.photoPath = p;
                                      await _service.sauvegarder();
                                      _charger();
                                    }
                                  },
                                ),
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, color: Colors.blueGrey, size: 20),
                                tooltip: 'Modifier cette dépense',
                                onPressed: () => _editerDepenseModal(d),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                tooltip: 'Supprimer cette dépense',
                                onPressed: () async {
                                  if (!await _demanderNipSecurise(action: 'supprimer cette dépense')) return;
                                  if (!context.mounted) return;
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (c) => AlertDialog(
                                      title: const Text('Confirmer la suppression'),
                                      content: Text(
                                        'Voulez-vous supprimer cette dépense (${d.fournisseur.isNotEmpty ? d.fournisseur : d.libelleCategorie} - ${d.montantTotal.toStringAsFixed(2)} \$) du compte de $nomActuel ?',
                                      ),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                                          onPressed: () => Navigator.pop(c, true),
                                          child: const Text('Supprimer'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirm == true) {
                                    await _service.supprimerDepense(d.id);
                                    _charger();
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.teal.shade800,
        foregroundColor: Colors.white,
        elevation: 4,
        icon: const Icon(Icons.document_scanner_rounded),
        label: const Text('Scanner Facture (IA)', style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: _scannerFactureDirectement,
      ),
      // GRAND BOUTON AU BAS DE L'ÉCRAN
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: SafeArea(
          child: ElevatedButton.icon(
            icon: const Icon(Icons.picture_as_pdf_rounded, size: 22),
            label: Text(
              'GÉNÉRER LE RAPPORT DE REMBOURSEMENT (${totalRemboursement.toStringAsFixed(2)} \$)',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal.shade800,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => DepensePdfService.afficherDialogueExport(
              context,
              depensesAffichees,
              technicien: nomActuel,
            ),
          ),
        ),
      ),
    );
  }
}
