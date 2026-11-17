import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'depenses_service.dart';

// ============================================================================
// 🧾 RÉSULTAT DE L'ANALYSE OCR D'UNE FACTURE / REÇU
// ============================================================================

class ReceiptScanResult {
  final bool isReadable; // true si au moins le montant ou fournisseur a été lu avec certitude
  final String? errorMessage;
  final double? montantTotal;
  final double? sousTotal;
  final double? pourboire;
  final double? tps;
  final double? tvq;
  final String? fournisseur;
  final CategorieDepense? categorie;
  final DateTime? date;
  final String? numeroCommande;
  final String? description;
  final double confidence; // Entre 0.0 et 1.0
  final String rawText;

  ReceiptScanResult({
    required this.isReadable,
    this.errorMessage,
    this.montantTotal,
    this.sousTotal,
    this.pourboire,
    this.tps,
    this.tvq,
    this.fournisseur,
    this.categorie,
    this.date,
    this.numeroCommande,
    this.description,
    this.confidence = 0.0,
    this.rawText = '',
  });

  bool get estFiable => isReadable && confidence >= 0.5 && (montantTotal ?? 0) > 0;

  String get messageStatut {
    if (!isReadable) {
      return errorMessage ?? 'Photo difficile à lire ou floue. Veuillez vérifier les informations.';
    }
    if (confidence >= 0.8) {
      return '✨ Facture analysée avec succès ! Les champs ont été remplis automatiquement.';
    } else if (confidence >= 0.5) {
      return '✨ Analyse automatique effectuée. Veuillez vérifier les champs avant d\'enregistrer.';
    } else {
      return '⚠️ Facture difficile à lire ou incomplète. Veuillez vérifier et compléter les informations.';
    }
  }

  factory ReceiptScanResult.unreadable(String message, {String raw = ''}) {
    return ReceiptScanResult(
      isReadable: false,
      errorMessage: message,
      confidence: 0.0,
      rawText: raw,
    );
  }
}

// ============================================================================
// 🔍 SERVICE D'ANALYSE ET SCAN DE REÇUS PAR IA / OCR
// ============================================================================

class ReceiptScannerService {
  static final ReceiptScannerService instance = ReceiptScannerService._();
  ReceiptScannerService._();

  // Clés API pour OCR.space (service OCR rapide mondial avec support français)
  static const List<String> _ocrApiKeys = [
    'helloworld',
    'K88899886788957',
    'K89849202388957',
  ];

  /// Analyse une facture / reçu à partir d'un chemin de fichier ou d'un buffer mémoire
  Future<ReceiptScanResult> analyserFacture({
    String? filePath,
    Uint8List? imageBytes,
  }) async {
    try {
      Uint8List? bytes = imageBytes;
      if (bytes == null && filePath != null && filePath.isNotEmpty) {
        if (!kIsWeb) {
          final file = File(filePath);
          if (await file.exists()) {
            bytes = await file.readAsBytes();
          }
        }
      }

      if (bytes == null || bytes.isEmpty) {
        return ReceiptScanResult.unreadable('Aucun fichier image trouvé ou sélectionné.');
      }

      if (bytes.lengthInBytes < 100) {
        return ReceiptScanResult.unreadable('Fichier image invalide ou vide.');
      }

      // 1. Exécution de la reconnaissance OCR
      final ocrText = await _extraireTexteOcr(bytes);
      if (ocrText == null || ocrText.trim().length < 5) {
        return ReceiptScanResult.unreadable(
          'Photo difficile à lire ou floue. Aucun texte n\'a pu être déchiffré.',
          raw: ocrText ?? '',
        );
      }

      // 2. Analyse sémantique du texte extrait
      return parseReceiptText(ocrText);
    } catch (e) {
      debugPrint('Erreur lors du scan du reçu: $e');
      return ReceiptScanResult.unreadable('Erreur technique lors de l\'analyse du reçu: $e');
    }
  }

  /// Appel OCR vers OCR.space avec fallback
  Future<String?> _extraireTexteOcr(Uint8List imageBytes) async {
    final base64Image = base64Encode(imageBytes);

    for (final apiKey in _ocrApiKeys) {
      try {
        final uri = Uri.parse('https://api.ocr.space/parse/image');
        final response = await http
            .post(
              uri,
              headers: {
                'Content-Type': 'application/x-www-form-urlencoded',
              },
              body: {
                'apikey': apiKey,
                'language': 'fre',
                'isOverlayRequired': 'false',
                'detectOrientation': 'true',
                'scale': 'true',
                'base64Image': 'data:image/jpeg;base64,$base64Image',
              },
            )
            .timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final exitCode = data['OCRExitCode'];
          if (exitCode == 1 || exitCode == 2) {
            final parsedResults = data['ParsedResults'] as List<dynamic>?;
            if (parsedResults != null && parsedResults.isNotEmpty) {
              final text = parsedResults[0]['ParsedText'] as String?;
              if (text != null && text.trim().isNotEmpty) {
                return text;
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Tentative OCR avec clé $apiKey échouée: $e');
      }
    }

    return null;
  }

  // ============================================================================
  // 🧠 PARSER SÉMANTIQUE DE REÇU (RÈGLES ET REGEX INTELLIGENTES)
  // ============================================================================

  ReceiptScanResult parseReceiptText(String text) {
    if (text.trim().isEmpty) {
      return ReceiptScanResult.unreadable('Aucun texte extrait du reçu.');
    }

    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    // 1. Détection du Fournisseur et de la Catégorie
    final detect = _detecterFournisseurEtCategorie(lines, text);
    final String fournisseur = detect.fournisseur;
    final CategorieDepense categorie = detect.categorie;

    // 2. Détection des Montants (Total, Sous-total, TPS, TVQ, Pourboire)
    final montants = _detecterMontants(lines, categorie);

    // 3. Détection de la Date
    final DateTime date = _detecterDate(lines) ?? DateTime.now();

    // 4. Détection du Numéro de commande / facture / transaction
    final String? numeroCommande = _detecterNumeroTransaction(lines);

    // 5. Synthèse de la description
    final String description = _genererDescription(categorie, fournisseur, montants);

    // 6. Calcul de la note de confiance (0.0 à 1.0)
    double confidence = 0.0;
    if (montants.total != null && montants.total! > 0) {
      confidence += 0.45;
    }
    if (fournisseur.isNotEmpty && fournisseur != 'Fournisseur inconnu') {
      confidence += 0.30;
    }
    if (categorie != CategorieDepense.autre) {
      confidence += 0.15;
    }
    if (_detecterDate(lines) != null) {
      confidence += 0.10;
    }

    final bool isReadable = confidence >= 0.45 && (montants.total ?? 0) > 0;

    return ReceiptScanResult(
      isReadable: isReadable,
      montantTotal: montants.total,
      sousTotal: montants.sousTotal,
      pourboire: montants.pourboire ?? 0.0,
      tps: montants.tps,
      tvq: montants.tvq,
      fournisseur: fournisseur,
      categorie: categorie,
      date: date,
      numeroCommande: numeroCommande,
      description: description,
      confidence: confidence,
      rawText: text,
      errorMessage: isReadable
          ? null
          : 'Facture difficile à lire ou floue. Veuillez vérifier les informations saisies.',
    );
  }

  // --- DÉTECTION FOURNISSEUR & CATÉGORIE ---

  static const Map<String, (String, CategorieDepense)> _commercesConnus = {
    // ⛽ Carburant / Essence
    'PETRO-CANADA': ('Petro-Canada', CategorieDepense.essence),
    'PETRO CANADA': ('Petro-Canada', CategorieDepense.essence),
    'PÉTRO-CANADA': ('Petro-Canada', CategorieDepense.essence),
    'SHELL': ('Shell', CategorieDepense.essence),
    'ESSO': ('Esso', CategorieDepense.essence),
    'ULTRAMAR': ('Ultramar', CategorieDepense.essence),
    'COUCHE-TARD': ('Couche-Tard', CategorieDepense.essence),
    'CIRCLE K': ('Circle K', CategorieDepense.essence),
    'HARNOIS': ('Harnois Énergies', CategorieDepense.essence),
    'IRVING': ('Irving Oil', CategorieDepense.essence),
    'CREVIER': ('Crevier', CategorieDepense.essence),
    'SONIC': ('Sonic Énergie', CategorieDepense.essence),
    'PIONEER': ('Pioneer', CategorieDepense.essence),
    'COSTCO ESSENCE': ('Costco Essence', CategorieDepense.essence),
    'COSTCO GAS': ('Costco Gas', CategorieDepense.essence),

    // 🍽️ Repas / Restaurants
    'TIM HORTONS': ('Tim Hortons', CategorieDepense.repas),
    'TIM HORTON': ('Tim Hortons', CategorieDepense.repas),
    'MCDONALD': ('McDonald\'s', CategorieDepense.repas),
    'MC DONALD': ('McDonald\'s', CategorieDepense.repas),
    'SUBWAY': ('Subway', CategorieDepense.repas),
    'A&W': ('A&W Restaurant', CategorieDepense.repas),
    'ST-HUBERT': ('St-Hubert', CategorieDepense.repas),
    'SAINT-HUBERT': ('St-Hubert', CategorieDepense.repas),
    'WENDY': ('Wendy\'s', CategorieDepense.repas),
    'HARVEY': ('Harvey\'s', CategorieDepense.repas),
    'BURGER KING': ('Burger King', CategorieDepense.repas),
    'STARBUCKS': ('Starbucks', CategorieDepense.repas),
    'NORMANDIN': ('Restaurant Normandin', CategorieDepense.repas),
    'ASHTON': ('Chez Ashton', CategorieDepense.repas),
    'BOSTON PIZZA': ('Boston Pizza', CategorieDepense.repas),
    'CAGE': ('La Cage', CategorieDepense.repas),
    'SCORES': ('Scores', CategorieDepense.repas),
    'BATON ROUGE': ('Bâton Rouge', CategorieDepense.repas),
    'CORA': ('Chez Cora', CategorieDepense.repas),
    'POULET ROUGE': ('Poulet Rouge', CategorieDepense.repas),
    'THAI EXPRESS': ('Thaï Express', CategorieDepense.repas),
    'PIZZA HUT': ('Pizza Hut', CategorieDepense.repas),
    'DOMINO': ('Domino\'s Pizza', CategorieDepense.repas),
    'BARBIES': ('Barbies Resto Bar Grill', CategorieDepense.repas),
    'PACINI': ('Pacini', CategorieDepense.repas),

    // 🔨 Outillage & Quincaillerie
    'CANADIAN TIRE': ('Canadian Tire', CategorieDepense.outillage),
    'HOME DEPOT': ('The Home Depot', CategorieDepense.outillage),
    'RONA': ('RONA', CategorieDepense.outillage),
    'BMR': ('BMR Quincaillerie', CategorieDepense.outillage),
    'PATRICK MORIN': ('Patrick Morin', CategorieDepense.outillage),
    'RENO-DEPOT': ('Réno-Dépôt', CategorieDepense.outillage),
    'RENO DEPOT': ('Réno-Dépôt', CategorieDepense.outillage),
    'FASTENAL': ('Fastenal Canada', CategorieDepense.outillage),
    'GRAINGER': ('Grainger / Acklands', CategorieDepense.outillage),
    'ACKLANDS': ('Acklands-Grainger', CategorieDepense.outillage),
    'WURTH': ('Würth Canada', CategorieDepense.outillage),
    'WÜRTH': ('Würth Canada', CategorieDepense.outillage),
    'LOWE': ('Lowe\'s', CategorieDepense.outillage),

    // 🔧 Pièces de rechange urgentes
    'NAPA': ('NAPA Pièces d\'auto', CategorieDepense.pieces),
    'CARQUEST': ('Carquest Auto Parts', CategorieDepense.pieces),
    'UAP': ('UAP Inc.', CategorieDepense.pieces),
    'TRACTION': ('Traction Pièces Camion Lourd', CategorieDepense.pieces),
    'PARTSSOURCE': ('PartsSource', CategorieDepense.pieces),

    // 🅿️ Stationnement & Péages
    'INDIGO': ('Indigo Parc', CategorieDepense.stationnement),
    'VINCI': ('Vinci Park', CategorieDepense.stationnement),
    'SPAQ': ('Société Parc Auto Québec', CategorieDepense.stationnement),
    'A25': ('Concession A25 Péage', CategorieDepense.stationnement),
    'A30': ('A30 Express Péage', CategorieDepense.stationnement),
    'AUTOROUTE 30': ('A30 Express Péage', CategorieDepense.stationnement),
    'STATIONNEMENT': ('Stationnement', CategorieDepense.stationnement),

    // 🏨 Hébergement / Hôtel
    'SUPER 8': ('Super 8 Motel', CategorieDepense.hebergement),
    'BEST WESTERN': ('Best Western', CategorieDepense.hebergement),
    'COMFORT INN': ('Comfort Inn', CategorieDepense.hebergement),
    'HOLIDAY INN': ('Holiday Inn', CategorieDepense.hebergement),
    'DAYS INN': ('Days Inn', CategorieDepense.hebergement),
    'QUALITY INN': ('Quality Inn', CategorieDepense.hebergement),
    'GOUVERNEUR': ('Hôtel Gouverneur', CategorieDepense.hebergement),
    'MARRIOTT': ('Marriott Hôtel', CategorieDepense.hebergement),
  };

  ({String fournisseur, CategorieDepense categorie}) _detecterFournisseurEtCategorie(
    List<String> lines,
    String fullText,
  ) {
    final upperText = fullText.toUpperCase();

    // 1. Recherche dans le dictionnaire des commerces connus
    for (final entry in _commercesConnus.entries) {
      if (upperText.contains(entry.key)) {
        return (fournisseur: entry.value.$1, categorie: entry.value.$2);
      }
    }

    // 2. Recherche par mots-clés de catégorie
    CategorieDepense? catTrouvee;
    if (upperText.contains('DIESEL') ||
        upperText.contains('CARBURANT') ||
        upperText.contains('ESSENCE') ||
        upperText.contains('POMPE #') ||
        upperText.contains('LITRES') ||
        upperText.contains('L/100')) {
      catTrouvee = CategorieDepense.essence;
    } else if (upperText.contains('POURBOIRE') ||
        upperText.contains('SERVEUR') ||
        upperText.contains('TABLE') ||
        upperText.contains('DINER') ||
        upperText.contains('DEJEUNER') ||
        upperText.contains('SOUPER') ||
        upperText.contains('RESTAURANT') ||
        upperText.contains('BISTRO') ||
        upperText.contains('MENU') ||
        upperText.contains('SANDWICH') ||
        upperText.contains('CAFE')) {
      catTrouvee = CategorieDepense.repas;
    } else if (upperText.contains('QUINCAILLERIE') ||
        upperText.contains('OUTILLAGE') ||
        upperText.contains('BOULON') ||
        upperText.contains('VIS') ||
        upperText.contains('RONDELLE') ||
        upperText.contains('ATTACHE')) {
      catTrouvee = CategorieDepense.outillage;
    } else if (upperText.contains('STATIONNEMENT') ||
        upperText.contains('PARKING') ||
        upperText.contains('PEAGE') ||
        upperText.contains('TOLL')) {
      catTrouvee = CategorieDepense.stationnement;
    } else if (upperText.contains('HOTEL') ||
        upperText.contains('MOTEL') ||
        upperText.contains('CHAMBRE') ||
        upperText.contains('NUITEE')) {
      catTrouvee = CategorieDepense.hebergement;
    } else if (upperText.contains('PIECES') ||
        upperText.contains('FILTRE') ||
        upperText.contains('COURROIE') ||
        upperText.contains('FREIN')) {
      catTrouvee = CategorieDepense.pieces;
    }

    // 3. Recherche du nom du fournisseur dans les premières lignes du reçu
    String fournisseurNom = 'Fournisseur';
    for (int i = 0; i < lines.length && i < 4; i++) {
      final line = lines[i].trim();
      // Ignorer si la ligne ressemble à une date, un numéro de tel, ou un montant
      if (line.length >= 3 &&
          !line.contains(RegExp(r'\d{4}[-/]\d')) &&
          !line.contains(RegExp(r'\$\s*\d')) &&
          !line.toLowerCase().startsWith('bienvenue') &&
          !line.toLowerCase().startsWith('merci')) {
        fournisseurNom = line;
        break;
      }
    }

    return (
      fournisseur: fournisseurNom,
      categorie: catTrouvee ?? CategorieDepense.autre,
    );
  }

  // --- DÉTECTION DES MONTANTS ET TAXES ---

  ({
    double? total,
    double? sousTotal,
    double? pourboire,
    double? tps,
    double? tvq,
  }) _detecterMontants(List<String> lines, CategorieDepense categorie) {
    double? total;
    double? sousTotal;
    double? pourboire;
    double? tps;
    double? tvq;

    final regexMontant = RegExp(r'(\d{1,4}[.,]\d{2})');

    final List<double> tousLesMontants = [];

    for (final line in lines) {
      final upper = line.toUpperCase();
      final matches = regexMontant.allMatches(line).toList();
      if (matches.isEmpty) continue;

      // On extrait la dernière valeur numérique de la ligne (souvent le montant)
      final valStr = matches.last.group(1)!.replaceAll(',', '.');
      final val = double.tryParse(valStr);
      if (val == null || val <= 0) continue;

      tousLesMontants.add(val);

      // Classification selon le texte de la ligne
      if ((upper.contains('TOTAL') && !upper.contains('SOUS') && !upper.contains('SUB')) ||
          upper.contains('NET A PAYER') ||
          upper.contains('A PAYER') ||
          upper.contains('MONTANT TOTAL') ||
          upper.contains('TOTAL CAD') ||
          upper.contains('GRAND TOTAL') ||
          upper.contains('SOLDE')) {
        total = val;
      } else if (upper.contains('SOUS-TOTAL') ||
          upper.contains('SOUS TOTAL') ||
          upper.contains('SUBTOTAL') ||
          upper.contains('SUB TOTAL')) {
        sousTotal = val;
      } else if (upper.contains('POURBOIRE') ||
          upper.contains('TIP') ||
          upper.contains('GRATUITY')) {
        pourboire = val;
      } else if (upper.contains('TPS') || upper.contains('GST') || upper.contains('TVH')) {
        tps = val;
      } else if (upper.contains('TVQ') || upper.contains('QST')) {
        tvq = val;
      }
    }

    // Si le total n'a pas été explicitement identifié par mot-clé, on prend le montant le plus élevé trouvé
    if (total == null && tousLesMontants.isNotEmpty) {
      tousLesMontants.sort();
      total = tousLesMontants.last;
    }

    // Traitement spécifique pour les repas avec pourboire :
    if (categorie == CategorieDepense.repas) {
      if (pourboire != null && pourboire > 0 && total != null) {
        // Si le total inclut déjà le pourboire, déduire le montant du repas
        if (sousTotal != null && (sousTotal + pourboire <= total + 0.05)) {
          // total est le grand total, le montant du repas est sousTotal (ou total - pourboire)
          total = (total - pourboire);
        }
      }
    }

    return (
      total: total,
      sousTotal: sousTotal,
      pourboire: pourboire,
      tps: tps,
      tvq: tvq,
    );
  }

  // --- DÉTECTION DATE ---

  DateTime? _detecterDate(List<String> lines) {
    // Formats numériques YYYY-MM-DD ou DD/MM/YYYY ou MM/DD/YYYY
    final regYmd = RegExp(r'\b(20\d\d)[-/](0[1-9]|1[0-2])[-/](0[1-9]|[12]\d|3[01])\b');
    final regDmy = RegExp(r'\b(0[1-9]|[12]\d|3[01])[-/](0[1-9]|1[0-2])[-/](20\d\d)\b');

    for (final line in lines) {
      final matchYmd = regYmd.firstMatch(line);
      if (matchYmd != null) {
        final y = int.parse(matchYmd.group(1)!);
        final m = int.parse(matchYmd.group(2)!);
        final d = int.parse(matchYmd.group(3)!);
        return DateTime(y, m, d);
      }

      final matchDmy = regDmy.firstMatch(line);
      if (matchDmy != null) {
        final d = int.parse(matchDmy.group(1)!);
        final m = int.parse(matchDmy.group(2)!);
        final y = int.parse(matchDmy.group(3)!);
        return DateTime(y, m, d);
      }
    }
    return null;
  }

  // --- DÉTECTION NUMÉRO TRANSACTION / COMMANDE ---

  String? _detecterNumeroTransaction(List<String> lines) {
    // 1. Chercher d'abord avec préfixes explicites : TRANSACTION, FACTURE, COMMANDE, REF, INV, CMD
    final regExplicite = RegExp(
      r'(?:FAC(?:TURE)?|INV(?:OICE)?|TRANS(?:ACTION)?|CMD|COMMANDE|REF)\s*[:#]?\s*([A-Za-z0-9-_]{4,18})',
      caseSensitive: false,
    );

    for (final line in lines) {
      final match = regExplicite.firstMatch(line);
      if (match != null) {
        final num = match.group(1);
        if (num != null && num.isNotEmpty && !num.contains(RegExp(r'^\d{2}[-/]\d{2}'))) {
          return num;
        }
      }
    }

    // 2. Recherche secondaire avec '#' ou 'NO' en évitant les numéros de pompe ou table
    final regSecondaire = RegExp(
      r'(?:N[O°]|#)\s*[:#]?\s*([A-Za-z0-9-_]{4,18})',
      caseSensitive: false,
    );
    for (final line in lines) {
      final upper = line.toUpperCase();
      if (upper.contains('POMPE') || upper.contains('TABLE') || upper.contains('SERVEUR')) continue;
      final match = regSecondaire.firstMatch(line);
      if (match != null) {
        final num = match.group(1);
        if (num != null && num.isNotEmpty && !num.contains(RegExp(r'^\d{2}[-/]\d{2}'))) {
          return num;
        }
      }
    }
    return null;
  }

  // --- GÉNÉRATION AUTOMATIQUE DE LA DESCRIPTION ---

  String _genererDescription(
    CategorieDepense categorie,
    String fournisseur,
    dynamic montants,
  ) {
    final f = (fournisseur.isNotEmpty && fournisseur != 'Fournisseur') ? ' - $fournisseur' : '';
    switch (categorie) {
      case CategorieDepense.essence:
        return 'Plein de carburant / Diesel$f';
      case CategorieDepense.repas:
        return 'Dîner / Restauration chantier$f';
      case CategorieDepense.outillage:
        return 'Outillage & Quincaillerie$f';
      case CategorieDepense.pieces:
        return 'Pièces de rechange urgentes$f';
      case CategorieDepense.stationnement:
        return 'Frais de stationnement / Péage$f';
      case CategorieDepense.hebergement:
        return 'Hébergement / Nuitée chantier$f';
      case CategorieDepense.autre:
        return 'Dépense de service route$f';
    }
  }

  // ============================================================================
  // 🧪 REÇUS VIRTUELS POUR DÉMO & TESTS IMMÉDIATS
  // ============================================================================

  static final List<({String nom, String texte, String icone})> exemplesRecus = [
    (
      nom: 'Pétro-Canada (Carburant Diesel)',
      texte: '''PÉTRO-CANADA #4928
1450 BOULEVARD WILFRID-HAMEL, QUÉBEC
DATE: 2026-09-28 10:14:22
POMPE #04 DIESEL
VOLUME: 78.44 L @ 1.829 \$/L
SOUS-TOTAL: 143.47 \$
TPS (5%): 7.17 \$
TVQ (9.975%): 14.31 \$
TOTAL CAD: 164.95 \$
TRANSACTION: TX-849204
MODE: CARTE VISA INTERAC
MERCI DE VOTRE VISITE''',
      icone: '⛽',
    ),
    (
      nom: 'St-Hubert (Dîner & Pourboire)',
      texte: '''ROTISSERIE ST-HUBERT
560 RUE BOUVIER, QUÉBEC
SERVEUR: MATHIEU   TABLE #12
DATE: 2026-09-28 12:35
1x TRIO CUISSE ROTIE: 22.95 \$
1x SOUPE DU JOUR: 4.50 \$
1x BREUVAGE: 3.50 \$
SOUS-TOTAL: 30.95 \$
TPS: 1.55 \$
TVQ: 3.09 \$
TOTAL REPAS: 35.59 \$
POURBOIRE: 5.50 \$
MONTANT TOTAL: 41.09 \$
FACTURE: SH-2026-9912''',
      icone: '🍗',
    ),
    (
      nom: 'Canadian Tire (Outillage & Attaches)',
      texte: '''CANADIAN TIRE #184
BOULEVARD LAURIER, QUEBEC
DATE: 2026-09-27
1x COFFRET EMBOUTS IMPACT: 49.99 \$
2x LOT COLLIERS SERRAGE: 18.50 \$
1x RUBAN ISOLANT 3M: 7.99 \$
SOUS-TOTAL: 76.48 \$
TPS: 3.82 \$
TVQ: 7.63 \$
TOTAL: 87.93 \$
COMMANDE: CT-481920''',
      icone: '🛠️',
    ),
    (
      nom: 'Tim Hortons (Café & Dîner rapide)',
      texte: '''TIM HORTONS RESTAURANT
DATE: 2026-09-28 07:15
1x CAFE GRAND REGULIER: 2.45 \$
1x SANDWICH MATIN OEUF BACON: 6.25 \$
SOUS-TOTAL: 8.70 \$
TPS: 0.44 \$
TVQ: 0.87 \$
TOTAL CAD: 10.01 \$
REF: TH-910248''',
      icone: '☕',
    ),
    (
      nom: 'NAPA Pièces d\'auto (Pièces urgentes)',
      texte: '''NAPA PIECES D AUTO QUEBEC
DATE: 2026-09-26
REF: NP-773129
2x RELAIS 24V HEAVY DUTY: 64.00 \$
1x FUSIBLE BLOC INDUSTRIEL: 38.50 \$
SOUS-TOTAL: 102.50 \$
TPS: 5.13 \$
TVQ: 10.22 \$
MONTANT TOTAL: 117.85 \$''',
      icone: '🔧',
    ),
    (
      nom: 'Facture Floue / Illisible (Test alerte)',
      texte: '''*** FLOU ***
...
--.-
''',
      icone: '⚠️',
    ),
  ];
}
