import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:supabase_flutter/supabase_flutter.dart';

// ==============================================================================
// 📦 MODÈLE : ARTICLE DE CAMION RAYCO WYLIE
// ==============================================================================
class ArticleCamion {
  final String id; // Ex: '101_11BFL0085'
  final String ref; // Ex: '11BFL0085'
  final String nom;
  int quantite;
  final String unite;
  final double cout;
  final String camion; // 'Camion #101', 'Camion #102', 'Camion #103'
  final String technicien; // 'David Hestin', 'Pierre-Olivier Patry', 'Jean-François Allie'
  final String localisation; // 'TECH 1', 'TECH 2', 'TECH 3'
  final String entrepot;
  final String notes;

  ArticleCamion({
    required this.id,
    required this.ref,
    required this.nom,
    required this.quantite,
    required this.unite,
    this.cout = 0.0,
    this.camion = 'Camion #101',
    this.technicien = '',
    this.localisation = '',
    this.entrepot = '',
    this.notes = '',
  });

  factory ArticleCamion.fromJson(
    Map<String, dynamic> json, {
    String defaultCamion = 'Camion #101',
    String defaultTech = '',
    String defaultLoc = '',
  }) {
    final refVal = (json['ref'] ?? '').toString();
    final rawNotes = (json['notes'] ?? '').toString();

    // 1. Déduction du camion (priorité : champ direct, puis champ 'entrepot', puis tag notes)
    String camionVal = (json['camion'] ?? json['entrepot'] ?? '').toString().trim();
    if (camionVal.isEmpty) {
      final mCamion = RegExp(r'\[CAMION:\s*([^\]]+)\]').firstMatch(rawNotes);
      camionVal = mCamion != null ? mCamion.group(1)!.trim() : defaultCamion;
    }

    // 2. Déduction du technicien
    String techVal = (json['technicien'] ?? '').toString().trim();
    if (techVal.isEmpty) {
      final mTech = RegExp(r'\[TECH:\s*([^\]]+)\]').firstMatch(rawNotes);
      techVal = mTech != null ? mTech.group(1)!.trim() : defaultTech;
    }

    // 3. Déduction de la localisation
    String locVal = (json['localisation'] ?? '').toString().trim();
    if (locVal.isEmpty) {
      final mLoc = RegExp(r'\[LOC:\s*([^\]]+)\]').firstMatch(rawNotes);
      locVal = mLoc != null ? mLoc.group(1)!.trim() : defaultLoc;
    }

    // 4. Déduction du coût
    double coutVal = 0.0;
    if (json['cout'] != null) {
      final coutRaw = json['cout'];
      coutVal = (coutRaw is num)
          ? coutRaw.toDouble()
          : (double.tryParse(coutRaw.toString()) ?? 0.0);
    } else {
      final mCout = RegExp(r'\[COUT:\s*([^\]]+)\]').firstMatch(rawNotes);
      if (mCout != null) {
        coutVal = double.tryParse(mCout.group(1)!.trim()) ?? 0.0;
      }
    }

    final quantiteRaw = json['quantite'];
    final int qte = (quantiteRaw is num)
        ? quantiteRaw.toInt()
        : (int.tryParse(quantiteRaw.toString()) ?? 0);

    final idVal = (json['id'] != null && json['id'].toString().isNotEmpty)
        ? json['id'].toString()
        : '${camionVal.replaceAll(RegExp(r'[^0-9]'), '')}_$refVal';

    final cleanNotes = rawNotes
        .replaceAll(RegExp(r'\[(CAMION|COUT|TECH|LOC):[^\]]+\]'), '')
        .replaceAll(RegExp(r'^\s*\|\s*'), '')
        .trim();

    return ArticleCamion(
      id: idVal,
      ref: refVal,
      nom: (json['nom'] ?? '').toString(),
      quantite: qte,
      unite: (json['unite'] ?? 'pcs').toString(),
      cout: coutVal,
      camion: camionVal,
      technicien: techVal,
      localisation: locVal,
      entrepot: (json['entrepot'] ?? camionVal).toString(),
      notes: cleanNotes,
    );
  }

  Map<String, dynamic> toMap({int utilise = 0}) => {
        'id': id,
        'ref': ref,
        'nom': nom,
        'quantite': quantite,
        'unite': unite,
        'cout': cout,
        'camion': camion,
        'technicien': technicien,
        'localisation': localisation,
        'entrepot': entrepot,
        'notes': notes,
        'utilise': utilise,
      };

  /// Sérialisation optimisée pour la table PostgreSQL 'inventaire_camion'
  /// Clé primaire : id (ex: '101_11BFL0085', '102_11BFL0085', '103_11BFL0085')
  Map<String, dynamic> toSupabase() {
    return {
      'id': id,
      'camion': camion,
      'technicien': technicien,
      'localisation': localisation,
      'ref': ref,
      'nom': nom,
      'quantite': quantite,
      'unite': unite,
      'cout': cout,
      'entrepot': entrepot.isNotEmpty ? entrepot : camion,
      'notes': notes,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }
}

// ==============================================================================
// 🛠️ SERVICE D'INVENTAIRE MULTI-CAMIONS RAYCO WYLIE
// ==============================================================================
class InventaireService extends ChangeNotifier {
  static final InventaireService instance = InventaireService._internal();

  InventaireService._internal();

  bool _isInitializing = false;

  static const List<String> camions = [
    'Camion #101',
    'Camion #102',
    'Camion #103',
  ];

  static const Map<String, String> camionVersTech = {
    'Camion #101': 'David Hestin',
    'Camion #102': 'Pierre-Olivier Patry',
    'Camion #103': 'Jean-François Allie',
  };

  static const Map<String, String> camionVersLoc = {
    'Camion #101': 'TECH 1',
    'Camion #102': 'TECH 2',
    'Camion #103': 'TECH 3',
  };

  List<ArticleCamion> _articles = [];
  bool _isLoaded = false;
  bool get isLoaded => _isLoaded;

  StreamSubscription<List<Map<String, dynamic>>>? _streamSub;
  bool _isCloudSync = false;
  bool get isCloudSync => _isCloudSync;
  String _cloudStatusMessage = 'Initialisation...';
  String get cloudStatusMessage => _cloudStatusMessage;

  List<ArticleCamion> get articles => List.unmodifiable(_articles);

  List<ArticleCamion> get articlesEnStock =>
      _articles.where((a) => a.quantite > 0).toList();

  /// Normalise n'importe quelle désignation (numéro, nom du technicien, tag) vers 'Camion #101', '#102' ou '#103'
  static String normaliserCamion(String? inputCamion, [String? inputTechnicien]) {
    final c = (inputCamion ?? '').toLowerCase();
    final t = (inputTechnicien ?? '').toLowerCase();

    if (c.contains('101') ||
        c.contains('tech 1') ||
        c.contains('tech_01') ||
        t.contains('hestin') ||
        t.contains('david')) {
      return 'Camion #101';
    }
    if (c.contains('102') ||
        c.contains('tech 2') ||
        c.contains('tech_02') ||
        t.contains('patry') ||
        t.contains('pierre')) {
      return 'Camion #102';
    }
    if (c.contains('103') ||
        c.contains('tech 3') ||
        c.contains('tech_03') ||
        t.contains('allie') ||
        t.contains('jean')) {
      return 'Camion #103';
    }

    return 'Camion #101';
  }

  /// Récupère la liste des articles d'un camion spécifique (ou de tous si camionOuTech == null ou 'Tous')
  List<ArticleCamion> getArticlesPourCamion(
    String? camionOuTech, {
    bool seulementEnStock = false,
  }) {
    if (camionOuTech == null ||
        camionOuTech.trim().isEmpty ||
        camionOuTech == 'Tous' ||
        camionOuTech == 'Tous les camions') {
      return seulementEnStock
          ? _articles.where((a) => a.quantite > 0).toList()
          : _articles;
    }

    final target = normaliserCamion(camionOuTech);
    return _articles.where((a) {
      final matchesCamion = normaliserCamion(a.camion) == target;
      if (!matchesCamion) return false;
      return seulementEnStock ? a.quantite > 0 : true;
    }).toList();
  }

  /// Récupère le stock disponible pour une référence précise dans un camion
  int getStockPourCamion(String ref, String? camion, [String? technicien]) {
    final target = normaliserCamion(camion, technicien);
    final match = _articles.firstWhere(
      (a) =>
          a.ref.toLowerCase() == ref.toLowerCase() &&
          normaliserCamion(a.camion) == target,
      orElse: () => ArticleCamion(
        id: '',
        ref: ref,
        nom: '',
        quantite: 0,
        unite: '',
      ),
    );
    return match.quantite;
  }

  /// Modifie manuellement la quantité d'un article
  void modifierQuantite(String refOuId, int delta, {String? camion}) {
    final targetCamion = camion != null ? normaliserCamion(camion) : null;
    int idx = -1;

    // 1. Chercher par id exact
    idx = _articles.indexWhere((a) => a.id == refOuId);

    // 2. Chercher par ref + camion
    if (idx == -1 && targetCamion != null) {
      idx = _articles.indexWhere((a) =>
          a.ref.toLowerCase() == refOuId.toLowerCase() &&
          normaliserCamion(a.camion) == targetCamion);
    }

    // 3. Fallback: première occurrence de la ref
    if (idx == -1) {
      idx = _articles.indexWhere((a) => a.ref.toLowerCase() == refOuId.toLowerCase());
    }

    if (idx >= 0) {
      _articles[idx].quantite = (_articles[idx].quantite + delta).clamp(0, 99999);
      _sauvegarderLocal();
      _synchroniserArticleSupabase(_articles[idx]);
      notifyListeners();
    }
  }

  /// Déduit les pièces utilisées d'une intervention du camion assigné au technicien
  void deduirePieces(
    List<Map<String, dynamic>> piecesUtilisees, {
    String? camion,
    String? technicien,
  }) {
    if (piecesUtilisees.isEmpty) return;
    final defaultCamion = normaliserCamion(camion, technicien);
    debugPrint('📦 [Inventaire] Déduction de ${piecesUtilisees.length} pièces pour $defaultCamion ($technicien)');

    final List<ArticleCamion> articlesModifies = [];

    for (final p in piecesUtilisees) {
      final ref = (p['ref'] ?? '').toString().trim();
      final utilise = (p['utilise'] as num?)?.toInt() ?? 0;
      if (ref.isEmpty || utilise <= 0) continue;

      // Si la pièce spécifie son propre camion (emprunt d'un autre camion), l'utiliser
      final itemCamion = p['camion']?.toString() ?? p['entrepot']?.toString();
      final targetCamion = (itemCamion != null && itemCamion.isNotEmpty)
          ? normaliserCamion(itemCamion, technicien)
          : defaultCamion;

      // Chercher l'article dans le camion cible
      int idx = _articles.indexWhere((a) =>
          a.ref.toLowerCase() == ref.toLowerCase() &&
          normaliserCamion(a.camion) == targetCamion);

      // Si non trouvé dans ce camion, fallback global
      if (idx == -1) {
        idx = _articles.indexWhere((a) => a.ref.toLowerCase() == ref.toLowerCase());
      }

      if (idx >= 0) {
        final anc = _articles[idx].quantite;
        _articles[idx].quantite = (anc - utilise).clamp(0, 99999);
        articlesModifies.add(_articles[idx]);
        debugPrint('  ✅ Déduit: $ref x$utilise de ${_articles[idx].camion} ($anc -> ${_articles[idx].quantite})');
      } else {
        debugPrint('  ⚠️ Pièce $ref introuvable dans l\'inventaire de $targetCamion');
      }
    }

    if (articlesModifies.isNotEmpty) {
      _sauvegarderLocal();
      for (final art in articlesModifies) {
        _synchroniserArticleSupabase(art);
      }
      notifyListeners();
    }
  }

  // ============================================================================
  // 💾 CHARGEMENT & PERSISTANCE LOCALE / CLOUD
  // ============================================================================
  File? _getFichierLocal() {
    if (kIsWeb) return null;
    try {
      final userProfile =
          Platform.environment['USERPROFILE'] ?? 'C:\\Users\\Default';
      final dir = Directory('$userProfile\\Documents\\AppTechnicien');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      return File('${dir.path}\\inventaire_camions.json');
    } catch (_) {
      return null;
    }
  }

  Future<void> initialiser() async {
    if (_isLoaded && _articles.isNotEmpty) return;
    if (_isInitializing) return;
    _isInitializing = true;

    try {
      // 1. Essai de chargement depuis le fichier local de sauvegarde
      try {
        final file = _getFichierLocal();
        if (file != null && await file.exists()) {
          final content = await file.readAsString();
          if (content.trim().isNotEmpty) {
            final decoded = jsonDecode(content);
            if (decoded is List) {
              _articles = decoded
                  .map((e) => ArticleCamion.fromJson(Map<String, dynamic>.from(e as Map)))
                  .toList();
              _isLoaded = true;
              notifyListeners();
            }
          }
        }
      } catch (e) {
        debugPrint('Erreur lecture inventaire local: $e');
      }

      // 2. Si non chargé depuis la sauvegarde locale, chargement depuis l'actif packagé
      if (!_isLoaded || _articles.isEmpty) {
        await reinitialiserDepuisFichier();
      }

      // 3. Synchronisation avec Supabase Cloud en arrière-plan
      synchroniserVersCloud();
    } finally {
      _isInitializing = false;
    }
  }

  /// Réinitialise l'inventaire depuis l'actif JSON officiel et pousse les données vers le Cloud
  Future<void> reinitialiserDepuisFichier() async {
    try {
      final jsonString =
          await rootBundle.loadString('assets/inventaires/inventaire_camions.json');
      final Map<String, dynamic> data = jsonDecode(jsonString);

      final Map<String, ArticleCamion> loadedById = {};
      data.forEach((techKey, techData) {
        final camion = techData['camion']?.toString() ?? 'Camion #101';
        final technicien = techData['technicien']?.toString() ?? '';
        final localisation = techData['localisation']?.toString() ?? '';
        final rawArticles = techData['articles'] as List<dynamic>? ?? [];

        for (final item in rawArticles) {
          final map = Map<String, dynamic>.from(item as Map);
          final art = ArticleCamion.fromJson(
            map,
            defaultCamion: camion,
            defaultTech: technicien,
            defaultLoc: localisation,
          );
          if (loadedById.containsKey(art.id)) {
            loadedById[art.id]!.quantite += art.quantite;
          } else {
            loadedById[art.id] = art;
          }
        }
      });

      _articles = loadedById.values.toList();
      _isLoaded = true;
      await _sauvegarderLocal();
      notifyListeners();
      debugPrint('📦 [Inventaire] Chargé avec succès : ${_articles.length} articles uniques pour 3 camions');

      // Tenter le téléversement forcé vers le Cloud
      synchroniserVersCloud(forcerTeleversement: true);
    } catch (e) {
      debugPrint('Erreur chargement asset inventaire: $e');
    }
  }

  /// Charge directement une liste d'articles (utile en test ou injection directe)
  void chargerDepuisArticles(List<ArticleCamion> articles) {
    _articles = List.from(articles);
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> _sauvegarderLocal() async {
    try {
      final file = _getFichierLocal();
      if (file != null) {
        final jsonStr = jsonEncode(_articles.map((a) => a.toMap()).toList());
        await file.writeAsString(jsonStr);
      }
    } catch (e) {
      debugPrint('Erreur sauvegarde inventaire local: $e');
    }
  }

  /// Écoute les modifications d'inventaire en direct (Supabase Realtime)
  void _initialiserStream() {
    try {
      _streamSub?.cancel();
      _streamSub = Supabase.instance.client
          .from('inventaire_camion')
          .stream(primaryKey: ['id'])
          .listen(
            (data) {
              if (data.isNotEmpty) {
                _articles = data
                    .map((item) => ArticleCamion.fromJson(Map<String, dynamic>.from(item)))
                    .toList();
                _isLoaded = true;
                _isCloudSync = true;
                _cloudStatusMessage = 'En direct avec le Cloud (${_articles.length} articles)';
                _sauvegarderLocal();
                notifyListeners();
              }
            },
            onError: (e) {
              debugPrint('Stream inventaire: $e');
              _isCloudSync = false;
              _cloudStatusMessage = 'Mode local (Stream cloud en attente)';
              notifyListeners();
            },
          );
    } catch (e) {
      debugPrint('Erreur init stream inventaire: $e');
    }
  }

  /// Synchronisation bidirectionnelle avec Supabase Cloud
  Future<bool> synchroniserVersCloud({bool forcerTeleversement = false}) async {
    try {
      final supabase = Supabase.instance.client;

      // Vérifier si la table existe et contient des données
      final check = await supabase
          .from('inventaire_camion')
          .select('id')
          .limit(10);

      if (check.isEmpty || forcerTeleversement) {
        // Envoi complet vers Supabase par lots de 50
        debugPrint('📦 Envoi initial de l\'inventaire vers Supabase (${_articles.length} articles)...');
        const batchSize = 50;
        bool tousReussis = true;
        for (var i = 0; i < _articles.length; i += batchSize) {
          final end = (i + batchSize < _articles.length) ? i + batchSize : _articles.length;
          final batch = _articles.sublist(i, end).map((a) => a.toSupabase()).toList();
          try {
            await supabase.from('inventaire_camion').upsert(batch);
          } catch (e) {
            tousReussis = false;
            debugPrint('ℹ️ Sync lot inventaire: $e');
            break;
          }
        }
        if (tousReussis) {
          _isCloudSync = true;
          _cloudStatusMessage = 'Inventaire synchronisé vers le Cloud (${_articles.length} articles)';
          debugPrint('✅ $_cloudStatusMessage');
        } else {
          _isCloudSync = false;
          _cloudStatusMessage = 'Mode local (Vérifier table SQL "id" dans Supabase)';
        }
      } else {
        // Supabase contient déjà l'inventaire, chargement de l'inventaire cloud
        final fullResponse = await supabase.from('inventaire_camion').select();
        if (fullResponse.isNotEmpty && fullResponse.length >= 300) {
          _articles = fullResponse
              .map((row) => ArticleCamion.fromJson(Map<String, dynamic>.from(row)))
              .toList();
          await _sauvegarderLocal();
          _isCloudSync = true;
          _cloudStatusMessage = 'Inventaire chargé depuis le Cloud (${_articles.length} articles)';
          debugPrint('✅ $_cloudStatusMessage');
        }
      }

      _initialiserStream();
      notifyListeners();
      return _isCloudSync;
    } catch (e) {
      debugPrint('ℹ️ Mode local inventaire actif (Supabase Sync/RLS : $e)');
      _isCloudSync = false;
      _cloudStatusMessage = 'Mode local (Cloud hors-ligne ou schéma en attente)';
      notifyListeners();
      return false;
    }
  }

  /// Ajoute ou met à jour un article (local + cloud)
  Future<void> ajouterOuMettreAJourArticle(ArticleCamion article) async {
    final idx = _articles.indexWhere((a) => a.id == article.id);
    if (idx >= 0) {
      _articles[idx] = article;
    } else {
      _articles.add(article);
    }
    await _sauvegarderLocal();
    await _synchroniserArticleSupabase(article);
    notifyListeners();
  }

  /// Synchronise un article modifié vers Supabase
  Future<void> _synchroniserArticleSupabase(ArticleCamion article) async {
    try {
      final supabase = Supabase.instance.client;
      await supabase.from('inventaire_camion').upsert(article.toSupabase());
      _isCloudSync = true;
    } catch (e) {
      debugPrint('Sync article (${article.id}) vers Supabase: $e');
    }
  }

  /// Ferme le flux temps réel lors de l'extinction
  void annulerStream() {
    _streamSub?.cancel();
    _streamSub = null;
  }
}
