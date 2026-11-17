import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'rapport_pdf.dart';
import 'nip_service.dart';
import 'techniciens_service.dart';
import 'app_helpers.dart';

// ============================================================================
// ⏱️ MODÈLES DE DONNÉES DE LA FEUILLE DE TEMPS & PÉRIODE DE PAIE
// ============================================================================

enum TypeActivite {
  deplacement, // Temps de déplacement (PAYÉ)
  travail,     // Temps de travail / intervention (PAYÉ)
  attente,     // Temps d'attente sur site (CONSERVÉ ET PAYÉ)
  repas,       // Temps de repas / dîner (DÉDUIT DU TEMPS PAYÉ)
}

class ActiviteQuart {
  final String id;
  final TypeActivite type;
  final String description;
  final String? reference; // Numéro de commande ou client
  final DateTime debut;
  final DateTime? fin;
  final int? dureeMinutesFixe;

  ActiviteQuart({
    required this.id,
    required this.type,
    required this.description,
    this.reference,
    required this.debut,
    this.fin,
    this.dureeMinutesFixe,
  });

  int get dureeMinutesBrute {
    if (dureeMinutesFixe != null && dureeMinutesFixe! > 0) {
      return dureeMinutesFixe!;
    }
    final finDate = fin != null ? versHeureDeLEst(fin!) : heureActuelleEst();
    final debutDate = versHeureDeLEst(debut);
    final diff = finDate.difference(debutDate).inMinutes;
    return diff > 0 ? diff : 1;
  }

  /// Durée arrondie au quart d'heure (15 min).
  /// Règle de paie :
  /// - Déplacement (trajet) : TOUJOURS au quart d'heure supérieur (plus haut).
  /// - Travail (chantier) : TOUJOURS au quart d'heure supérieur (plus haut).
  /// - Pauses repas / attente : arrondi au quart d'heure.
  int get dureeMinutes {
    final brute = dureeMinutesBrute;
    final bool toujoursPlusHaut =
        (type == TypeActivite.deplacement || type == TypeActivite.travail);
    return arrondirAuQuartDHeureMinutes(brute, toujoursPlusHaut: toujoursPlusHaut);
  }

  /// Règle de paie :
  /// Le temps payé inclut les déplacements et conserve les temps d'attente.
  /// Les repas sont déduits du temps payé.
  bool get estPaye => type != TypeActivite.repas;

  String get libelleType {
    switch (type) {
      case TypeActivite.deplacement:
        return 'Déplacement / Trajet';
      case TypeActivite.travail:
        return 'Travail / Chantier';
      case TypeActivite.attente:
        return 'Temps d\'attente';
      case TypeActivite.repas:
        return 'Pause repas';
    }
  }

  Color get couleur {
    switch (type) {
      case TypeActivite.deplacement:
        return Colors.blueAccent;
      case TypeActivite.travail:
        return Colors.teal;
      case TypeActivite.attente:
        return Colors.amber.shade800;
      case TypeActivite.repas:
        return Colors.deepOrange;
    }
  }

  IconData get icone {
    switch (type) {
      case TypeActivite.deplacement:
        return Icons.directions_car_rounded;
      case TypeActivite.travail:
        return Icons.build_rounded;
      case TypeActivite.attente:
        return Icons.hourglass_top_rounded;
      case TypeActivite.repas:
        return Icons.restaurant_rounded;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'description': description,
        'reference': reference,
        'debut': debut.toIso8601String(),
        'fin': fin?.toIso8601String(),
        'dureeMinutesFixe': dureeMinutesFixe,
      };

  factory ActiviteQuart.fromJson(Map<String, dynamic> json) => ActiviteQuart(
        id: json['id'] as String,
        type: TypeActivite.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => TypeActivite.travail,
        ),
        description: json['description'] as String? ?? '',
        reference: json['reference'] as String?,
        debut: versHeureDeLEst(DateTime.parse(json['debut'] as String)),
        fin: json['fin'] != null ? versHeureDeLEst(DateTime.parse(json['fin'] as String)) : null,
        dureeMinutesFixe: json['dureeMinutesFixe'] as int?,
      );
}

// ============================================================================
// ⏱️ MODÈLE D'INTERVALLE DE PUNCH (ENTRÉE / SORTIE MULTIPLES)
// ============================================================================

class IntervallePunch {
  final DateTime entree;
  DateTime? sortie;

  IntervallePunch({
    required this.entree,
    this.sortie,
  });

  bool get estActif => sortie == null;

  int get dureeSecondes {
    final fin = sortie != null ? versHeureDeLEst(sortie!) : heureActuelleEst();
    final debut = versHeureDeLEst(entree);
    final diff = fin.difference(debut).inSeconds;
    return diff > 0 ? diff : 0;
  }

  int get dureeMinutes {
    final s = dureeSecondes;
    return (s / 60).round();
  }

  Map<String, dynamic> toJson() => {
        'entree': entree.toIso8601String(),
        'sortie': sortie?.toIso8601String(),
      };

  factory IntervallePunch.fromJson(Map<String, dynamic> json) => IntervallePunch(
        entree: versHeureDeLEst(DateTime.parse(json['entree'] as String)),
        sortie: json['sortie'] != null
            ? versHeureDeLEst(DateTime.parse(json['sortie'] as String))
            : null,
      );
}

class QuartDeTravail {
  final String id;
  final DateTime date;
  final String technicien;
  DateTime clockIn;
  DateTime? clockOut;
  final List<IntervallePunch> punches;
  final List<ActiviteQuart> activites;
  String notes;
  bool estEstime; // Vrai si les heures ont été estimées (ex: remise le vendredi)
  int? minutesEstimeesFixe;

  QuartDeTravail({
    required this.id,
    required this.date,
    required this.technicien,
    required this.clockIn,
    this.clockOut,
    List<IntervallePunch>? punches,
    List<ActiviteQuart>? activites,
    this.notes = '',
    this.estEstime = false,
    this.minutesEstimeesFixe,
  })  : activites = activites ?? [],
        punches = punches ?? [IntervallePunch(entree: clockIn, sortie: clockOut)];

  bool get estActif {
    if (estEstime) return false;
    if (punches.isNotEmpty) {
      return punches.last.sortie == null;
    }
    return clockOut == null;
  }

  /// Cumul en secondes de tous les intervalles de punch de la journée
  int get cumulSecondesPunches {
    if (punches.isEmpty) {
      final fin = clockOut != null ? versHeureDeLEst(clockOut!) : heureActuelleEst();
      final debut = versHeureDeLEst(clockIn);
      final diff = fin.difference(debut).inSeconds;
      return diff > 0 ? diff : 0;
    }
    int total = 0;
    for (final p in punches) {
      total += p.dureeSecondes;
    }
    return total;
  }

  /// Durée brute totale du quart en minutes (calculée à partir des punches)
  int get dureeBruteMinutes {
    if (minutesEstimeesFixe != null) {
      return minutesEstimeesFixe! + totalRepasMinutes;
    }
    return (cumulSecondesPunches / 60).round();
  }

  /// Somme des temps de repas (déduits du temps payé)
  int get totalRepasMinutes {
    int total = 0;
    for (final act in activites.where((a) => a.type == TypeActivite.repas)) {
      total += act.dureeMinutes;
    }
    // Si estimé sans sous-activité, repas par défaut de 45m
    if (total == 0 && estEstime) return 45;
    return total;
  }

  /// Somme des temps d'attente (conservés et payés)
  int get totalAttenteMinutes {
    int total = 0;
    for (final act in activites.where((a) => a.type == TypeActivite.attente)) {
      total += act.dureeMinutes;
    }
    return total;
  }

  /// Somme des temps de déplacement (inclus et payés)
  int get totalDeplacementMinutes {
    int total = 0;
    for (final act in activites.where((a) => a.type == TypeActivite.deplacement)) {
      total += act.dureeMinutes;
    }
    return total;
  }

  /// Somme des temps de travail direct
  int get totalTravailMinutes {
    int total = 0;
    for (final act in activites.where((a) => a.type == TypeActivite.travail)) {
      total += act.dureeMinutes;
    }
    return total;
  }

  /// Déduction de repas pour le calcul du punch :
  /// Si le technicien fait des pauses / punch-out (plusieurs intervalles),
  /// le temps hors punch est déjà exclu mécaniquement du cumul des punches.
  int get repasADeduireDuPunch {
    if (estEstime) {
      return totalRepasMinutes > 0 ? totalRepasMinutes : 45;
    }
    if (punches.length > 1) {
      return 0;
    }
    return totalRepasMinutes;
  }

  /// TEMPS PAYÉ :
  /// Durée nette du punch (arrondi au quart d'heure supérieur selon règles de paie)
  /// comparée à la somme des activités chantiers/trajets/attentes.
  /// Le technicien reçoit le montant payable pour chaque journée (max entre punch et activités).
  int get tempsPayeMinutes {
    if (minutesEstimeesFixe != null) {
      return minutesEstimeesFixe!;
    }
    final bruteShift = dureeBruteMinutes - repasADeduireDuPunch;
    final bruteNet = bruteShift > 0 ? bruteShift : 0;
    final bruteArrondi = arrondirAuQuartDHeureMinutes(bruteNet, toujoursPlusHaut: true);

    final sumActivites = totalDeplacementMinutes + totalTravailMinutes + totalAttenteMinutes;
    return sumActivites > bruteArrondi ? sumActivites : bruteArrondi;
  }

  String get tempsPayeFormate => formatMinutes(tempsPayeMinutes);

  double get tempsPayeDecimal =>
      double.parse((tempsPayeMinutes / 60.0).toStringAsFixed(2));

  String get nomJourSemaine {
    switch (date.weekday) {
      case DateTime.monday:
        return 'Lundi';
      case DateTime.tuesday:
        return 'Mardi';
      case DateTime.wednesday:
        return 'Mercredi';
      case DateTime.thursday:
        return 'Jeudi';
      case DateTime.friday:
        return 'Vendredi';
      case DateTime.saturday:
        return 'Samedi';
      case DateTime.sunday:
        return 'Dimanche';
      default:
        return '';
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'technicien': technicien,
        'clockIn': clockIn.toIso8601String(),
        'clockOut': clockOut?.toIso8601String(),
        'notes': notes,
        'estEstime': estEstime,
        'minutesEstimeesFixe': minutesEstimeesFixe,
        'punches': punches.map((p) => p.toJson()).toList(),
        'activites': activites.map((a) => a.toJson()).toList(),
      };

  factory QuartDeTravail.fromJson(Map<String, dynamic> json) {
    final cIn = versHeureDeLEst(DateTime.parse(json['clockIn'] as String));
    final cOut = json['clockOut'] != null
        ? versHeureDeLEst(DateTime.parse(json['clockOut'] as String))
        : null;
    final punchesList = (json['punches'] as List<dynamic>?)
            ?.map((p) => IntervallePunch.fromJson(p as Map<String, dynamic>))
            .toList() ??
        [IntervallePunch(entree: cIn, sortie: cOut)];

    return QuartDeTravail(
      id: json['id'] as String,
      date: versHeureDeLEst(DateTime.parse(json['date'] as String)),
      technicien: json['technicien'] as String? ?? 'Pierre-Olivier Patry',
      clockIn: cIn,
      clockOut: cOut,
      punches: punchesList,
      notes: json['notes'] as String? ?? '',
      estEstime: json['estEstime'] as bool? ?? false,
      minutesEstimeesFixe: json['minutesEstimeesFixe'] as int?,
      activites: (json['activites'] as List<dynamic>?)
              ?.map((a) => ActiviteQuart.fromJson(a as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}


/// Classe modélisant une période de paie de 2 semaines (remise le vendredi ou remise anticipée)
class PeriodePaie {
  final DateTime debut;
  final DateTime finVendredi;
  final DateTime? dateRemisePersonnalisee;
  final String technicien;
  final String numeroCamion;
  final List<QuartDeTravail> quartsSemaine1;
  final List<QuartDeTravail> quartsSemaine2;

  PeriodePaie({
    required this.debut,
    required this.finVendredi,
    this.dateRemisePersonnalisee,
    required this.technicien,
    this.numeroCamion = 'Camion #102',
    required this.quartsSemaine1,
    required this.quartsSemaine2,
  });

  List<QuartDeTravail> get tousLesQuarts => [...quartsSemaine1, ...quartsSemaine2];

  /// Date de remise effective (anticipée ou vendredi standard)
  DateTime get dateRemiseEffective => dateRemisePersonnalisee ?? finVendredi;

  /// Vrai si la feuille est remise plus tôt que le vendredi de fin de période
  bool get estRemiseAnticipee {
    final remise = DateTime(dateRemiseEffective.year, dateRemiseEffective.month, dateRemiseEffective.day);
    final ven = DateTime(finVendredi.year, finVendredi.month, finVendredi.day);
    return remise.isBefore(ven);
  }

  String get nomJourDateRemise => formatNomJour(dateRemiseEffective.weekday);

  int get totalMinutesSemaine1 =>
      quartsSemaine1.fold(0, (sum, q) => sum + q.tempsPayeMinutes);

  int get totalMinutesSemaine2 =>
      quartsSemaine2.fold(0, (sum, q) => sum + q.tempsPayeMinutes);

  int get totalMinutesPeriode => totalMinutesSemaine1 + totalMinutesSemaine2;

  double get totalHeuresDecimalesPeriode =>
      double.parse((totalMinutesPeriode / 60.0).toStringAsFixed(2));

  int get totalDeplacementMinutes =>
      tousLesQuarts.fold(0, (sum, q) => sum + q.totalDeplacementMinutes);

  int get totalTravailMinutes =>
      tousLesQuarts.fold(0, (sum, q) => sum + q.totalTravailMinutes);

  int get totalAttenteMinutes =>
      tousLesQuarts.fold(0, (sum, q) => sum + q.totalAttenteMinutes);

  int get totalRepasMinutes =>
      tousLesQuarts.fold(0, (sum, q) => sum + q.totalRepasMinutes);

  QuartDeTravail? get quartDernierVendredi {
    try {
      return quartsSemaine2.firstWhere(
        (q) => q.date.year == finVendredi.year &&
            q.date.month == finVendredi.month &&
            q.date.day == finVendredi.day,
      );
    } catch (_) {
      return null;
    }
  }

  bool get dernierVendrediEstEstime =>
      quartDernierVendredi != null && quartDernierVendredi!.estEstime;
}

String formatNomJour(int weekday) {
  switch (weekday) {
    case DateTime.monday:
      return 'Lundi';
    case DateTime.tuesday:
      return 'Mardi';
    case DateTime.wednesday:
      return 'Mercredi';
    case DateTime.thursday:
      return 'Jeudi';
    case DateTime.friday:
      return 'Vendredi';
    case DateTime.saturday:
      return 'Samedi';
    case DateTime.sunday:
      return 'Dimanche';
    default:
      return '';
  }
}

String formatMinutes(int minutes) {
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (m == 0) return '${h}h';
  return '${h}h ${m.toString().padLeft(2, '0')}m';
}

String formatHeureDateTime(DateTime dt) {
  final est = versHeureDeLEst(dt);
  final h = est.hour.toString().padLeft(2, '0');
  final m = est.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

// ============================================================================
// 💾 GESTION DE LA PERSISTANCE & CALCUL DE LA PÉRIODE DE 2 SEMAINES
// ============================================================================

class FeuilleDeTempsRepository {
  static final FeuilleDeTempsRepository instance = FeuilleDeTempsRepository._();
  FeuilleDeTempsRepository._();

  List<QuartDeTravail> _quarts = [];
  DateTime? _dateRemisePersonnalisee;
  final Map<String, DateTime?> _datesRemiseParTechnicien = {};
  bool _initialise = false;

  static String camionPourTechnicien(String nom) {
    final norm = NipSecuriteService.normaliserNomTechnicien(nom);
    if (norm == 'David Hestin') return 'Camion #101';
    if (norm == 'Pierre-Olivier Patry') return 'Camion #102';
    if (norm == 'Jean-François Allie') return 'Camion #103';
    return 'Camion #100';
  }

  DateTime? getDateRemisePersonnalisee({String? technicien}) {
    if (technicien == null || technicien.trim().isEmpty) return _dateRemisePersonnalisee;
    final norm = NipSecuriteService.normaliserNomTechnicien(technicien);
    return _datesRemiseParTechnicien[norm];
  }

  DateTime? get dateRemisePersonnalisee => _dateRemisePersonnalisee;

  Future<List<QuartDeTravail>> getQuarts({String? technicien}) async {
    if (!_initialise) {
      await charger();
    }
    if (technicien == null || technicien.trim().isEmpty) {
      return _quarts;
    }
    final norm = NipSecuriteService.normaliserNomTechnicien(technicien).toLowerCase();
    final brut = technicien.trim().toLowerCase();
    return _quarts.where((q) {
      final qNorm = NipSecuriteService.normaliserNomTechnicien(q.technicien).toLowerCase();
      final qBrut = q.technicien.trim().toLowerCase();
      return qNorm == norm || qBrut == brut;
    }).toList();
  }

  List<QuartDeTravail> get quarts => _quarts;

  QuartDeTravail? getQuartActif({String? technicien}) {
    try {
      if (technicien == null || technicien.trim().isEmpty) {
        return _quarts.firstWhere((q) => q.estActif);
      }
      final norm = NipSecuriteService.normaliserNomTechnicien(technicien).toLowerCase();
      final brut = technicien.trim().toLowerCase();
      return _quarts.firstWhere((q) {
        final qNorm = NipSecuriteService.normaliserNomTechnicien(q.technicien).toLowerCase();
        final qBrut = q.technicien.trim().toLowerCase();
        return q.estActif && (qNorm == norm || qBrut == brut);
      });
    } catch (_) {
      return null;
    }
  }

  QuartDeTravail? getQuartPourJour(DateTime date, {String? technicien}) {
    final techNorm = (technicien != null && technicien.trim().isNotEmpty)
        ? NipSecuriteService.normaliserNomTechnicien(technicien).toLowerCase()
        : null;
    final techBrut = technicien?.trim().toLowerCase();
    try {
      final candidats = _quarts.where((q) {
        final memeJour = q.date.year == date.year &&
            q.date.month == date.month &&
            q.date.day == date.day;
        if (!memeJour) return false;
        if (techNorm == null) return true;
        final qNorm = NipSecuriteService.normaliserNomTechnicien(q.technicien).toLowerCase();
        final qBrut = q.technicien.trim().toLowerCase();
        return qNorm == techNorm || qBrut == techBrut;
      }).toList();

      if (candidats.isEmpty) return null;
      // Priorité absolue au quart actif !
      final actif = candidats.where((q) => q.estActif);
      if (actif.isNotEmpty) return actif.first;
      return candidats.first;
    } catch (_) {
      return null;
    }
  }

  /// Calcule et retourne la période de paie de 2 semaines se terminant ce vendredi pour le technicien
  Future<PeriodePaie> getPeriodePaieActuelle({
    DateTime? dateReference,
    String? technicien,
    bool syncSupabase = true,
  }) async {
    if (!_initialise) {
      await charger();
    }
    if (syncSupabase) {
      try {
        await synchroniserDepuisSupabase();
      } catch (_) {}
    }
    final now = dateReference ?? DateTime.now();
    final techNom = (technicien != null && technicien.trim().isNotEmpty)
        ? NipSecuriteService.normaliserNomTechnicien(technicien)
        : 'Pierre-Olivier Patry';
    final camion = camionPourTechnicien(techNom);

    // Déterminer le vendredi de remise de paie
    // (Si aujourd'hui est samedi ou dimanche, c'était le vendredi précédent)
    DateTime finVendredi;
    if (now.weekday <= DateTime.friday) {
      finVendredi = now.add(Duration(days: DateTime.friday - now.weekday));
    } else {
      finVendredi = now.subtract(Duration(days: now.weekday - DateTime.friday));
    }
    finVendredi = DateTime(finVendredi.year, finVendredi.month, finVendredi.day);

    // Début de la période de 2 semaines = lundi de la semaine précédente (11 jours avant)
    final debutLundiSemaine1 = finVendredi.subtract(const Duration(days: 11));
    final debutSemaine2 = finVendredi.subtract(const Duration(days: 4)); // Lundi sem 2

    final all = await getQuarts(technicien: techNom);

    // Répartition des quarts par semaine
    final quartsSem1 = <QuartDeTravail>[];
    final quartsSem2 = <QuartDeTravail>[];

    for (int i = 0; i < 5; i++) {
      final jourSem1 = debutLundiSemaine1.add(Duration(days: i));
      final q1 = _trouverOuCreerQuartPourJour(all, jourSem1, techNom);
      quartsSem1.add(q1);

      final jourSem2 = debutSemaine2.add(Duration(days: i));
      final q2 = _trouverOuCreerQuartPourJour(
        all,
        jourSem2,
        techNom,
        estDernierVendredi: (i == 4),
      );
      quartsSem2.add(q2);
    }

    final dateRemise = getDateRemisePersonnalisee(technicien: techNom);

    return PeriodePaie(
      debut: debutLundiSemaine1,
      finVendredi: finVendredi,
      dateRemisePersonnalisee: dateRemise,
      technicien: techNom,
      numeroCamion: camion,
      quartsSemaine1: quartsSem1,
      quartsSemaine2: quartsSem2,
    );
  }

  QuartDeTravail _trouverOuCreerQuartPourJour(
    List<QuartDeTravail> liste,
    DateTime date,
    String technicien, {
    bool estDernierVendredi = false,
  }) {
    final techNorm = NipSecuriteService.normaliserNomTechnicien(technicien).toLowerCase();
    final brut = technicien.trim().toLowerCase();
    final trouve = liste.where(
      (q) => q.date.year == date.year &&
          q.date.month == date.month &&
          q.date.day == date.day &&
          (NipSecuriteService.normaliserNomTechnicien(q.technicien).toLowerCase() == techNorm ||
           q.technicien.trim().toLowerCase() == brut),
    );
    if (trouve.isNotEmpty) {
      return trouve.firstWhere((q) => q.estActif, orElse: () => trouve.first);
    }

    final slug = techNorm.replaceAll(' ', '_');
    final clockIn = DateTime(date.year, date.month, date.day, 7, 30);

    return QuartDeTravail(
      id: 'jour_${slug}_${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}',
      date: date,
      technicien: technicien,
      clockIn: clockIn,
      clockOut: clockIn,
      notes: '',
      activites: [],
    );
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
      return File('${dir.path}\\feuilles_de_temps.json');
    } catch (_) {
      return null;
    }
  }

  Future<void> charger() async {
    _initialise = true;
    try {
      final file = _getFichierSauvegarde();
      if (file != null && await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isEmpty) {
          _initialiserDonneesParDefaut();
          return;
        }
        final dynamic decoded = jsonDecode(content);
        if (decoded is Map<String, dynamic>) {
          if (decoded['dateRemisePersonnalisee'] != null) {
            _dateRemisePersonnalisee =
                DateTime.tryParse(decoded['dateRemisePersonnalisee'] as String);
          }
          if (decoded['datesRemiseParTechnicien'] is Map) {
            (decoded['datesRemiseParTechnicien'] as Map).forEach((k, v) {
              if (v != null) {
                _datesRemiseParTechnicien[k.toString()] = DateTime.tryParse(v.toString());
              }
            });
          }
          final list = decoded['quarts'] as List<dynamic>?;
          if (list != null) {
            _quarts = list
                .map((item) => QuartDeTravail.fromJson(item as Map<String, dynamic>))
                .toList();
            return;
          }
        } else if (decoded is List<dynamic>) {
          _quarts = decoded
              .map((item) => QuartDeTravail.fromJson(item as Map<String, dynamic>))
              .toList();
          return;
        }
      }
    } catch (e) {
      debugPrint('Erreur chargement local feuilles de temps: $e');
    }

    _initialiserDonneesParDefaut();
  }

  void _initialiserDonneesParDefaut() {
    _quarts = [];
  }

  Future<void> sauvegarder() async {
    try {
      final file = _getFichierSauvegarde();
      if (file != null) {
        final data = {
          'dateRemisePersonnalisee': _dateRemisePersonnalisee?.toIso8601String(),
          'datesRemiseParTechnicien': _datesRemiseParTechnicien.map((k, v) => MapEntry(k, v?.toIso8601String())),
          'quarts': _quarts.map((q) => q.toJson()).toList(),
        };
        final jsonStr = jsonEncode(data);
        await file.writeAsString(jsonStr, flush: true);
      }
    } catch (e) {
      debugPrint('Erreur sauvegarde locale feuilles de temps: $e');
    }
  }

  /// Enregistre ou met à jour n'importe quel quart/journée
  Future<void> enregistrerQuart(QuartDeTravail quart) async {
    final techNorm = NipSecuriteService.normaliserNomTechnicien(quart.technicien).toLowerCase();
    final idx = _quarts.indexWhere(
      (q) => q.id == quart.id ||
          (q.date.year == quart.date.year &&
              q.date.month == quart.date.month &&
              q.date.day == quart.date.day &&
              NipSecuriteService.normaliserNomTechnicien(q.technicien).toLowerCase() == techNorm),
    );
    if (idx >= 0) {
      _quarts[idx] = quart;
    } else {
      _quarts.insert(0, quart);
    }
    await sauvegarder();
  }

  Future<void> definirDateRemise(DateTime? date, {String? technicien}) async {
    final val = date != null ? DateTime(date.year, date.month, date.day) : null;
    if (technicien != null && technicien.trim().isNotEmpty) {
      final norm = NipSecuriteService.normaliserNomTechnicien(technicien);
      if (val != null) {
        _datesRemiseParTechnicien[norm] = val;
      } else {
        _datesRemiseParTechnicien.remove(norm);
      }
    } else {
      _dateRemisePersonnalisee = val;
    }
    await sauvegarder();
  }

  Future<void> reinitialiserDateRemise({String? technicien}) async {
    if (technicien != null && technicien.trim().isNotEmpty) {
      final norm = NipSecuriteService.normaliserNomTechnicien(technicien);
      _datesRemiseParTechnicien.remove(norm);
    } else {
      _dateRemisePersonnalisee = null;
    }
    await sauvegarder();
  }

  Future<void> appliquerRemiseAnticipee({
    required DateTime dateRemise,
    int minutesParJourRestant = 480,
    String? notes,
    String? technicien,
  }) async {
    final techNom = (technicien != null && technicien.trim().isNotEmpty)
        ? NipSecuriteService.normaliserNomTechnicien(technicien)
        : 'Pierre-Olivier Patry';

    await definirDateRemise(dateRemise, technicien: techNom);

    final periode = await getPeriodePaieActuelle(technicien: techNom);
    final noteEstime = notes != null && notes.trim().isNotEmpty
        ? notes.trim()
        : 'Estimé pour remise anticipée de paie le ${formatNomJour(dateRemise.weekday)}';

    final remiseNorm = DateTime(dateRemise.year, dateRemise.month, dateRemise.day);

    for (final q in periode.quartsSemaine2) {
      final qDate = DateTime(q.date.year, q.date.month, q.date.day);
      if (qDate.isAfter(remiseNorm) || qDate.isAtSameMomentAs(remiseNorm)) {
        q.estEstime = true;
        q.minutesEstimeesFixe = minutesParJourRestant;
        q.notes = noteEstime;
        q.clockOut = q.clockIn.add(Duration(minutes: minutesParJourRestant + 45));
        await enregistrerQuart(q);
      }
    }
    await sauvegarder();
  }

  Future<void> estimerDernierVendredi(
    DateTime dateVendredi,
    int minutesPayees, {
    String? notes,
    String? technicien,
  }) async {
    await estimerJour(
      dateVendredi,
      minutesPayees,
      notes: notes ?? 'Estimé pour remise de paie le vendredi',
      technicien: technicien,
    );
  }

  Future<void> estimerJour(
    DateTime date,
    int minutesPayees, {
    String? notes,
    bool estEstime = true,
    String? technicien,
  }) async {
    final techNom = (technicien != null && technicien.trim().isNotEmpty)
        ? NipSecuriteService.normaliserNomTechnicien(technicien)
        : 'Pierre-Olivier Patry';
    final techNorm = techNom.toLowerCase();

    final idx = _quarts.indexWhere(
      (q) => q.date.year == date.year &&
          q.date.month == date.month &&
          q.date.day == date.day &&
          NipSecuriteService.normaliserNomTechnicien(q.technicien).toLowerCase() == techNorm,
    );

    final clockIn = DateTime(date.year, date.month, date.day, 7, 30);
    final clockOut = clockIn.add(Duration(minutes: minutesPayees + 45));

    if (idx >= 0) {
      final q = _quarts[idx];
      q.estEstime = estEstime;
      q.minutesEstimeesFixe = minutesPayees;
      q.clockIn = clockIn;
      q.clockOut = clockOut;
      if (notes != null) q.notes = notes;
    } else {
      final nouveau = QuartDeTravail(
        id: 'estime_${techNorm.replaceAll(' ', '_')}_${date.millisecondsSinceEpoch}',
        date: date,
        technicien: techNom,
        clockIn: clockIn,
        clockOut: clockOut,
        estEstime: estEstime,
        minutesEstimeesFixe: minutesPayees,
        notes: notes ?? 'Estimé pour remise de paie',
      );
      _quarts.insert(0, nouveau);
    }
    await sauvegarder();
  }

  /// Callback déclenché lorsqu'une intervention est mise en pause suite à un clock-out
  static Function(String technicien)? onInterventionsModifieesParClockOut;

  Future<QuartDeTravail> clockIn({
    String? technicien,
    DateTime? heure,
  }) async {
    if (!_initialise) {
      await charger();
    }
    final techNom = (technicien != null && technicien.trim().isNotEmpty)
        ? NipSecuriteService.normaliserNomTechnicien(technicien)
        : 'Pierre-Olivier Patry';
    final techNorm = techNom.toLowerCase();
    final now = heure != null ? versHeureDeLEst(heure) : heureActuelleEst();
    final dateJour = DateTime(now.year, now.month, now.day);

    // Chercher s'il existe déjà un quart pour aujourd'hui et ce technicien
    final idx = _quarts.indexWhere((q) =>
        q.date.year == dateJour.year &&
        q.date.month == dateJour.month &&
        q.date.day == dateJour.day &&
        (NipSecuriteService.normaliserNomTechnicien(q.technicien).toLowerCase() == techNorm ||
            q.technicien.trim().toLowerCase() == techNom.toLowerCase()));

    QuartDeTravail quart;
    if (idx >= 0) {
      quart = _quarts[idx];
      quart.estEstime = false;
      quart.minutesEstimeesFixe = null;

      // Si le quart a déjà des punches :
      if (quart.punches.isNotEmpty) {
        if (quart.punches.last.sortie != null) {
          // Nouveau punch interval pour reprendre l'accumulation !
          quart.punches.add(IntervallePunch(entree: now, sortie: null));
          quart.clockOut = null; // Réactivé
        }
      } else {
        quart.punches.add(IntervallePunch(entree: now, sortie: null));
        quart.clockIn = now;
        quart.clockOut = null;
      }

      // Nettoyer d'éventuels doublons résiduels de la même journée
      _quarts.removeWhere((q) =>
          q != quart &&
          q.date.year == dateJour.year &&
          q.date.month == dateJour.month &&
          q.date.day == dateJour.day &&
          (NipSecuriteService.normaliserNomTechnicien(q.technicien).toLowerCase() == techNorm ||
              q.technicien.trim().toLowerCase() == techNom.toLowerCase()));
    } else {
      quart = QuartDeTravail(
        id: 'quart_${techNorm.replaceAll(' ', '_')}_${dateJour.year}${dateJour.month.toString().padLeft(2, '0')}${dateJour.day.toString().padLeft(2, '0')}',
        date: dateJour,
        technicien: techNom,
        clockIn: now,
        clockOut: null,
        punches: [IntervallePunch(entree: now, sortie: null)],
      );
      _quarts.insert(0, quart);
    }
    await sauvegarder();
    return quart;
  }

  /// S'assure que le technicien est actuellement Punch-In.
  /// Si le quart n'existe pas ou est en pause / clock-out, déclenche un clockIn automatique.
  Future<QuartDeTravail> assurerClockInActif({required String technicien, DateTime? heure}) async {
    if (!_initialise) await charger();
    final now = heure != null ? versHeureDeLEst(heure) : heureActuelleEst();
    final quart = getQuartPourJour(now, technicien: technicien);
    if (quart == null || !quart.estActif) {
      return await clockIn(technicien: technicien, heure: now);
    }
    return quart;
  }

  Future<void> clockOut(String? quartId, {String? technicien, DateTime? heure}) async {
    if (!_initialise) {
      await charger();
    }
    final now = heure != null ? versHeureDeLEst(heure) : heureActuelleEst();
    QuartDeTravail? quart;
    if (quartId != null && quartId.isNotEmpty) {
      final idx = _quarts.indexWhere((q) => q.id == quartId);
      if (idx >= 0) {
        quart = _quarts[idx];
      }
    }
    if (quart == null) {
      final techNorm = (technicien != null && technicien.trim().isNotEmpty)
          ? NipSecuriteService.normaliserNomTechnicien(technicien).toLowerCase()
          : null;
      final techBrut = technicien?.trim().toLowerCase();
      final aujourdhui = DateTime.now();
      for (final q in _quarts) {
        if (q.estActif &&
            q.date.year == aujourdhui.year &&
            q.date.month == aujourdhui.month &&
            q.date.day == aujourdhui.day) {
          if (techNorm != null) {
            final qNorm = NipSecuriteService.normaliserNomTechnicien(q.technicien).toLowerCase();
            final qBrut = q.technicien.trim().toLowerCase();
            if (qNorm != techNorm && qBrut != techBrut) continue;
          }
          quart = q;
          break;
        }
      }
    }

    if (quart != null) {
      if (quart.punches.isNotEmpty && quart.punches.last.sortie == null) {
        quart.punches.last.sortie = now;
      } else if (quart.punches.isEmpty) {
        quart.punches.add(IntervallePunch(entree: quart.clockIn, sortie: now));
      }
      quart.clockOut = now;
      await sauvegarder();

      // AUTOMATISME : Mettre en pause toute intervention active pour ce technicien
      await mettreEnPauseInterventionsActives(quart.technicien, heurePause: now);
    }
  }

  /// Met automatiquement en pause toute intervention active (en route ou sur chantier) assignée à ce technicien
  Future<int> mettreEnPauseInterventionsActives(String nomTechnicien, {DateTime? heurePause}) async {
    final now = (heurePause != null ? versHeureDeLEst(heurePause) : heureActuelleEst()).toUtc();
    final techNorm = NipSecuriteService.normaliserNomTechnicien(nomTechnicien).toLowerCase();
    int count = 0;

    try {
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('interventions')
          .select()
          .inFilter('statut', ['En route', 'Arrivé']);

      for (final row in response) {
        final rowTech = (row['nom_technicien'] ?? '').toString().trim();
        final rowTechNorm = NipSecuriteService.normaliserNomTechnicien(rowTech).toLowerCase();
        if (rowTechNorm == techNorm || rowTech.toLowerCase() == nomTechnicien.trim().toLowerCase()) {
          final id = row['id'].toString();
          final statut = row['statut'] as String?;
          final updates = <String, dynamic>{};

          if (statut == 'En route') {
            updates['statut'] = 'En pause';
            updates['en_pause'] = true;
            updates['heure_debut_pause'] = now.toIso8601String();
          } else if (statut == 'Arrivé') {
            updates['statut'] = 'Intervention en pause';
            updates['en_pause_chantier'] = true;
            updates['heure_debut_pause_chantier'] = now.toIso8601String();
            updates['motif_pause_chantier'] = 'Technicien Clock-Out (Pause)';
          }

          if (updates.isNotEmpty) {
            final clean = <String, dynamic>{};
            for (final e in updates.entries) {
              if (kColonnesInterventionsSupabase.contains(e.key)) clean[e.key] = e.value;
            }
            await supabase.from('interventions').update(clean).eq('id', id);
            count++;
          }
        }
      }
    } catch (_) {}

    try {
      onInterventionsModifieesParClockOut?.call(nomTechnicien);
    } catch (_) {}

    return count;
  }

  Future<void> ajouterActivite(String quartId, ActiviteQuart activite) async {
    final quart = _quarts.firstWhere((q) => q.id == quartId);
    quart.activites.add(activite);
    await sauvegarder();
  }

  Future<void> supprimerActivite(String quartId, String activiteId) async {
    final quart = _quarts.firstWhere((q) => q.id == quartId);
    quart.activites.removeWhere((a) => a.id == activiteId);
    await sauvegarder();
  }

  /// Synchronise depuis Supabase toutes les interventions pour alimenter les feuilles de temps
  Future<void> synchroniserDepuisSupabase() async {
    try {
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('interventions')
          .select()
          .order('created_at', ascending: false)
          .limit(50);
      for (final item in response) {
        await synchroniserIntervention(item, sauvegarderApres: false);
      }
      await sauvegarder();
    } catch (_) {}
  }

  /// Synchronise une liste d'interventions réelles avec les feuilles de temps
  Future<void> synchroniserInterventions(List<Map<String, dynamic>> interventions) async {
    if (!_initialise) {
      await charger();
    }
    for (final it in interventions) {
      await synchroniserIntervention(it, sauvegarderApres: false);
    }
    await sauvegarder();
  }

  /// Synchronise une intervention spécifique avec le quart du technicien concerné
  Future<void> synchroniserIntervention(Map<String, dynamic> it, {bool sauvegarderApres = true}) async {
    if (!_initialise) {
      await charger();
    }

    final nomTechBrut = (it['nom_technicien'] ?? '').toString().trim();
    final techNom = nomTechBrut.isNotEmpty
        ? NipSecuriteService.normaliserNomTechnicien(nomTechBrut)
        : 'Pierre-Olivier Patry';
    final techNorm = techNom.toLowerCase();

    // Déterminer la date de l'intervention
    final dateStr = (it['heure_depart_trajet'] ??
            it['heure_arrivee_site'] ??
            it['date_chantier'] ??
            it['date_rendez_vous'] ??
            it['created_at'])
        ?.toString();
    final now = heureActuelleEst();
    DateTime dateJour = DateTime(now.year, now.month, now.day);
    if (dateStr != null && dateStr.isNotEmpty) {
      final parsed = DateTime.tryParse(dateStr);
      if (parsed != null) {
        final est = versHeureDeLEst(parsed);
        dateJour = DateTime(est.year, est.month, est.day);
      }
    }

    // Trouver ou créer le quart pour cette journée et ce technicien
    final idxQuart = _quarts.indexWhere(
      (q) =>
          q.date.year == dateJour.year &&
          q.date.month == dateJour.month &&
          q.date.day == dateJour.day &&
          (NipSecuriteService.normaliserNomTechnicien(q.technicien).toLowerCase() == techNorm ||
              q.technicien.trim().toLowerCase() == nomTechBrut.toLowerCase()),
    );

    QuartDeTravail quart;
    if (idxQuart >= 0) {
      quart = _quarts[idxQuart];
    } else {
      final dateInitiale = (dateStr != null && dateStr.isNotEmpty)
          ? (DateTime.tryParse(dateStr) != null ? versHeureDeLEst(DateTime.parse(dateStr)) : dateJour)
          : dateJour;
      quart = QuartDeTravail(
        id: 'quart_${techNorm.replaceAll(' ', '_')}_${dateJour.year}${dateJour.month.toString().padLeft(2, '0')}${dateJour.day.toString().padLeft(2, '0')}',
        date: dateJour,
        technicien: techNom,
        clockIn: dateInitiale,
        clockOut: null,
        punches: [IntervallePunch(entree: dateInitiale, sortie: null)],
        notes: 'Interventions chantiers Rayco Wylie',
      );
      _quarts.insert(0, quart);
    }

    final String interventionId = (it['id'] ?? 'cmd_${dateJour.millisecondsSinceEpoch}').toString();
    final String client = (it['nom_client'] ?? 'Client').toString();
    final String ref = (it['numero_bon_commande'] ?? it['numero_commande'] ?? it['numero_reference'] ?? interventionId).toString();
    final String machine = (it['type_machine'] ?? '').toString();

    // 1. TEMPS DE DÉPLACEMENT / TRAJET
    final departTrajetStr = it['heure_depart_trajet'] as String?;
    if (departTrajetStr != null && departTrajetStr.isNotEmpty) {
      final departRaw = DateTime.tryParse(departTrajetStr);
      if (departRaw != null) {
        final depart = versHeureDeLEst(departRaw);
        if (quart.clockIn.isAfter(depart)) {
          quart.clockIn = depart;
          if (quart.punches.isNotEmpty && quart.punches.first.entree.isAfter(depart)) {
            quart.punches[0] = IntervallePunch(entree: depart, sortie: quart.punches.first.sortie);
          }
        }

        DateTime finTrajet = now;
        final arriveeStr = it['heure_arrivee_site'] as String?;
        if (arriveeStr != null && arriveeStr.isNotEmpty) {
          final arrRaw = DateTime.tryParse(arriveeStr);
          if (arrRaw != null) finTrajet = versHeureDeLEst(arrRaw);
        } else if (it['statut'] == 'En route' || it['statut'] == 'En pause') {
          finTrajet = now;
        }

        int pauseTrajetSec = 0;
        if (it['duree_pause_secondes'] is num) {
          pauseTrajetSec = (it['duree_pause_secondes'] as num).toInt();
        }

        int secTrajet = finTrajet.difference(depart).inSeconds - pauseTrajetSec;
        if (secTrajet < 0) secTrajet = 0;
        int minTrajet = (secTrajet / 60).round();
        if (minTrajet == 0 && (it['statut'] == 'En route' || it['statut'] == 'Arrivé' || it['statut'] == 'Complété' || it['statut'] == 'En attente d\'approbation')) {
          minTrajet = 1;
        }

        final bool trajetTermine = arriveeStr != null && arriveeStr.isNotEmpty;
        final actTrajetId = 'trajet_$interventionId';
        final existingIdx = quart.activites.indexWhere((a) => a.id == actTrajetId || (a.reference == ref && a.type == TypeActivite.deplacement));
        final activiteTrajet = ActiviteQuart(
          id: actTrajetId,
          type: TypeActivite.deplacement,
          description: 'Trajet vers $client',
          reference: ref,
          debut: depart,
          fin: trajetTermine ? finTrajet : null,
          dureeMinutesFixe: trajetTermine ? minTrajet : null,
        );

        if (existingIdx >= 0) {
          quart.activites[existingIdx] = activiteTrajet;
        } else {
          quart.activites.add(activiteTrajet);
        }
      }
    }

    // 2. TEMPS EN CHANTIER (TRAVAIL)
    final arriveeChantierStr = it['heure_arrivee_site'] as String?;
    if (arriveeChantierStr != null && arriveeChantierStr.isNotEmpty) {
      final arrRaw = DateTime.tryParse(arriveeChantierStr);
      if (arrRaw != null) {
        final arrivee = versHeureDeLEst(arrRaw);
        DateTime finChantier = now;
        final clotureStr = (it['heure_cloture'] ?? it['heure_signature']) as String?;
        if (clotureStr != null && clotureStr.isNotEmpty) {
          final cloRaw = DateTime.tryParse(clotureStr);
          if (cloRaw != null) finChantier = versHeureDeLEst(cloRaw);
        }

        int pauseChantierSec = 0;
        if (it['duree_pause_chantier_secondes'] is num) {
          pauseChantierSec = (it['duree_pause_chantier_secondes'] as num).toInt();
        }

        int secChantier = finChantier.difference(arrivee).inSeconds - pauseChantierSec;
        if (secChantier < 0) secChantier = 0;
        int minChantier = (secChantier / 60).round();
        if (minChantier == 0 && (it['statut'] == 'Arrivé' || it['statut'] == 'Complété' || it['statut'] == 'En attente d\'approbation' || it['statut'] == 'Intervention en pause')) {
          minChantier = 1;
        }

        final bool chantierTermine = clotureStr != null && clotureStr.isNotEmpty;
        final actChantierId = 'travail_$interventionId';
        final existingIdx = quart.activites.indexWhere((a) => a.id == actChantierId || (a.reference == ref && a.type == TypeActivite.travail));
        final desc = machine.isNotEmpty ? 'Intervention sur $client ($machine)' : 'Intervention sur $client';
        final activiteTravail = ActiviteQuart(
          id: actChantierId,
          type: TypeActivite.travail,
          description: desc,
          reference: ref,
          debut: arrivee,
          fin: chantierTermine ? finChantier : null,
          dureeMinutesFixe: chantierTermine ? minChantier : null,
        );

        if (existingIdx >= 0) {
          quart.activites[existingIdx] = activiteTravail;
        } else {
          quart.activites.add(activiteTravail);
        }
      }
    }

    // 3. PAUSES CHANTIER (Repas déduit vs Attente payée)
    int pauseChantierSec = 0;
    if (it['duree_pause_chantier_secondes'] is num) {
      pauseChantierSec = (it['duree_pause_chantier_secondes'] as num).toInt();
    }
    final motif = (it['motif_pause_chantier'] ?? '').toString().toLowerCase();

    if (pauseChantierSec > 0) {
      int minPause = (pauseChantierSec / 60).round();
      if (minPause <= 0) minPause = 1;

      final bool estRepas = motif.contains('repas') || motif.contains('dîner') || motif.contains('diner') || motif.contains('lunch');
      final typePause = estRepas ? TypeActivite.repas : TypeActivite.attente;
      final actPauseId = 'pause_${estRepas ? "repas" : "attente"}_$interventionId';

      final existingIdx = quart.activites.indexWhere((a) => a.id == actPauseId || (a.reference == ref && a.type == typePause));
      final activitePause = ActiviteQuart(
        id: actPauseId,
        type: typePause,
        description: estRepas ? 'Pause repas / dîner ($client)' : (motif.isNotEmpty ? '${it["motif_pause_chantier"]} ($client)' : 'Attente chantier ($client)'),
        reference: ref,
        debut: dateJour.add(Duration(hours: estRepas ? 12 : 10)),
        fin: dateJour.add(Duration(hours: estRepas ? 12 : 10, minutes: minPause)),
        dureeMinutesFixe: minPause,
      );

      if (existingIdx >= 0) {
        quart.activites[existingIdx] = activitePause;
      } else {
        quart.activites.add(activitePause);
      }
    }

    // 4. TEMPS DE DÉPLACEMENT RETOUR (estimé ou réel)
    final retourStr = it['duree_retour'] ?? it['duree_trajet'];
    int secRetour = 0;
    if (it['duree_retour_secondes'] is num && (it['duree_retour_secondes'] as num) > 0) {
      secRetour = (it['duree_retour_secondes'] as num).toInt();
    } else if (retourStr != null) {
      secRetour = dureeChaineVersSecondes(retourStr);
    }
    if (secRetour > 0 && (it['statut'] == 'Arrivé' || it['statut'] == 'Complété' || it['statut'] == 'En attente d\'approbation')) {
      int minRetour = arrondirAuQuartDHeureMinutes((secRetour / 60).round(), toujoursPlusHaut: true);
      if (minRetour <= 0) minRetour = 15;
      final actRetourId = 'retour_$interventionId';
      final existingIdx = quart.activites.indexWhere(
          (a) => a.id == actRetourId || (a.reference == ref && a.description.contains('retour')));
      final clotureStr = (it['heure_cloture'] ?? it['heure_signature']) as String?;
      DateTime debutRetour = now;
      if (clotureStr != null && clotureStr.isNotEmpty) {
        final parsedClo = DateTime.tryParse(clotureStr);
        if (parsedClo != null) debutRetour = versHeureDeLEst(parsedClo);
      }
      final finRetour = debutRetour.add(Duration(minutes: minRetour));
      final activiteRetour = ActiviteQuart(
        id: actRetourId,
        type: TypeActivite.deplacement,
        description: 'Trajet retour depuis $client',
        reference: ref,
        debut: debutRetour,
        fin: finRetour,
        dureeMinutesFixe: minRetour,
      );

      if (existingIdx >= 0) {
        quart.activites[existingIdx] = activiteRetour;
      } else {
        quart.activites.add(activiteRetour);
      }

      if (quart.clockOut != null && quart.clockOut!.isBefore(finRetour)) {
        quart.clockOut = finRetour;
      }
    }

    // Retirer les activités génériques par défaut une fois qu'au moins une activité réelle existe
    if (quart.activites.any((a) => a.reference != null && a.reference!.isNotEmpty)) {
      quart.activites.removeWhere((a) => a.id.startsWith('gen_') || a.id.startsWith('est_'));
    }

    if (sauvegarderApres) {
      await enregistrerQuart(quart);
    }
  }
}

// ============================================================================
// 📄 SERVICE PDF : RAPPORT DE PAIE (2 SEMAINES OU SEMAINE EN COURS)
// ============================================================================

class FeuilleDeTempsPdfService {
  static pw.Font? _cachedFontRegular;
  static pw.Font? _cachedFontBold;

  /// Génère le PDF officiel de la Période de Paie de 2 semaines
  static Future<Uint8List> genererBytesPdfPeriode(PeriodePaie periode) async {
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

    final primary = PdfColor.fromHex('#1E3A8A'); // Bleu marine
    final accentGreen = PdfColor.fromHex('#047857'); // Vert paie
    final orangeRepas = PdfColor.fromHex('#C2410C');
    final greyBg = PdfColor.fromHex('#F8FAFC');

    final strDebut =
        '${periode.debut.year}-${periode.debut.month.toString().padLeft(2, '0')}-${periode.debut.day.toString().padLeft(2, '0')}';
    final strFin =
        '${periode.finVendredi.year}-${periode.finVendredi.month.toString().padLeft(2, '0')}-${periode.finVendredi.day.toString().padLeft(2, '0')}';
    final strDateRemise =
        '${periode.dateRemiseEffective.year}-${periode.dateRemiseEffective.month.toString().padLeft(2, '0')}-${periode.dateRemiseEffective.day.toString().padLeft(2, '0')}';

    pdf.addPage(
      pw.Page(
        theme: theme,
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // ─── EN-TÊTE OFFICIEL ──────────────────────────────────
              pw.Container(
                padding: const pw.EdgeInsets.all(14),
                decoration: pw.BoxDecoration(
                  color: primary,
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'FEUILLE DE TEMPS & RELEVÉ DE PAIE',
                          style: pw.TextStyle(
                            color: PdfColors.white,
                            fontSize: 16,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 3),
                        pw.Text(
                          periode.estRemiseAnticipee
                              ? 'Période bi-hebdomadaire (2 semaines) • Remise anticipée le ${periode.nomJourDateRemise}'
                              : 'Période bi-hebdomadaire (2 semaines) • Remise le Vendredi',
                          style: const pw.TextStyle(
                            color: PdfColors.white,
                            fontSize: 9.5,
                          ),
                        ),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          'PÉRIODE : DU $strDebut AU $strFin',
                          style: pw.TextStyle(
                            color: PdfColors.white,
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 3),
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: pw.BoxDecoration(
                            color: periode.estRemiseAnticipee ? PdfColors.amber300 : PdfColors.white,
                            borderRadius: pw.BorderRadius.circular(3),
                          ),
                          child: pw.Text(
                            periode.estRemiseAnticipee
                                ? 'REMISE ANTICIPÉE : ${periode.nomJourDateRemise.toUpperCase()} $strDateRemise'
                                : 'Date de remise : Vendredi $strFin',
                            style: pw.TextStyle(
                              color: periode.estRemiseAnticipee ? PdfColors.amber900 : primary,
                              fontSize: 8.5,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 12),

              // ─── INFORMATIONS TECHNICIEN ───────────────────────────
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                        pw.Text(
                          'TECHNICIEN DE SERVICE :',
                          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                        ),
                        pw.Text(
                          periode.technicien,
                          style: pw.TextStyle(
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          'CYCLE DE PAIE :',
                          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                        ),
                        pw.Text(
                          'Aux deux semaines (10 jours ouvrables)',
                          style: pw.TextStyle(
                            fontSize: 11,
                            fontWeight: pw.FontWeight.bold,
                            color: primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 12),

              // ─── GRAND RÉCAPITULATIF DE LA PÉRIODE ─────────────────
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColors.green50,
                  borderRadius: pw.BorderRadius.circular(8),
                  border: pw.Border.all(color: PdfColors.green300, width: 1.5),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'TOTAL DES HEURES PAYÉES (2 SEMAINES)',
                          style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                            color: accentGreen,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.end,
                          children: [
                            pw.Text(
                              formatMinutes(periode.totalMinutesPeriode),
                              style: pw.TextStyle(
                                fontSize: 22,
                                fontWeight: pw.FontWeight.bold,
                                color: accentGreen,
                              ),
                            ),
                            pw.SizedBox(width: 8),
                            pw.Text(
                              '(${periode.totalHeuresDecimalesPeriode.toStringAsFixed(2)} h payées)',
                              style: pw.TextStyle(
                                fontSize: 12,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.grey700,
                              ),
                            ),
                          ],
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          'Semaine 1 : ${formatMinutes(periode.totalMinutesSemaine1)} (${(periode.totalMinutesSemaine1 / 60.0).toStringAsFixed(2)}h)  •  '
                          'Semaine 2 : ${formatMinutes(periode.totalMinutesSemaine2)} (${(periode.totalMinutesSemaine2 / 60.0).toStringAsFixed(2)}h)',
                          style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey800),
                        ),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        _buildLigneMini('Déplacements payés :', formatMinutes(periode.totalDeplacementMinutes), PdfColors.blue800),
                        _buildLigneMini('Attentes payées (conservées) :', formatMinutes(periode.totalAttenteMinutes), PdfColors.amber900),
                        _buildLigneMini('Repas déduits (non payés) :', '-${formatMinutes(periode.totalRepasMinutes)}', orangeRepas, isBold: true),
                      ],
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 14),

              // ─── TABLEAU DÉTAILLÉ SEMAINE 1 ─────────────────────────
              _buildSectionTableauSemaine('SEMAINE 1', periode.quartsSemaine1, primary),

              pw.SizedBox(height: 12),

              // ─── TABLEAU DÉTAILLÉ SEMAINE 2 ─────────────────────────
              _buildSectionTableauSemaine(
                'SEMAINE 2 (AVEC ESTIMATION DU VENDREDI DE REMISE)',
                periode.quartsSemaine2,
                primary,
                estSemaine2: true,
              ),

              pw.SizedBox(height: 10),

              // Note explicative de la remise de paie
              pw.Container(
                padding: const pw.EdgeInsets.all(6),
                decoration: pw.BoxDecoration(
                  color: periode.estRemiseAnticipee ? PdfColors.amber100 : PdfColors.amber50,
                  borderRadius: pw.BorderRadius.circular(4),
                  border: pw.Border.all(
                    color: periode.estRemiseAnticipee ? PdfColors.amber400 : PdfColors.amber300,
                  ),
                ),
                child: pw.Row(
                  children: [
                    pw.Text(periode.estRemiseAnticipee ? '• ' : '• ', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: primary)),
                    pw.Expanded(
                      child: pw.Text(
                        periode.estRemiseAnticipee
                            ? 'Note de paie : Feuille de temps remise par anticipation le ${periode.nomJourDateRemise} $strDateRemise. '
                              'Les journées restantes ont été estimées et déclarées par le technicien pour permettre le traitement normal de la paie sans interruption. '
                              'Règle Rayco Wylie : déplacements inclus et payés, attentes conservées et payées, repas déduits.'
                            : 'Note de paie : La feuille de temps étant remise le vendredi avant la fermeture du bureau, '
                              'les heures estimées sont déclarées pour le traitement normal de la paie. '
                              'Les temps de déplacement sont inclus et payés, les attentes sont conservées et payées, les repas sont déduits.',
                        style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey800),
                      ),
                    ),
                  ],
                ),
              ),

              pw.Spacer(),

              // ─── SIGNATURES ────────────────────────────────────────
              pw.Divider(color: PdfColors.grey400),
              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'SIGNATURE DU TECHNICIEN',
                        style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Déclaré et remis le ${periode.nomJourDateRemise} $strDateRemise${periode.estRemiseAnticipee ? ' (Remise anticipée)' : ''}',
                        style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600),
                      ),
                      pw.SizedBox(height: 20),
                      pw.Container(width: 170, decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 1)))),
                      pw.SizedBox(height: 2),
                      pw.Text(periode.technicien, style: const pw.TextStyle(fontSize: 8)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'APPROBATION SERVICE DE LA PAIE',
                        style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Conforme pour versement bi-hebdomadaire',
                        style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600),
                      ),
                      pw.SizedBox(height: 20),
                      pw.Container(width: 170, decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 1)))),
                      pw.SizedBox(height: 2),
                      pw.Text('Signature autorisée', style: const pw.TextStyle(fontSize: 8)),
                    ],
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildSectionTableauSemaine(
    String titre,
    List<QuartDeTravail> quarts,
    PdfColor primary, {
    bool estSemaine2 = false,
  }) {
    int totalSemaine = quarts.fold(0, (sum, q) => sum + q.tempsPayeMinutes);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              titre,
              style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: primary),
            ),
            pw.Text(
              'Sous-total : ${formatMinutes(totalSemaine)} (${(totalSemaine / 60.0).toStringAsFixed(2)} h)',
              style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: PdfColors.green800),
            ),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey300),
          columnWidths: const {
            0: pw.FixedColumnWidth(80),  // Jour / Date
            1: pw.FixedColumnWidth(85),  // Horaires
            2: pw.FixedColumnWidth(70),  // Déplacement
            3: pw.FixedColumnWidth(65),  // Attente
            4: pw.FixedColumnWidth(65),  // Repas
            5: pw.FixedColumnWidth(70),  // Payé
            6: pw.FlexColumnWidth(),     // Statut / Note
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: [
                _th('JOUR / DATE'),
                _th('CLOCK IN/OUT'),
                _th('DÉPLAC.'),
                _th('ATTENTE'),
                _th('REPAS'),
                _th('PAYÉ NET'),
                _th('STATUT / NOTES'),
              ],
            ),
            ...quarts.map((q) {
              final dateStr =
                  '${q.date.month.toString().padLeft(2, '0')}-${q.date.day.toString().padLeft(2, '0')}';
              final labelJour = '${q.nomJourSemaine} $dateStr';
              final horaires =
                  '${formatHeureDateTime(q.clockIn)} - ${q.clockOut != null ? formatHeureDateTime(q.clockOut!) : "--:--"}';
              final estEstime = q.estEstime;

              return pw.TableRow(
                decoration: estEstime
                    ? const pw.BoxDecoration(color: PdfColors.amber50)
                    : null,
                children: [
                  _td(labelJour, isBold: true),
                  _td(horaires),
                  _td(formatMinutes(q.totalDeplacementMinutes)),
                  _td(formatMinutes(q.totalAttenteMinutes)),
                  _td('-${formatMinutes(q.totalRepasMinutes)}', color: PdfColors.deepOrange800),
                  _td(
                    '${q.tempsPayeFormate} (${q.tempsPayeDecimal}h)',
                    color: PdfColors.green900,
                    isBold: true,
                  ),
                  _td(
                    estEstime
                        ? (q.notes.isNotEmpty ? '[ESTIMÉ] : ${q.notes}' : '[ESTIMÉ] (REMISE ANTICIPÉE)')
                        : (q.notes.isNotEmpty ? q.notes : 'Régulier validé'),
                    color: estEstime ? PdfColors.amber900 : PdfColors.grey700,
                    isBold: estEstime,
                  ),
                ],
              );
            }),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildLigneMini(String label, String valeur, PdfColor couleur, {bool isBold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
          pw.SizedBox(width: 6),
          pw.Text(
            valeur,
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: couleur,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _th(String texte) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(4.5),
      child: pw.Text(
        texte,
        style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  static pw.Widget _td(String texte, {PdfColor? color, bool isBold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(4.5),
      child: pw.Text(
        texte,
        style: pw.TextStyle(
          fontSize: 7.5,
          color: color ?? PdfColors.black,
          fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  /// Dialogue de choix d'export à la demande avec les 3 options
  static Future<void> afficherDialogueExportPeriode(
    BuildContext context,
    PeriodePaie periode,
  ) async {
    final strFin =
        '${periode.finVendredi.year}-${periode.finVendredi.month.toString().padLeft(2, '0')}-${periode.finVendredi.day.toString().padLeft(2, '0')}';

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
                    backgroundColor: Colors.green.shade50,
                    child: const Icon(Icons.receipt_long, color: Colors.green),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Exporter le Rapport de Paie (2 Semaines)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          periode.estRemiseAnticipee
                              ? 'Remise anticipée : ${periode.nomJourDateRemise} ${periode.dateRemiseEffective.day}/${periode.dateRemiseEffective.month} • Total : ${formatMinutes(periode.totalMinutesPeriode)} (${periode.totalHeuresDecimalesPeriode} h)'
                              : 'Remise du Vendredi $strFin • Total : ${formatMinutes(periode.totalMinutesPeriode)} (${periode.totalHeuresDecimalesPeriode} h)',
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),

              // ─── OPTION 1 : ENREGISTRER SOUS... (EXPLORATEUR)
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
                  'Ouvre l\'explorateur pour choisir le dossier et le nom du fichier.',
                  style: TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: () {
                  Navigator.pop(ctx);
                  enregistrerPdfEmplacementChoisi(context, periode);
                },
              ),

              // ─── OPTION 2 : ENVOYER PAR COURRIEL AVEC OUTLOOK
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                leading: CircleAvatar(
                  backgroundColor: Colors.teal.shade50,
                  child: const Icon(Icons.mail_outline, color: Colors.teal),
                ),
                title: const Text(
                  'Envoyer par courriel avec Outlook',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                subtitle: const Text(
                  'Ouvre Outlook avec le PDF joint et le message pré-rempli pour la paie.',
                  style: TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: () {
                  Navigator.pop(ctx);
                  envoyerParOutlook(context, periode);
                },
              ),

              // ─── OPTION 3 : APERÇU ET IMPRESSION
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                leading: CircleAvatar(
                  backgroundColor: Colors.purple.shade50,
                  child: const Icon(Icons.print_outlined, color: Colors.purple),
                ),
                title: const Text(
                  'Aperçu & Imprimer',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                subtitle: const Text(
                  'Visualiser la feuille et imprimer directement en format papier/PDF.',
                  style: TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: () {
                  Navigator.pop(ctx);
                  imprimerApercuPdf(context, periode);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Option 1 : FilePicker pour choisir l'emplacement + explorer.exe /select
  static Future<void> enregistrerPdfEmplacementChoisi(
    BuildContext context,
    PeriodePaie periode,
  ) async {
    try {
      final strFin =
          '${periode.finVendredi.year}-${periode.finVendredi.month.toString().padLeft(2, '0')}-${periode.finVendredi.day.toString().padLeft(2, '0')}';
      final cleanTech = periode.technicien.replaceAll(RegExp(r'[\\/:*?"<>| ]'), '_');
      final nomFichierSuggere =
          'FeuilleDePaie_2Semaines_${cleanTech}_$strFin${periode.estRemiseAnticipee ? "_RemiseAnticipee" : ""}.pdf';

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⏳ Génération du rapport de paie (2 semaines)...'), duration: Duration(seconds: 1)),
        );
      }

      final pdfBytes = await genererBytesPdfPeriode(periode);

      final Uri? uriChoisi = await FilePicker.saveFile(
        dialogTitle: 'Choisir l\'emplacement où enregistrer la feuille de paie',
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
            content: Text('✅ Feuille de paie enregistrée : $cheminFinal'),
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
      debugPrint('Erreur sauvegarde PDF paie: $e');
    }
  }

  /// Option 2 : Lancer Outlook avec la pièce jointe
  static Future<void> envoyerParOutlook(
    BuildContext context,
    PeriodePaie periode, {
    String courrielPaie = 'paie@raycowylie.com',
  }) async {
    try {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⏳ Préparation du PDF et d\'Outlook...'), duration: Duration(seconds: 1)),
        );
      }

      final pdfBytes = await genererBytesPdfPeriode(periode);
      final strFin =
          '${periode.finVendredi.year}-${periode.finVendredi.month.toString().padLeft(2, '0')}-${periode.finVendredi.day.toString().padLeft(2, '0')}';
      final strDebut =
          '${periode.debut.year}-${periode.debut.month.toString().padLeft(2, '0')}-${periode.debut.day.toString().padLeft(2, '0')}';
      final strRemise =
          '${periode.dateRemiseEffective.year}-${periode.dateRemiseEffective.month.toString().padLeft(2, '0')}-${periode.dateRemiseEffective.day.toString().padLeft(2, '0')}';
      final cleanTech = periode.technicien.replaceAll(RegExp(r'[\\/:*?"<>| ]'), '_');

      final subject = periode.estRemiseAnticipee
          ? 'Feuille de temps (Paie 2 semaines) - ${periode.technicien} - Remise anticipée du ${periode.nomJourDateRemise} $strRemise'
          : 'Feuille de temps (Paie 2 semaines) - ${periode.technicien} - Remise du Vendredi $strFin';

      final body = '''Bonjour au service de la paie,

Veuillez trouver ci-joint ma feuille de temps pour la période de paie de 2 semaines (du $strDebut au $strFin), ${periode.estRemiseAnticipee ? "remise par anticipation ce ${periode.nomJourDateRemise} $strRemise" : "remise ce vendredi"}.

RÉCAPITULATIF DE LA PÉRIODE (2 SEMAINES) :
• GRAND TOTAL HEURES PAYÉES : ${formatMinutes(periode.totalMinutesPeriode)} (${periode.totalHeuresDecimalesPeriode.toStringAsFixed(2)} h)
  - Semaine 1 : ${formatMinutes(periode.totalMinutesSemaine1)} (${(periode.totalMinutesSemaine1 / 60.0).toStringAsFixed(2)} h)
  - Semaine 2 : ${formatMinutes(periode.totalMinutesSemaine2)} (${(periode.totalMinutesSemaine2 / 60.0).toStringAsFixed(2)} h)
• Total déplacements payés (inclus) : ${formatMinutes(periode.totalDeplacementMinutes)}
• Total attente sur site (conservée et payée) : ${formatMinutes(periode.totalAttenteMinutes)}
• Pauses repas (déduites du temps payé) : -${formatMinutes(periode.totalRepasMinutes)}

${periode.estRemiseAnticipee ? "⚡ Remise anticipée : Les journées restantes de la période ont été estimées et déclarées pour permettre le traitement régulier de la paie." : "Note : Les heures de ce dernier vendredi ont été estimées et déclarées pour la remise hebdomadaire de paie."}

Le relevé officiel complet en PDF est attaché à ce courriel.

Cordialement,
${periode.technicien}
Technicien de service''';

      if (!kIsWeb && Platform.isWindows) {
        final userProfile =
            Platform.environment['USERPROFILE'] ?? 'C:\\Users\\Default';
        final targetDir = Directory('$userProfile\\Documents\\AppTechnicien\\PDF');
        if (!await targetDir.exists()) {
          await targetDir.create(recursive: true);
        }

        final pdfPath =
            '${targetDir.path}\\FeuilleDePaie_2Semaines_${cleanTech}_$strFin.pdf';
        final pdfFile = File(pdfPath);
        await pdfFile.writeAsBytes(pdfBytes);

        final outlookPath = RapportPdfService.trouverOutlookPath();
        if (outlookPath != null) {
          final uriMailto = Uri(
            scheme: 'mailto',
            path: courrielPaie,
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
                content: Text('📧 Outlook ouvert avec la feuille de paie jointe ($courrielPaie) !'),
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
        path: courrielPaie,
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
        filename: 'FeuilleDePaie_2Semaines_${cleanTech}_$strFin.pdf',
      );
    } catch (e) {
      debugPrint('Erreur envoi Outlook: $e');
    }
  }

  /// Enregistre automatiquement la feuille de paie sur disque dans Documents\RaycoWylie_Documents\FeuillesDeTemps\
  static Future<String?> sauvegarderPdfSurDisque(PeriodePaie periode, Uint8List pdfBytes) async {
    if (kIsWeb) return null;
    try {
      final strFin =
          '${periode.finVendredi.year}-${periode.finVendredi.month.toString().padLeft(2, '0')}-${periode.finVendredi.day.toString().padLeft(2, '0')}';
      final cleanTech = periode.technicien.replaceAll(RegExp(r'[\\/:*?"<>| ]'), '_');
      final fileName = 'FeuilleDePaie_2Semaines_${cleanTech}_$strFin${periode.estRemiseAnticipee ? "_RemiseAnticipee" : ""}.pdf';

      if (!kIsWeb && Platform.isWindows) {
        final userProfile = Platform.environment['USERPROFILE'] ?? 'C:\\Users\\Default';
        final targetDir = Directory('$userProfile\\Documents\\RaycoWylie_Documents\\FeuillesDeTemps');
        if (!await targetDir.exists()) {
          await targetDir.create(recursive: true);
        }
        final f = File('${targetDir.path}\\$fileName');
        await f.writeAsBytes(pdfBytes);
        return f.path;
      } else {
        final temp = Directory('${Directory.systemTemp.path}/FeuillesDeTemps');
        if (!await temp.exists()) await temp.create(recursive: true);
        final f = File('${temp.path}/$fileName');
        await f.writeAsBytes(pdfBytes);
        return f.path;
      }
    } catch (e) {
      debugPrint('Erreur sauvegarde disque feuille paie: $e');
      return null;
    }
  }

  /// Option 3 : Visualiser et imprimer la feuille de paie via le visualiseur PDF Windows natif ou Printing.layoutPdf
  static Future<void> imprimerApercuPdf(
    BuildContext context,
    PeriodePaie periode,
  ) async {
    try {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⏳ Préparation de la feuille de paie pour visualisation...'), duration: Duration(seconds: 1)),
        );
      }
      final pdfBytes = await genererBytesPdfPeriode(periode);

      if (!kIsWeb && Platform.isWindows) {
        // Sous Windows : Sauvegarder sur disque et ouvrir immédiatement dans le lecteur PDF par défaut (Acrobat, Edge, etc.)
        final path = await sauvegarderPdfSurDisque(periode, pdfBytes);
        if (path != null) {
          await RapportPdfService.ouvrirFichier(path);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('📄 Feuille de paie ouverte dans votre lecteur Windows :\n$path'),
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

      final strFin =
          '${periode.finVendredi.year}-${periode.finVendredi.month.toString().padLeft(2, '0')}-${periode.finVendredi.day.toString().padLeft(2, '0')}';
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdfBytes,
        name: 'FeuilleDePaie_2Semaines_$strFin.pdf',
      );
    } catch (e) {
      debugPrint('Erreur aperçu PDF paie: $e');
    }
  }
}

// ============================================================================
// 🖥️ ÉCRAN COMPLET DE LA FEUILLE DE TEMPS (AVEC VUE 2 SEMAINES & ESTIMATION)
// ============================================================================

class FeuilleDeTempsScreen extends StatefulWidget {
  final String? technicienInitial;
  const FeuilleDeTempsScreen({super.key, this.technicienInitial});

  @override
  State<FeuilleDeTempsScreen> createState() => _FeuilleDeTempsScreenState();
}

class _FeuilleDeTempsScreenState extends State<FeuilleDeTempsScreen>
    with SingleTickerProviderStateMixin {
  final FeuilleDeTempsRepository _repo = FeuilleDeTempsRepository.instance;
  final TechnicienService _techService = TechnicienService.instance;
  late TabController _tabController;
  PeriodePaie? _periode;
  bool _isLoading = true;

  List<Technicien> _techniciens = [
    Technicien(
      id: '1',
      nom: 'Pierre-Olivier Patry',
      numeroCamion: 'Camion #102',
      courriel: 'popatry@raycowylie.com',
      telephone: '418-806-0391',
    ),
    Technicien(
      id: '2',
      nom: 'David Hestin',
      numeroCamion: 'Camion #101',
      courriel: 'dhestin@raycowylie.com',
      telephone: '418-555-0101',
    ),
    Technicien(
      id: '3',
      nom: 'Jean-François Allie',
      numeroCamion: 'Camion #103',
      courriel: 'jfallie@raycowylie.com',
      telephone: '418-555-0103',
    ),
  ];
  Technicien? _technicienSelectionne;
  bool _estDeverrouille = false;
  Timer? _liveTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    if (widget.technicienInitial != null) {
      _technicienSelectionne = _techniciens.firstWhere(
        (t) => t.nom.toLowerCase() == widget.technicienInitial!.toLowerCase(),
        orElse: () => _techniciens.first,
      );
    } else {
      _technicienSelectionne = _techniciens.first;
    }
    _charger();
    _initTechniciens();

    // Défilement du temps en direct chaque seconde
    _liveTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && (_quartAujourdhui?.estActif == true || _repo.quarts.any((q) => q.estActif || q.activites.any((a) => a.fin == null)))) {
        setState(() {});
      }
    });
  }

  Future<void> _initTechniciens() async {
    try {
      final techs = await _techService.getTechniciens();
      if (techs.isNotEmpty && mounted) {
        setState(() {
          _techniciens = techs;
          if (_technicienSelectionne != null) {
            _technicienSelectionne = _techniciens.firstWhere(
              (t) => t.nom.toLowerCase() == _technicienSelectionne!.nom.toLowerCase(),
              orElse: () => _techniciens.first,
            );
          }
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    setState(() => _isLoading = true);
    final nomTech = _technicienSelectionne?.nom ?? 'Pierre-Olivier Patry';
    final p = await _repo.getPeriodePaieActuelle(technicien: nomTech);
    if (mounted) {
      setState(() {
        _periode = p;
        _isLoading = false;
      });
    }
  }


  QuartDeTravail? get _quartAujourdhui {
    final tech = _technicienSelectionne?.nom;
    final actif = _repo.getQuartActif(technicien: tech);
    if (actif != null) return actif;
    return _repo.getQuartPourJour(DateTime.now(), technicien: tech);
  }

  void _changerTechnicien(Technicien tech) {
    setState(() {
      _technicienSelectionne = tech;
      _estDeverrouille = false; // Verrouiller immédiatement anti-tampering
    });
    _charger();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🔒 Feuille de temps de ${tech.nom} sélectionnée (Protégée par NIP).'),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.blueGrey.shade800,
      ),
    );
  }

  Future<bool> _demanderNipSecurise({String action = 'modifier cette feuille de temps'}) async {
    if (_estDeverrouille) return true;

    final String nomTech = _technicienSelectionne?.nom ?? 'Pierre-Olivier Patry';
    final String camion = _technicienSelectionne?.numeroCamion ?? 'Camion #102';

    final ok = await NipSecuriteService.instance.afficherDialogueVerificationNip(
      context,
      nomTechnicien: nomTech,
      numeroCamion: camion,
      actionDescription: action,
    );

    if (ok && mounted) {
      setState(() => _estDeverrouille = true);
    }
    return ok;
  }

  Future<void> _changerNipModal() async {
    final String nomTech = _technicienSelectionne?.nom ?? 'Pierre-Olivier Patry';
    final String camion = _technicienSelectionne?.numeroCamion ?? 'Camion #102';

    await NipSecuriteService.instance.afficherDialogueChangementNip(
      context,
      nomTechnicien: nomTech,
      numeroCamion: camion,
    );
  }

  /// Dialogue pour modifier n'importe quelle journée (erreur d'heures, oubli de punch, pause repas, etc.)
  Future<void> _dialogueModifierJournee(QuartDeTravail quart) async {
    if (!await _demanderNipSecurise(action: 'modifier les heures du ${quart.nomJourSemaine} ${quart.date.day}/${quart.date.month}')) return;
    if (!mounted) return;
    DateTime clockIn = quart.clockIn;
    int repasMinutes = quart.totalRepasMinutes;
    int trajetMinutes = quart.totalDeplacementMinutes;
    int attenteMinutes = quart.totalAttenteMinutes;
    int minutesPayees = quart.tempsPayeMinutes;
    DateTime clockOut = quart.clockOut ??
        clockIn.add(Duration(minutes: minutesPayees + repasMinutes));
    bool estEstime = quart.estEstime;
    int heuresChoisie = minutesPayees ~/ 60;
    int minutesChoisie = minutesPayees % 60;
    final noteCtrl = TextEditingController(text: quart.notes);

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          final totalNetMinutes = (heuresChoisie * 60) + minutesChoisie;
          final totalDecimal = (totalNetMinutes / 60.0).toStringAsFixed(2);
          final brutMinutes = totalNetMinutes + repasMinutes;

          void updatePaidTime(int h, int m, {String? presetNote}) {
            setDlgState(() {
              heuresChoisie = h.clamp(0, 24);
              minutesChoisie = m.clamp(0, 59);
              minutesPayees = (heuresChoisie * 60) + minutesChoisie;
              clockOut = clockIn.add(Duration(minutes: minutesPayees + repasMinutes));
              if (presetNote != null &&
                  (noteCtrl.text.isEmpty ||
                      noteCtrl.text == 'Quart standard régulier')) {
                noteCtrl.text = presetNote;
              }
            });
          }

          return AlertDialog(
            titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: Row(
              children: [
                CircleAvatar(
                  backgroundColor:
                      estEstime ? Colors.amber.shade100 : Colors.indigo.shade100,
                  child: Icon(
                    estEstime ? Icons.flash_on : Icons.edit_calendar_rounded,
                    color: estEstime ? Colors.amber.shade900 : Colors.indigo.shade900,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Modifier - ${quart.nomJourSemaine} ${quart.date.day}/${quart.date.month}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Correction d\'erreur, horaires ou estimation d\'heures',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(ctx, false),
                ),
              ],
            ),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Carte récapitulative temps payé net
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: estEstime ? Colors.amber.shade50 : Colors.green.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: estEstime ? Colors.amber.shade400 : Colors.green.shade300,
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                estEstime ? '⚡ TEMPS PAYÉ ESTIMÉ' : '✅ TEMPS PAYÉ NET',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: estEstime
                                      ? Colors.amber.shade900
                                      : Colors.green.shade900,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$heuresChoisie h ${minutesChoisie.toString().padLeft(2, '0')}m  ($totalDecimal h payées)',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: estEstime
                                      ? Colors.amber.shade900
                                      : Colors.green.shade900,
                                ),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('Brut : ${formatMinutes(brutMinutes)}',
                                  style: const TextStyle(fontSize: 10, color: Colors.black54)),
                              Text('Repas : -${formatMinutes(repasMinutes)}',
                                  style: const TextStyle(fontSize: 10, color: Colors.deepOrange)),
                              Text('Trajet : ${formatMinutes(trajetMinutes)}',
                                  style: const TextStyle(fontSize: 10, color: Colors.blueAccent)),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Raccourcis rapides
                    const Text('Raccourcis rapides :',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ActionChip(
                          avatar: const Icon(Icons.check, size: 14),
                          label: const Text('8h00 Régulier', style: TextStyle(fontSize: 11)),
                          onPressed: () =>
                              updatePaidTime(8, 0, presetNote: 'Quart standard régulier'),
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.access_time, size: 14),
                          label: const Text('8h30 Chantier', style: TextStyle(fontSize: 11)),
                          onPressed: () =>
                              updatePaidTime(8, 30, presetNote: 'Chantier prolongé'),
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.access_time, size: 14),
                          label: const Text('9h00 Chantier', style: TextStyle(fontSize: 11)),
                          onPressed: () =>
                              updatePaidTime(9, 0, presetNote: 'Chantier prolongé'),
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.access_time, size: 14),
                          label: const Text('7h30', style: TextStyle(fontSize: 11)),
                          onPressed: () => updatePaidTime(7, 30),
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.star, size: 14, color: Colors.amber),
                          label: const Text('8h00 Férié payé', style: TextStyle(fontSize: 11)),
                          onPressed: () =>
                              updatePaidTime(8, 0, presetNote: 'Congé férié payé (8h00)'),
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.local_hospital, size: 14, color: Colors.red),
                          label: const Text('8h00 Maladie / Mobile', style: TextStyle(fontSize: 11)),
                          onPressed: () => updatePaidTime(8, 0,
                              presetNote: 'Journée maladie payée (8h00)'),
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.block, size: 14, color: Colors.grey),
                          label: const Text('0h Non payé', style: TextStyle(fontSize: 11)),
                          onPressed: () => updatePaidTime(0, 0,
                              presetNote: 'Congé sans solde / Non travaillé'),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    // Steppers Heures et Minutes
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Heures : ',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.remove_circle_outline, size: 20),
                                      onPressed: heuresChoisie > 0
                                          ? () => updatePaidTime(heuresChoisie - 1, minutesChoisie)
                                          : null,
                                    ),
                                    Text('$heuresChoisie h',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                    IconButton(
                                      icon: const Icon(Icons.add_circle_outline, size: 20),
                                      onPressed: heuresChoisie < 20
                                          ? () => updatePaidTime(heuresChoisie + 1, minutesChoisie)
                                          : null,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Minutes : ',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.remove_circle_outline, size: 20),
                                      onPressed: minutesChoisie >= 15
                                          ? () => updatePaidTime(heuresChoisie, minutesChoisie - 15)
                                          : (heuresChoisie > 0
                                              ? () => updatePaidTime(heuresChoisie - 1, 45)
                                              : null),
                                    ),
                                    Text('${minutesChoisie.toString().padLeft(2, '0')} m',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                    IconButton(
                                      icon: const Icon(Icons.add_circle_outline, size: 20),
                                      onPressed: minutesChoisie < 45
                                          ? () => updatePaidTime(heuresChoisie, minutesChoisie + 15)
                                          : () => updatePaidTime(heuresChoisie + 1, 0),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    // Horaires Début (Clock In) et Fin (Clock Out)
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Horaires du quart :',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  icon: const Icon(Icons.login, size: 16, color: Colors.green),
                                  label: Text('In: ${formatHeureDateTime(clockIn)}'),
                                  onPressed: () async {
                                    final pick = await showTimePicker(
                                      context: ctx,
                                      initialTime: TimeOfDay.fromDateTime(clockIn),
                                    );
                                    if (pick != null) {
                                      setDlgState(() {
                                        clockIn = DateTime(quart.date.year, quart.date.month,
                                            quart.date.day, pick.hour, pick.minute);
                                        clockOut = clockIn.add(Duration(
                                            minutes: (heuresChoisie * 60) +
                                                minutesChoisie +
                                                repasMinutes));
                                      });
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  icon: const Icon(Icons.logout, size: 16, color: Colors.red),
                                  label: Text('Out: ${formatHeureDateTime(clockOut)}'),
                                  onPressed: () async {
                                    final pick = await showTimePicker(
                                      context: ctx,
                                      initialTime: TimeOfDay.fromDateTime(clockOut),
                                    );
                                    if (pick != null) {
                                      setDlgState(() {
                                        clockOut = DateTime(quart.date.year, quart.date.month,
                                            quart.date.day, pick.hour, pick.minute);
                                        final diff = clockOut.difference(clockIn).inMinutes;
                                        final net = diff - repasMinutes;
                                        if (net >= 0) {
                                          heuresChoisie = net ~/ 60;
                                          minutesChoisie = net % 60;
                                          minutesPayees = net;
                                        }
                                      });
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Détails Déductions / Paie (Repas, Déplacement)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Repas
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Pause Repas (Déduite) :',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              DropdownButtonFormField<int>(
                                initialValue:
                                    [0, 30, 45, 60].contains(repasMinutes) ? repasMinutes : 45,
                                isDense: true,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    contentPadding:
                                        EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                                items: const [
                                  DropdownMenuItem(value: 0, child: Text('0 min (Aucune)', overflow: TextOverflow.ellipsis)),
                                  DropdownMenuItem(value: 30, child: Text('30 min', overflow: TextOverflow.ellipsis)),
                                  DropdownMenuItem(value: 45, child: Text('45 min (Std)', overflow: TextOverflow.ellipsis)),
                                  DropdownMenuItem(value: 60, child: Text('60 min (1h)', overflow: TextOverflow.ellipsis)),
                                ],
                                onChanged: (v) {
                                  if (v != null) {
                                    setDlgState(() {
                                      repasMinutes = v;
                                      clockOut = clockIn.add(Duration(
                                          minutes: (heuresChoisie * 60) +
                                              minutesChoisie +
                                              repasMinutes));
                                    });
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Déplacement
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Déplacement (Payé) :',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              DropdownButtonFormField<int>(
                                initialValue: [0, 30, 45, 60, 90, 120].contains(trajetMinutes)
                                    ? trajetMinutes
                                    : 60,
                                isDense: true,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    contentPadding:
                                        EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                                items: const [
                                  DropdownMenuItem(value: 0, child: Text('0 min')),
                                  DropdownMenuItem(value: 30, child: Text('30 min')),
                                  DropdownMenuItem(value: 45, child: Text('45 min')),
                                  DropdownMenuItem(value: 60, child: Text('60 min')),
                                  DropdownMenuItem(value: 90, child: Text('1h 30m')),
                                  DropdownMenuItem(value: 120, child: Text('2h 00m')),
                                ],
                                onChanged: (v) {
                                  if (v != null) setDlgState(() => trajetMinutes = v);
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    // Switch Marquer comme estimé (Remise anticipée)
                    Container(
                      decoration: BoxDecoration(
                        color: estEstime ? Colors.amber.shade50 : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: estEstime ? Colors.amber.shade400 : Colors.grey.shade300),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: SwitchListTile(
                          title: const Text(
                            'Marquer comme journée estimée (Remise anticipée)',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          subtitle: const Text(
                            'Cochez si cette journée est déclarée à l\'avance car la feuille est remise plus tôt.',
                            style: TextStyle(fontSize: 10),
                          ),
                          value: estEstime,
                          activeThumbImage: null,
                          activeTrackColor: Colors.amber.shade800,
                          onChanged: (val) {
                            setDlgState(() {
                              estEstime = val;
                              if (val && noteCtrl.text.isEmpty) {
                                noteCtrl.text = 'Estimé pour remise anticipée de paie';
                              }
                            });
                          },
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Champ Note / Justification
                    TextField(
                      controller: noteCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Note / Justification (affichée sur la paie & PDF)',
                        hintText: 'Ex: Correction d\'erreur, Oubli de punch, Congé férié, Chantier...',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
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
                icon: const Icon(Icons.check),
                label: const Text('Enregistrer les modifications'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade800,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onPressed: () => Navigator.pop(ctx, true),
              ),
            ],
          );
        },
      ),
    );

    if (result == true) {
      final totalMin = (heuresChoisie * 60) + minutesChoisie;
      quart.clockIn = clockIn;
      quart.clockOut = clockOut;
      quart.punches.clear();
      quart.punches.add(IntervallePunch(entree: clockIn, sortie: clockOut));
      quart.minutesEstimeesFixe = totalMin;
      quart.estEstime = estEstime;
      quart.notes = noteCtrl.text.trim();

      // Recréer ou synchroniser les activités
      quart.activites.clear();
      if (trajetMinutes > 0) {
        quart.activites.add(
          ActiviteQuart(
            id: 'trajet_${quart.id}_${DateTime.now().millisecondsSinceEpoch}',
            type: TypeActivite.deplacement,
            description: 'Temps de déplacement / trajet',
            debut: clockIn,
            fin: clockIn.add(Duration(minutes: trajetMinutes)),
            dureeMinutesFixe: trajetMinutes,
          ),
        );
      }
      final travailMin = totalMin - trajetMinutes - attenteMinutes;
      if (travailMin > 0) {
        quart.activites.add(
          ActiviteQuart(
            id: 'travail_${quart.id}_${DateTime.now().millisecondsSinceEpoch}',
            type: TypeActivite.travail,
            description: quart.notes.isNotEmpty ? quart.notes : 'Travail sur site / interventions',
            debut: clockIn.add(Duration(minutes: trajetMinutes)),
            fin: clockIn.add(Duration(minutes: trajetMinutes + travailMin)),
            dureeMinutesFixe: travailMin,
          ),
        );
      }
      if (attenteMinutes > 0) {
        quart.activites.add(
          ActiviteQuart(
            id: 'attente_${quart.id}_${DateTime.now().millisecondsSinceEpoch}',
            type: TypeActivite.attente,
            description: 'Temps d\'attente sur site',
            debut: clockIn.add(Duration(minutes: trajetMinutes + (travailMin > 0 ? travailMin : 0))),
            fin: clockIn.add(Duration(minutes: trajetMinutes + (travailMin > 0 ? travailMin : 0) + attenteMinutes)),
            dureeMinutesFixe: attenteMinutes,
          ),
        );
      }
      if (repasMinutes > 0) {
        quart.activites.add(
          ActiviteQuart(
            id: 'repas_${quart.id}_${DateTime.now().millisecondsSinceEpoch}',
            type: TypeActivite.repas,
            description: 'Pause repas / dîner',
            debut: DateTime(quart.date.year, quart.date.month, quart.date.day, 12, 0),
            fin: DateTime(quart.date.year, quart.date.month, quart.date.day, 12, repasMinutes),
            dureeMinutesFixe: repasMinutes,
          ),
        );
      }

      await _repo.enregistrerQuart(quart);
      await _charger();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '✅ ${quart.nomJourSemaine} ${quart.date.day}/${quart.date.month} : Heures mises à jour (${formatMinutes(totalMin)}) !'),
            backgroundColor: Colors.green.shade800,
          ),
        );
      }
    }
  }

  /// Dialogue pour choisir une remise anticipée (ex: jeudi, mercredi, départ en congé, etc.)
  Future<void> _dialogueRemiseAnticipee() async {
    final periode = _periode;
    if (periode == null) return;
    if (!await _demanderNipSecurise(action: 'déclarer ou modifier une remise anticipée de paie')) return;
    if (!mounted) return;

    final qVen = periode.quartsSemaine2[4];
    final qJeu = periode.quartsSemaine2[3];
    final qMer = periode.quartsSemaine2[2];
    final qMar = periode.quartsSemaine2[1];

    DateTime dateChoisie = periode.dateRemiseEffective;
    int heuresEstimees = 8;
    int minutesEstimees = 0;
    final noteCtrl = TextEditingController(
      text: periode.estRemiseAnticipee
          ? 'Remise anticipée de paie le ${periode.nomJourDateRemise}'
          : 'Remise anticipée (veille de férié/congé)',
    );

    final bool? valider = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          final isJeudi = dateChoisie.year == qJeu.date.year &&
              dateChoisie.month == qJeu.date.month &&
              dateChoisie.day == qJeu.date.day;
          final isMercredi = dateChoisie.year == qMer.date.year &&
              dateChoisie.month == qMer.date.month &&
              dateChoisie.day == qMer.date.day;
          final isMardi = dateChoisie.year == qMar.date.year &&
              dateChoisie.month == qMar.date.month &&
              dateChoisie.day == qMar.date.day;
          final isVendrediNormal = dateChoisie.year == qVen.date.year &&
              dateChoisie.month == qVen.date.month &&
              dateChoisie.day == qVen.date.day;

          return AlertDialog(
            title: const Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.amber,
                  child: Icon(Icons.send_time_extension_rounded, color: Colors.white),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Remise Anticipée de la Paie',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      Text('Remettre la feuille plus tôt que le vendredi',
                          style: TextStyle(fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.shade300),
                      ),
                      child: const Text(
                        'Vous devez remettre votre feuille de temps avant le vendredi habituel ? '
                        '(Ex: vendredi férié payé, départ en congé, ou impératif de paie).\n'
                        'Sélectionnez le jour de remise anticipée. Les jours restants seront automatiquement '
                        'estimés et marqués sur le rapport officiel.',
                        style: TextStyle(fontSize: 12, color: Colors.black87),
                      ),
                    ),
                    const SizedBox(height: 16),

                    const Text('Choisir le jour de remise :',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),

                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: Text('Jeudi ${qJeu.date.day}/${qJeu.date.month}'),
                          selected: isJeudi,
                          selectedColor: Colors.amber.shade300,
                          onSelected: (sel) {
                            if (sel) {
                              setDlgState(() {
                                dateChoisie = qJeu.date;
                                noteCtrl.text = 'Remise anticipée le Jeudi (Vendredi férié/estimé)';
                              });
                            }
                          },
                        ),
                        ChoiceChip(
                          label: Text('Mercredi ${qMer.date.day}/${qMer.date.month}'),
                          selected: isMercredi,
                          selectedColor: Colors.amber.shade300,
                          onSelected: (sel) {
                            if (sel) {
                              setDlgState(() {
                                dateChoisie = qMer.date;
                                noteCtrl.text = 'Remise anticipée le Mercredi';
                              });
                            }
                          },
                        ),
                        ChoiceChip(
                          label: Text('Mardi ${qMar.date.day}/${qMar.date.month}'),
                          selected: isMardi,
                          selectedColor: Colors.amber.shade300,
                          onSelected: (sel) {
                            if (sel) {
                              setDlgState(() {
                                dateChoisie = qMar.date;
                                noteCtrl.text = 'Remise anticipée le Mardi';
                              });
                            }
                          },
                        ),
                        ChoiceChip(
                          label: Text('Vendredi ${qVen.date.day}/${qVen.date.month} (Normal)'),
                          selected: isVendrediNormal,
                          selectedColor: Colors.green.shade200,
                          onSelected: (sel) {
                            if (sel) {
                              setDlgState(() {
                                dateChoisie = qVen.date;
                                noteCtrl.text = 'Remise normale le Vendredi';
                              });
                            }
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    if (!isVendrediNormal) ...[
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.info_outline, size: 16, color: Colors.blue),
                                SizedBox(width: 6),
                                Text(
                                  'Heures estimées par jour restant :',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blue),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Heures / jour :'),
                                Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.remove_circle_outline, size: 18),
                                      onPressed: heuresEstimees > 0
                                          ? () => setDlgState(() => heuresEstimees--)
                                          : null,
                                    ),
                                    Text('$heuresEstimees h',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                    IconButton(
                                      icon: const Icon(Icons.add_circle_outline, size: 18),
                                      onPressed: heuresEstimees < 12
                                          ? () => setDlgState(() => heuresEstimees++)
                                          : null,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    TextField(
                      controller: noteCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Motif / Justification pour la paie',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              if (periode.estRemiseAnticipee)
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  onPressed: () async {
                    Navigator.pop(ctx, false);
                    await _repo.reinitialiserDateRemise();
                    await _charger();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Cycle normal rétabli (Remise le Vendredi).')),
                      );
                    }
                  },
                  child: const Text('Rétablir Vendredi normal'),
                ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuler'),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.check),
                label: Text(isVendrediNormal ? 'Valider Vendredi' : 'Appliquer Remise Anticipée'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isVendrediNormal ? Colors.green.shade800 : Colors.amber.shade900,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(ctx, true),
              ),
            ],
          );
        },
      ),
    );

    if (valider == true) {
      final isVen = dateChoisie.year == qVen.date.year &&
          dateChoisie.month == qVen.date.month &&
          dateChoisie.day == qVen.date.day;

      if (isVen) {
        await _repo.reinitialiserDateRemise(technicien: _technicienSelectionne?.nom);
      } else {
        final totalMin = (heuresEstimees * 60) + minutesEstimees;
        await _repo.appliquerRemiseAnticipee(
          dateRemise: dateChoisie,
          minutesParJourRestant: totalMin,
          notes: noteCtrl.text,
          technicien: _technicienSelectionne?.nom,
        );
      }
      await _charger();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isVen
                  ? 'Cycle normal rétabli (Remise le Vendredi).'
                  : '⚡ Remise anticipée fixée au ${formatNomJour(dateChoisie.weekday)} ${dateChoisie.day}/${dateChoisie.month} !',
            ),
            backgroundColor: isVen ? Colors.green.shade800 : Colors.amber.shade900,
          ),
        );
      }
    }
  }

  /// Dialogue pour estimer ou modifier les heures du dernier vendredi
  Future<void> _dialogueEstimerVendredi(DateTime dateVendredi) async {
    if (!await _demanderNipSecurise(action: 'estimer les heures du vendredi')) return;
    if (!mounted) return;

    int heuresChoisie = 8;
    int minutesChoisie = 0;

    final qVendredi = _periode?.quartDernierVendredi;
    if (qVendredi != null && qVendredi.estEstime) {
      final totalMin = qVendredi.tempsPayeMinutes;
      heuresChoisie = totalMin ~/ 60;
      minutesChoisie = totalMin % 60;
    }

    final noteCtrl = TextEditingController(
      text: qVendredi?.notes.isNotEmpty == true
          ? qVendredi!.notes
          : 'Estimé pour remise de paie le vendredi',
    );

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          final totalMinutes = (heuresChoisie * 60) + minutesChoisie;
          final totalDecimal = (totalMinutes / 60.0).toStringAsFixed(2);

          return AlertDialog(
            title: const Row(
              children: [
                CircleAvatar(backgroundColor: Colors.amber, child: Icon(Icons.flash_on, color: Colors.white)),
                SizedBox(width: 10),
                Expanded(child: Text('Estimer le Vendredi de Remise', style: TextStyle(fontSize: 16))),
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
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: const Text(
                      'Puisque la feuille de paie est remise le vendredi, vous pouvez déclarer ici '
                      'votre estimation d\'heures payées pour compléter la période de 2 semaines.',
                      style: TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                  ),
                  const SizedBox(height: 16),

                  const Text('Raccourcis rapides :', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      ActionChip(
                        label: const Text('8h00 standard'),
                        onPressed: () => setDlgState(() {
                          heuresChoisie = 8;
                          minutesChoisie = 0;
                        }),
                      ),
                      ActionChip(
                        label: const Text('8h30'),
                        onPressed: () => setDlgState(() {
                          heuresChoisie = 8;
                          minutesChoisie = 30;
                        }),
                      ),
                      ActionChip(
                        label: const Text('9h00'),
                        onPressed: () => setDlgState(() {
                          heuresChoisie = 9;
                          minutesChoisie = 0;
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Sélecteur précis
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Temps payé estimé :', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text(
                          '$heuresChoisie h ${minutesChoisie.toString().padLeft(2, '0')}m ($totalDecimal h)',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green.shade800),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      const Text('Heures : '),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: heuresChoisie > 1 ? () => setDlgState(() => heuresChoisie--) : null,
                      ),
                      Text('$heuresChoisie h', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: heuresChoisie < 16 ? () => setDlgState(() => heuresChoisie++) : null,
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Text('Minutes : '),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: minutesChoisie >= 15 ? () => setDlgState(() => minutesChoisie -= 15) : null,
                      ),
                      Text('$minutesChoisie m', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: minutesChoisie <= 45 ? () => setDlgState(() => minutesChoisie += 15) : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  TextField(
                    controller: noteCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Note d\'estimation (affichée sur le rapport)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
              ElevatedButton.icon(
                icon: const Icon(Icons.check),
                label: const Text('Enregistrer l\'estimation'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade900, foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(ctx, true),
              ),
            ],
          );
        },
      ),
    );

    if (result == true) {
      final totalMin = (heuresChoisie * 60) + minutesChoisie;
      await _repo.estimerDernierVendredi(
        dateVendredi,
        totalMin,
        notes: noteCtrl.text,
        technicien: _technicienSelectionne?.nom,
      );
      await _charger();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚡ Vendredi estimé à $heuresChoisie h ${minutesChoisie}m pour la remise de paie !'),
            backgroundColor: Colors.amber.shade900,
          ),
        );
      }
    }
  }

  /// Carte supérieure de sélection et de protection NIP du technicien
  Widget _buildCardTechnicienSecurise() {
    final techActuel = _technicienSelectionne ?? _techniciens.first;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _estDeverrouille ? Colors.green.shade400 : const Color(0xFFD1001F).withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFD1001F).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person, color: Color(0xFFD1001F), size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'COMPTE TECHNICIEN (FEUILLE DE TEMPS)',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                    color: Colors.grey,
                  ),
                ),
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    key: const Key('technicien_dropdown'),
                    value: techActuel.nom,
                    isDense: true,
                    icon: const Icon(Icons.arrow_drop_down, color: Colors.black54),
                    items: _techniciens.map((t) {
                      return DropdownMenuItem<String>(
                        value: t.nom,
                        child: Row(
                          children: [
                            Text(
                              t.nom,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: Colors.black87,
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
                                style: const TextStyle(fontSize: 10, color: Colors.black54),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (nom) {
                      if (nom != null && nom != techActuel.nom) {
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
            key: const Key('nip_lock_toggle_button'),
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
                _demanderNipSecurise(action: 'déverrouiller votre feuille de temps');
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
          // Menu d'options
          PopupMenuButton<String>(
            key: const Key('nip_options_menu_button'),
            icon: const Icon(Icons.more_vert, size: 20, color: Colors.grey),
            tooltip: 'Options de sécurité',
            onSelected: (val) {
              if (val == 'changer_nip') {
                _changerNipModal();
              } else if (val == 'verrouiller') {
                setState(() => _estDeverrouille = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('🔒 Session verrouillée.'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'changer_nip',
                child: Row(
                  children: [
                    Icon(Icons.password, size: 18, color: Colors.blueGrey),
                    SizedBox(width: 8),
                    Text('Modifier mon code NIP'),
                  ],
                ),
              ),
              if (_estDeverrouille)
                const PopupMenuItem(
                  value: 'verrouiller',
                  child: Row(
                    children: [
                      Icon(Icons.lock, size: 18, color: Colors.amber),
                      SizedBox(width: 8),
                      Text('Verrouiller la session'),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBandeauPdfFeuilleDePaie(PeriodePaie periode) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.indigo.shade300, width: 1.2),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.indigo.shade100,
            child: const Icon(Icons.picture_as_pdf, color: Colors.indigo, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Feuille de paie officielle (${periode.debut.day}/${periode.debut.month} au ${periode.finVendredi.day}/${periode.finVendredi.month})',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Colors.indigo.shade900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Total certifié : ${formatMinutes(periode.totalMinutesPeriode)} (${periode.totalHeuresDecimalesPeriode} h) • Visualisation & impression directe Windows',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            icon: const Icon(Icons.print, size: 15),
            label: const Text('Aperçu & Imprimer', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            onPressed: () => FeuilleDeTempsPdfService.imprimerApercuPdf(context, periode),
          ),
          const SizedBox(width: 6),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            icon: const Icon(Icons.email, size: 15),
            label: const Text('Outlook', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            onPressed: () => FeuilleDeTempsPdfService.envoyerParOutlook(context, periode),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final periode = _periode;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text(
          'Feuille de Temps & Paie',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFFD1001F),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.amberAccent,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(icon: Icon(Icons.calendar_month), text: '2 Semaines (Paie)'),
            Tab(icon: Icon(Icons.view_week), text: 'Semaine en cours'),
            Tab(icon: Icon(Icons.punch_clock), text: 'Aujourd\'hui'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _charger,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildCardTechnicienSecurise(),
          if (isWindowsDesktop && periode != null) _buildBandeauPdfFeuilleDePaie(periode),
          Expanded(
            child: _isLoading || periode == null
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildVueDeuxSemaines(periode),
                      _buildVueSemaine(periode),
                      _buildVueAujourdhui(periode),
                    ],
                  ),
          ),
        ],
      ),
      // ─── LE GRAND BOUTON AU MOMENT DEMANDÉ ─────────────────────────
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
              periode?.estRemiseAnticipee == true
                  ? 'GÉNÉRER RAPPORT (REMISE ANTICIPÉE)'
                  : 'GÉNÉRER RAPPORT DE PAIE (2 SEMAINES)',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade800,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 4,
            ),
            onPressed: () {
              if (_periode != null) {
                FeuilleDeTempsPdfService.afficherDialogueExportPeriode(
                  context,
                  _periode!,
                );
              }
            },
          ),
        ),
      ),
    );
  }

  // ─── VUE 1 : PÉRIODE DE 2 SEMAINES ─────────────────────────────────
  Widget _buildVueDeuxSemaines(PeriodePaie periode) {
    final strDebut = '${periode.debut.day}/${periode.debut.month}';
    final strFin = '${periode.finVendredi.day}/${periode.finVendredi.month}';
    final strRemise = '${periode.dateRemiseEffective.day}/${periode.dateRemiseEffective.month}';
    final qVendredi = periode.quartDernierVendredi;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
      children: [
        // Carte récapitulative
        Card(
          elevation: 3,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PÉRIODE DE PAIE ($strDebut au $strFin)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade700,
                            letterSpacing: 1.1,
                          ),
                        ),
                        Text(
                          periode.technicien,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    InkWell(
                      onTap: _dialogueRemiseAnticipee,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: periode.estRemiseAnticipee
                              ? Colors.amber.shade100
                              : Colors.indigo.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: periode.estRemiseAnticipee
                                ? Colors.amber.shade500
                                : Colors.indigo.shade200,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              periode.estRemiseAnticipee ? Icons.flash_on : Icons.event_available,
                              size: 14,
                              color: periode.estRemiseAnticipee
                                  ? Colors.amber.shade900
                                  : Colors.indigo.shade900,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              periode.estRemiseAnticipee
                                  ? 'Remise anticipée : ${periode.nomJourDateRemise} $strRemise ✏️'
                                  : 'Remise Vendredi $strFin ✏️',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: periode.estRemiseAnticipee
                                    ? Colors.amber.shade900
                                    : Colors.indigo.shade900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 20),

                // Grand total
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade300),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.green.shade700,
                        child: const Icon(Icons.monetization_on_outlined, color: Colors.white),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'TOTAL PAIE (2 SEMAINES)',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green),
                            ),
                            Text(
                              '${formatMinutes(periode.totalMinutesPeriode)} (${periode.totalHeuresDecimalesPeriode} h)',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Sous-totaux Semaine 1 et Semaine 2
                Row(
                  children: [
                    Expanded(
                      child: _buildBadgeSemaine(
                        'Semaine 1',
                        formatMinutes(periode.totalMinutesSemaine1),
                        '${(periode.totalMinutesSemaine1 / 60.0).toStringAsFixed(2)} h',
                        Colors.blue.shade700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildBadgeSemaine(
                        'Semaine 2',
                        formatMinutes(periode.totalMinutesSemaine2),
                        '${(periode.totalMinutesSemaine2 / 60.0).toStringAsFixed(2)} h',
                        Colors.teal.shade700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Bannière spéciale Remise / Estimation
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: periode.estRemiseAnticipee ? Colors.amber.shade100 : Colors.amber.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: periode.estRemiseAnticipee ? Colors.amber.shade600 : Colors.amber.shade400,
              width: periode.estRemiseAnticipee ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Icon(
                periode.estRemiseAnticipee ? Icons.send_time_extension_rounded : Icons.flash_on,
                color: Colors.amber.shade900,
                size: 28,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      periode.estRemiseAnticipee
                          ? '⚡ REMISE ANTICIPÉE ACTIVE : ${periode.nomJourDateRemise.toUpperCase()} $strRemise'
                          : (qVendredi != null && qVendredi.estEstime
                              ? '⚡ Dernier Vendredi : Estimé à ${qVendredi.tempsPayeFormate}'
                              : '⚡ Remise de la feuille de paie'),
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber.shade900, fontSize: 13),
                    ),
                    Text(
                      periode.estRemiseAnticipee
                          ? 'Les journées restantes sont estimées. Cliquez sur une journée pour corriger au besoin.'
                          : 'Vous devez remettre votre feuille plus tôt ou modifier des heures ?',
                      style: const TextStyle(fontSize: 11, color: Colors.black87),
                    ),
                  ],
                ),
              ),
              Wrap(
                spacing: 6,
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.edit_calendar, size: 14),
                    label: Text(periode.estRemiseAnticipee ? 'Modifier' : 'Remise anticipée'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber.shade900,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    onPressed: _dialogueRemiseAnticipee,
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Détail Semaine 1
        _buildCartesJours('Semaine 1', periode.quartsSemaine1),

        const SizedBox(height: 16),

        // Détail Semaine 2
        _buildCartesJours('Semaine 2 (Semaine courante)', periode.quartsSemaine2, finVendredi: periode.finVendredi),
      ],
    );
  }

  // ─── VUE 2 : SEMAINE EN COURS ──────────────────────────────────────
  Widget _buildVueSemaine(PeriodePaie periode) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
      children: [
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('TOTAL SEMAINE EN COURS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                    Text(
                      '${formatMinutes(periode.totalMinutesSemaine2)} (${(periode.totalMinutesSemaine2 / 60.0).toStringAsFixed(2)} h)',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.teal.shade800),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 6,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.send_time_extension, size: 14),
                      label: const Text('Remise anticipée', style: TextStyle(fontSize: 11)),
                      onPressed: _dialogueRemiseAnticipee,
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.flash_on, size: 14),
                      label: const Text('Estimer Vendredi', style: TextStyle(fontSize: 11)),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade900, foregroundColor: Colors.white),
                      onPressed: () => _dialogueEstimerVendredi(periode.finVendredi),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildCartesJours('Jours de la semaine', periode.quartsSemaine2, finVendredi: periode.finVendredi),
      ],
    );
  }

  // ─── VUE 3 : AUJOURD'HUI & HORODATEUR EN DIRECT ────────────────────
  Widget _buildVueAujourdhui(PeriodePaie periode) {
    final quart = _quartAujourdhui;
    final estActif = quart != null && quart.estActif;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
      children: [
        Card(
          elevation: 3,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                colors: estActif
                    ? [Colors.indigo.shade900, Colors.indigo.shade700]
                    : [Colors.blueGrey.shade800, Colors.blueGrey.shade600],
              ),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      estActif
                          ? 'PUNCH EN COURS (ACTIF)'
                          : (quart != null && quart.punches.isNotEmpty
                              ? 'PUNCH EN PAUSE'
                              : 'AUCUN PUNCH ACTIF'),
                      style: TextStyle(
                        color: estActif
                            ? Colors.greenAccent
                            : (quart != null ? Colors.amberAccent : Colors.grey.shade300),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    if (quart != null)
                      Text(
                        estActif
                            ? 'Début : ${formatHeureDateTime(quart.clockIn)}'
                            : '${formatHeureDateTime(quart.clockIn)} - ${quart.clockOut != null ? formatHeureDateTime(quart.clockOut!) : "--:--"}',
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                      ),
                  ],
                ),
                if (estActif) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.timer, color: Colors.greenAccent, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Chrono en direct : ${formatChrono(quart.cumulSecondesPunches)}',
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (quart != null && quart.punches.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.pause_circle_outline, color: Colors.amberAccent.shade100, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Punch en pause : ${formatChrono(quart.cumulSecondesPunches)} cumulé',
                          style: TextStyle(
                            color: Colors.amberAccent.shade100,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Total payé aujourd\'hui : ${quart.tempsPayeFormate} (${quart.tempsPayeDecimal} h)',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
                if (quart != null && quart.punches.length > 1) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: quart.punches.asMap().entries.map((entry) {
                      final i = entry.key + 1;
                      final p = entry.value;
                      final inStr = formatHeureDateTime(p.entree);
                      final outStr = p.sortie != null ? formatHeureDateTime(p.sortie!) : 'en cours';
                      final durStr = formatChrono(p.dureeSecondes);
                      final isActive = p.sortie == null;
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isActive
                              ? Colors.green.withValues(alpha: 0.25)
                              : Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isActive ? Colors.greenAccent : Colors.white24,
                            width: 1,
                          ),
                        ),
                        child: Text(
                          'P$i : $inStr - $outStr ($durStr)',
                          style: TextStyle(
                            fontSize: 11,
                            color: isActive ? Colors.greenAccent : Colors.white70,
                            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatItemMini('🚗 Trajet (1/4h)', formatMinutes(quart?.totalDeplacementMinutes ?? 0)),
                    _buildStatItemMini('🏗️ Chantier (1/4h)', formatMinutes(quart?.totalTravailMinutes ?? 0)),
                    _buildStatItemMini('🍽️ Repas', '-${formatMinutes(quart?.totalRepasMinutes ?? 0)}', isOrange: true),
                    _buildStatItemMini('⏱️ Net payé', quart?.tempsPayeFormate ?? '0h', isGreen: true),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: Icon(estActif ? Icons.pause_circle_filled : Icons.play_circle_filled, size: 22),
                    label: Text(
                      estActif
                          ? 'CLOCK-OUT (Pause / Arrêter le punch)'
                          : (quart != null && quart.punches.isNotEmpty
                              ? 'CLOCK-IN (Reprendre le travail)'
                              : 'CLOCK-IN (Démarrer le quart)'),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: estActif ? Colors.red.shade700 : Colors.green.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () async {
                      try {
                        if (estActif) {
                          if (!await _demanderNipSecurise(action: 'mettre en pause ou terminer votre quart (Clock-out)')) return;
                          await _repo.clockOut(quart.id, technicien: _technicienSelectionne?.nom);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('⏸️ Punch mis en pause • Interventions actives suspendues'),
                                backgroundColor: Colors.redAccent,
                                duration: Duration(seconds: 3),
                              ),
                            );
                          }
                        } else {
                          if (!await _demanderNipSecurise(action: 'commencer ou reprendre votre quart (Clock-in)')) return;
                          await _repo.clockIn(technicien: _technicienSelectionne?.nom);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('🟢 Punch activé • Chronomètre de travail en marche !'),
                                backgroundColor: Colors.green,
                                duration: Duration(seconds: 2),
                              ),
                            );
                          }
                        }
                        await _charger();
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
                          );
                        }
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        if (quart != null && quart.activites.isNotEmpty) ...[
          const SizedBox(height: 16),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.list_alt_rounded, size: 18, color: Colors.blueGrey),
                      const SizedBox(width: 8),
                      Text(
                        'ACTIVITÉS DU JOUR (${quart.activites.length})',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey),
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  ...quart.activites.map((act) {
                    final isTrajetOuChantier =
                        act.type == TypeActivite.deplacement || act.type == TypeActivite.travail;
                    final arrondiBadge = isTrajetOuChantier ? ' (1/4h haut)' : ' (1/4h)';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: act.couleur.withValues(alpha: 0.15),
                            child: Icon(act.icone, size: 18, color: act.couleur),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  act.description,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${formatHeureDateTime(act.debut)} - ${act.fin != null ? formatHeureDateTime(act.fin!) : "En cours"} ${act.reference != null ? "• ${act.reference}" : ""}',
                                  style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: act.couleur.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${formatMinutes(act.dureeMinutes)}$arrondiBadge',
                              style: TextStyle(
                                color: act.couleur,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStatItemMini(String label, String valeur, {bool isGreen = false, bool isOrange = false}) {
    Color col = Colors.white;
    if (isGreen) col = Colors.greenAccent;
    if (isOrange) col = Colors.orangeAccent;

    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
        const SizedBox(height: 2),
        Text(valeur, style: TextStyle(color: col, fontWeight: FontWeight.bold, fontSize: 16)),
      ],
    );
  }

  Widget _buildBadgeSemaine(String titre, String duree, String decimal, Color color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titre, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(
            '$duree ($decimal)',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildCartesJours(String titre, List<QuartDeTravail> quarts, {DateTime? finVendredi}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Text(
            titre,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
        ),
        ...quarts.map((q) {
          final isEstimated = q.estEstime;

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: isEstimated
                  ? BorderSide(color: Colors.amber.shade700, width: 1.5)
                  : BorderSide.none,
            ),
            child: ListTile(
              onTap: () => _dialogueModifierJournee(q),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              leading: CircleAvatar(
                backgroundColor: isEstimated ? Colors.amber.shade100 : Colors.indigo.shade50,
                child: Text(
                  q.nomJourSemaine.substring(0, 2),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: isEstimated ? Colors.amber.shade900 : Colors.indigo.shade900,
                  ),
                ),
              ),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        '${q.nomJourSemaine} ${q.date.day}/${q.date.month}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      if (isEstimated) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade200,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'ESTIMÉ',
                            style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: Colors.amber.shade900),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    '${q.tempsPayeFormate} (${q.tempsPayeDecimal} h)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: isEstimated ? Colors.amber.shade900 : Colors.green.shade800,
                    ),
                  ),
                ],
              ),
              subtitle: Text(
                isEstimated
                    ? '⚡ ESTIMÉ : ${q.notes.isNotEmpty ? q.notes : "Déclaré d'avance pour remise anticipée"}'
                    : '${q.notes.isNotEmpty ? "📝 ${q.notes} • " : ""}Trajet: ${formatMinutes(q.totalDeplacementMinutes)} • Chantier: ${formatMinutes(q.totalTravailMinutes)} • Attente: ${formatMinutes(q.totalAttenteMinutes)} • Repas: -${formatMinutes(q.totalRepasMinutes)}',
                style: TextStyle(
                  fontSize: 11,
                  color: isEstimated ? Colors.amber.shade900 : Colors.grey.shade700,
                  fontWeight: isEstimated ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              trailing: IconButton(
                icon: Icon(
                  Icons.edit_outlined,
                  color: isEstimated ? Colors.amber.shade900 : Colors.blueGrey.shade700,
                  size: 20,
                ),
                tooltip: 'Modifier cette journée (erreur, horaires, repas)',
                onPressed: () => _dialogueModifierJournee(q),
              ),
            ),
          );
        }),
      ],
    );
  }
}

// ============================================================================
// 📌 BANNIÈRE HORODATEUR DU DASHBOARD (AGENDA)
// ============================================================================

class HorodateurBanniereWidget extends StatefulWidget {
  final VoidCallback onRefresh;
  final String? technicien;

  const HorodateurBanniereWidget({super.key, required this.onRefresh, this.technicien});

  @override
  State<HorodateurBanniereWidget> createState() => _HorodateurBanniereWidgetState();
}

class _HorodateurBanniereWidgetState extends State<HorodateurBanniereWidget> {
  final FeuilleDeTempsRepository _repo = FeuilleDeTempsRepository.instance;
  PeriodePaie? _periode;
  Timer? _liveTimer;

  @override
  void initState() {
    super.initState();
    _recharger(forcerSupabase: true);
    // Rafraîchissement périodique léger (toutes les 15s) pour mettre à jour les cumuls en local sans forcer de requêtes Supabase en boucle
    _liveTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) {
        _recharger(forcerSupabase: false);
      }
    });
  }

  @override
  void didUpdateWidget(covariant HorodateurBanniereWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.technicien != widget.technicien) {
      _recharger(forcerSupabase: false);
    }
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    super.dispose();
  }

  Future<void> _recharger({bool forcerSupabase = false}) async {
    final p = await _repo.getPeriodePaieActuelle(
      technicien: widget.technicien,
      syncSupabase: forcerSupabase,
    );
    if (mounted) {
      // Évite de déclencher setState si les données n'ont pas changé (anti-flicker)
      if (_periode?.totalHeuresDecimalesPeriode != p.totalHeuresDecimalesPeriode ||
          _periode?.debut != p.debut ||
          _periode?.finVendredi != p.finVendredi) {
        setState(() {
          _periode = p;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _periode;
    final totalHeures = p?.totalHeuresDecimalesPeriode ?? 0.0;
    final quartAujourdhui = _repo.getQuartActif(technicien: widget.technicien) ??
        _repo.getQuartPourJour(DateTime.now(), technicien: widget.technicien);
    final bool punchActif = quartAujourdhui?.estActif == true;
    final int secPunches = quartAujourdhui?.cumulSecondesPunches ?? 0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => FeuilleDeTempsScreen(technicienInitial: widget.technicien)),
          );
          _recharger();
          widget.onRefresh();
        },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.indigo.shade200, width: 1.5),
            color: Colors.indigo.shade50,
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: punchActif ? Colors.green.shade800 : Colors.indigo.shade900,
                child: Icon(
                  punchActif ? Icons.timer : Icons.punch_clock,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Text(
                          'PÉRIODE DE PAIE (2 SEMAINES)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo.shade900,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.green.shade700,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${totalHeures.toStringAsFixed(1)} h payées',
                            style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: punchActif
                                ? Colors.green.shade700
                                : (secPunches > 0 ? Colors.amber.shade800 : Colors.blueGrey.shade600),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                punchActif
                                    ? Icons.play_arrow
                                    : (secPunches > 0 ? Icons.pause : Icons.stop),
                                size: 10,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                punchActif
                                    ? 'Punch : ${formatChrono(secPunches)}'
                                    : (secPunches > 0
                                        ? 'Pause : ${formatChrono(secPunches)}'
                                        : 'Non punché'),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      p?.estRemiseAnticipee == true
                          ? '⚡ Remise anticipée : ${p?.nomJourDateRemise} • Cliquez pour voir et exporter'
                          : (p?.dernierVendrediEstEstime == true
                              ? 'Vendredi estimé • Cliquez pour visualiser et générer le rapport'
                              : 'Remise le vendredi • Cliquez pour estimer et générer le rapport'),
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
