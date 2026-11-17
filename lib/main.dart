import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_helpers.dart';
import 'nip_service.dart';
import 'crane_header_widget.dart';
import 'feuille_de_temps.dart';
import 'techniciens_service.dart';
import 'depenses_service.dart';
import 'rendez_vous_service.dart';
import 'inventaire_screen.dart';
import 'inventaire_donnees.dart';
import 'rapport_form_screen.dart';
import 'rapport_detail_screen.dart';
import 'widget_photos_chantier.dart';
import 'rapport_pdf.dart';
import 'signature_distance_service.dart';
import 'signature_client_web_screen.dart';
import 'archives_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🔗 CONNEXION SUPABASE
  await Supabase.initialize(
    url: 'https://tnkyoqpxewvjsqlkvkcf.supabase.co',
    publishableKey: 'sb_publishable_CvS_y4fnMs34RjNqokh2-A_QW9YGUFU',
  );

  // 📦 INITIALISATION INVENTAIRE CAMIONS
  try {
    await InventaireService.instance.initialiser();
  } catch (e) {
    debugPrint('Initialisation inventaire: $e');
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RaycoFieldService',
      theme: ThemeData(
        fontFamilyFallback: const [
          'Segoe UI Emoji',
          'Segoe UI Symbol',
          'Noto Color Emoji',
          'Apple Color Emoji',
        ],
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFD1001F),
          primary: const Color(0xFFD1001F),
          secondary: const Color(0xFF8B0000),
          surface: Colors.white,
        ),
        primaryColor: const Color(0xFFD1001F),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFD1001F),
          foregroundColor: Colors.white,
          elevation: 2,
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 4,
          showCloseIcon: true,
          insetPadding: const EdgeInsets.fromLTRB(14, 0, 14, 70),
        ),
        useMaterial3: true,
      ),
      debugShowCheckedModeBanner: false,
      onGenerateRoute: (settings) {
        final uri = Uri.tryParse(settings.name ?? '');
        if (uri != null) {
          final path = uri.path;
          final token = uri.queryParameters['token'] ?? uri.queryParameters['id'];
          if ((path == '/signer' || path == 'signer' || uri.fragment.contains('signer')) &&
              token != null &&
              token.isNotEmpty) {
            return MaterialPageRoute(
              builder: (_) => SignatureClientWebScreen(token: token),
            );
          }
        }
        return null;
      },
      home: _determinerEcranInitial(),
    );
  }

  Widget _determinerEcranInitial() {
    if (kIsWeb) {
      final currentUri = Uri.base;
      final fragment = currentUri.fragment;
      final query = currentUri.queryParameters;
      String? token = query['token'] ?? query['id'];

      // Analyse du fragment si routage de type hash: #/signer?token=...
      if (token == null && fragment.contains('token=')) {
        final idx = fragment.indexOf('token=');
        token = fragment.substring(idx + 6).split('&').first;
      }

      if ((currentUri.path.contains('signer') || fragment.contains('signer')) &&
          token != null &&
          token.isNotEmpty) {
        return SignatureClientWebScreen(token: token);
      }
    }
    return const DashboardScreen();
  }
}

// ==========================================
// 📊 ÉCRAN 1 : L'AGENDA DU TECHNICIEN
// ==========================================
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  final SupabaseClient supabase = Supabase.instance.client;
  List<Map<String, dynamic>> interventions = [];
  List<Technicien> techniciens = [];
  String? filtreTechnicien;
  bool _isLoading = true;
  bool _isLiveConnected = false;
  bool _hasSupabaseExtraCols = false;
  StreamSubscription<List<Map<String, dynamic>>>? _interventionsSub;
  StreamSubscription<List<Map<String, dynamic>>>? _techniciensSub;
  Timer? _heartbeatTimer;
  Timer? _liveClockTimer;
  bool _navigationEnCours = false;
  final Set<String> _bandeauxMasques = {};
  final Set<String> _timersMasquagePlanifies = {};
  /// IDs créés localement mais pas encore confirmés par Supabase.
  final Set<String> _idsEnAttenteSync = {};
  /// IDs supprimés localement (évite une réapparition pendant la propagation).
  final Set<String> _idsSupprimes = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _verifierColonnesSupabase();
    chargerInterventions();
    _ecouterFluxEnDirect();
    TechnicienService.instance.addListener(_onTechniciensServiceUpdated);
    _demarrerHeartbeatAutoSync();
    _demarrerLiveClockTimer();

    // Réagir immédiatement si un technicien fait Clock-Out et suspend ses interventions
    FeuilleDeTempsRepository.onInterventionsModifieesParClockOut = (nomTech) {
      if (!mounted) return;
      final now = DateTime.now().toUtc();
      final techNorm = NipSecuriteService.normaliserNomTechnicien(nomTech)
          .toLowerCase();
      bool modifie = false;
      for (final item in interventions) {
        final t = (item['nom_technicien'] ?? '').toString().trim();
        if (NipSecuriteService.normaliserNomTechnicien(t).toLowerCase() ==
                techNorm ||
            t.toLowerCase() == nomTech.trim().toLowerCase()) {
          if (item['statut'] == 'En route') {
            item['statut'] = 'En pause';
            item['en_pause'] = true;
            item['heure_debut_pause'] = now.toIso8601String();
            modifie = true;
          } else if (item['statut'] == 'Arrivé') {
            item['statut'] = 'Intervention en pause';
            item['en_pause_chantier'] = true;
            item['heure_debut_pause_chantier'] = now.toIso8601String();
            item['motif_pause_chantier'] = 'Technicien Clock-Out (Pause)';
            modifie = true;
          }
        }
      }
      if (modifie && mounted) {
        setState(() {});
      }
    };
  }

  void _demarrerLiveClockTimer() {
    _liveClockTimer?.cancel();
    _liveClockTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) {
        final bool aDesInterventionsActives = interventions.any((it) {
          final st = it['statut'];
          return st == 'En route' ||
              st == 'En pause' ||
              st == 'Arrivé' ||
              st == 'Intervention en pause' ||
              it['en_pause_chantier'] == true;
        });
        if (aDesInterventionsActives) {
          setState(() {});
        }
      }
    });
  }

  Future<void> _verifierColonnesSupabase() async {
    try {
      await supabase
          .from('interventions')
          .select('numero_bon_commande, numero_unite')
          .limit(1);
      _hasSupabaseExtraCols = true;
    } catch (_) {
      _hasSupabaseExtraCols = false;
    }
  }

  void _extraireMetaDepuisNotes(Map<String, dynamic> item) {
    final notes = (item['notes'] ?? '').toString();
    if ((item['numero_bon_commande'] == null ||
            item['numero_bon_commande'].toString().isEmpty) &&
        notes.contains('[PO:')) {
      final m = RegExp(r'\[PO:\s*([^\]]+)\]').firstMatch(notes);
      if (m != null) item['numero_bon_commande'] = m.group(1)?.trim();
    }
    if ((item['numero_unite'] == null ||
            item['numero_unite'].toString().isEmpty) &&
        notes.contains('[UNITÉ:')) {
      final m = RegExp(r'\[UNITÉ:\s*([^\]]+)\]').firstMatch(notes);
      if (m != null) item['numero_unite'] = m.group(1)?.trim();
    }
    if ((item['numero_reference'] == null ||
            item['numero_reference'].toString().isEmpty) &&
        notes.contains('[RÉF:')) {
      final m = RegExp(r'\[RÉF:\s*([^\]]+)\]').firstMatch(notes);
      if (m != null) item['numero_reference'] = m.group(1)?.trim();
    }
    if (notes.contains('[RETOUR:')) {
      final m = RegExp(r'\[RETOUR:\s*([^|\]]+)(?:\|\s*([^\]]+))?\]')
          .firstMatch(notes);
      if (m != null) {
        final dStr = m.group(1)?.trim();
        final distStr = m.group(2)?.trim();
        if (dStr != null && dStr.isNotEmpty && item['duree_retour'] == null) {
          item['duree_retour'] = dStr;
          item['duree_retour_secondes'] = dureeChaineVersSecondes(dStr);
        }
        if (distStr != null &&
            distStr.isNotEmpty &&
            item['distance_retour_km'] == null) {
          item['distance_retour_km'] = distStr;
        }
      }
    }
    if (notes.contains('[CONTROLES:')) {
      final idx = notes.indexOf('[CONTROLES:');
      final startArray = notes.indexOf('[', idx + 11);
      if (startArray != -1) {
        final endArray = notes.indexOf(']', startArray);
        if (endArray != -1) {
          final cStr = notes.substring(startArray, endArray + 1).trim();
          try {
            final decoded = jsonDecode(cStr);
            if (decoded is List) {
              item['controles_securite'] = decoded;
            }
          } catch (_) {}
        }
      }
    }
    if (notes.contains('[SIG_TOKEN:')) {
      final m = RegExp(r'\[SIG_TOKEN:\s*([^\]]+)\]').firstMatch(notes);
      if (m != null) item['signature_token'] = m.group(1)?.trim();
    }
    if (notes.contains('[SIG_DISTANTE: OUI]')) {
      item['signature_a_distance_demandee'] = true;
    }
    if (notes.contains('[SIG_NOM:')) {
      final m = RegExp(r'\[SIG_NOM:\s*([^\]]+)\]').firstMatch(notes);
      if (m != null) item['nom_signataire_distant'] = m.group(1)?.trim();
    }
    if (notes.contains('[ARCHIVE: OUI]')) {
      item['est_archive'] = true;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _heartbeatTimer?.cancel();
    _liveClockTimer?.cancel();
    _interventionsSub?.cancel();
    _techniciensSub?.cancel();
    TechnicienService.instance.removeListener(_onTechniciensServiceUpdated);
    FeuilleDeTempsRepository.onInterventionsModifieesParClockOut = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint(
        '📱 Application active (Windows/Android) : synchro automatique...',
      );
      _syncSilencieuse();
    }
  }

  void _onTechniciensServiceUpdated() {
    if (mounted) {
      setState(() {
        techniciens = TechnicienService.instance.techniciens;
        if (filtreTechnicien != null &&
            !techniciens.any((t) => t.nom == filtreTechnicien)) {
          filtreTechnicien = null;
        }
      });
    }
  }

  /// ⚡ Écoute en direct des changements sur les tables Supabase (Realtime)
  void _ecouterFluxEnDirect() {
    _interventionsSub?.cancel();
    try {
      _interventionsSub = supabase
          .from('interventions')
          .stream(primaryKey: ['id'])
          .order('created_at', ascending: false)
          .listen(
            (data) {
              if (mounted) {
                setState(() {
                  _mettreAJourListeInterventions(
                    List<Map<String, dynamic>>.from(data),
                  );
                  _isLiveConnected = true;
                  _isLoading = false;
                });
              }
            },
            onError: (err) {
              debugPrint('Supabase Realtime interventions: $err');
              if (mounted) {
                setState(() => _isLiveConnected = false);
              }
            },
          );
    } catch (e) {
      debugPrint('Erreur stream interventions: $e');
    }

    _techniciensSub?.cancel();
    try {
      _techniciensSub = supabase
          .from('techniciens')
          .stream(primaryKey: ['id'])
          .order('nom', ascending: true)
          .listen(
            (data) {
              if (mounted) {
                final list = data
                    .map((item) => Technicien.fromJson(item))
                    .toList();
                setState(() {
                  techniciens = list;
                  if (filtreTechnicien != null &&
                      !techniciens.any((t) => t.nom == filtreTechnicien)) {
                    filtreTechnicien = null;
                  }
                });
              }
            },
            onError: (err) {
              debugPrint('Supabase Realtime techniciens: $err');
            },
          );
    } catch (e) {
      debugPrint('Erreur stream techniciens: $e');
    }
  }

  /// 💓 Battement de cœur : auto-synchronisation en arrière-plan toutes les 30 secondes (avec détection de changements)
  void _demarrerHeartbeatAutoSync() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _syncSilencieuse();
    });
  }

  void _mettreAJourListeInterventions(List<Map<String, dynamic>> remoteList) {
    final fetched = List<Map<String, dynamic>>.from(remoteList)
      ..removeWhere((f) => _idsSupprimes.contains(f['id']?.toString()));
    for (final item in fetched) {
      _extraireMetaDepuisNotes(item);
    }
    for (final local in interventions) {
      if (!fetched.any((f) => f['id'] == local['id'])) {
        // Absente du serveur : on ne la garde que si elle n'a pas encore été
        // envoyée. Sinon, elle a été supprimée par un autre appareil.
        if (_idsEnAttenteSync.contains(local['id']?.toString())) {
          fetched.insert(0, local);
        }
      } else {
        final remoteIdx = fetched.indexWhere((f) => f['id'] == local['id']);
        if (remoteIdx >= 0) {
          if ((fetched[remoteIdx]['numero_bon_commande'] == null ||
                  fetched[remoteIdx]['numero_bon_commande']
                      .toString()
                      .isEmpty) &&
              local['numero_bon_commande'] != null &&
              local['numero_bon_commande'].toString().isNotEmpty) {
            fetched[remoteIdx]['numero_bon_commande'] =
                local['numero_bon_commande'];
          }
          if ((fetched[remoteIdx]['numero_unite'] == null ||
                  fetched[remoteIdx]['numero_unite'].toString().isEmpty) &&
              local['numero_unite'] != null &&
              local['numero_unite'].toString().isNotEmpty) {
            fetched[remoteIdx]['numero_unite'] = local['numero_unite'];
          }
          if ((fetched[remoteIdx]['numero_reference'] == null ||
                  fetched[remoteIdx]['numero_reference'].toString().isEmpty) &&
              local['numero_reference'] != null &&
              local['numero_reference'].toString().isNotEmpty) {
            fetched[remoteIdx]['numero_reference'] = local['numero_reference'];
          }

          // ✍️ Détection de signature à distance nouvellement reçue
          final remoteSig = fetched[remoteIdx]['signature'] as String?;
          final localSig = local['signature'] as String?;
          if ((localSig == null || localSig.isEmpty) &&
              remoteSig != null &&
              remoteSig.isNotEmpty) {
            debugPrint('⚡ [Signature à distance reçue] Régénération auto du PDF pour ${fetched[remoteIdx]['numero_commande']}...');
            _recalculerPdfApresSignatureDistante(fetched[remoteIdx]);
          }
        }
      }
    }
    interventions = fetched;
  }

  /// Regénère automatiquement le PDF dès qu'une signature à distance est reçue
  Future<void> _recalculerPdfApresSignatureDistante(Map<String, dynamic> item) async {
    try {
      final nouveauPdfPath =
          await RapportPdfService.genererEtSauvegarderAutomatiquement(
        intervention: item,
        getNumeroDossier: getNumeroDossier,
        getDossierPhotos: getDossierPhotos,
        formatSeconds: formatSeconds,
        formatHeure: formatHeure,
      );
      if (nouveauPdfPath != null) {
        item['rapport_pdf_path'] = nouveauPdfPath;
      }
      if (mounted) {
        final client = item['nom_client'] ?? 'Client';
        final cmd = item['numero_commande'] ?? item['id'] ?? '';
        final nomSignataire = item['nom_signataire_distant'] ?? '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✍️ Signature à distance reçue pour $client ($cmd) ${nomSignataire.isNotEmpty ? "par $nomSignataire" : ""} !\nPDF actualisé avec succès.',
            ),
            backgroundColor: Colors.teal.shade800,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      debugPrint('Erreur régénération PDF signature distante: $e');
    }
  }

  Future<void> _syncSilencieuse() async {
    try {
      final response = await supabase
          .from('interventions')
          .select()
          .order('created_at', ascending: false);
      if (mounted) {
        final rawList = List<Map<String, dynamic>>.from(response);
        // Ne reconstruire que si les données ont réellement changé
        final ancienneLen = interventions.length;
        _mettreAJourListeInterventions(rawList);
        if (!_isLiveConnected || ancienneLen != interventions.length) {
          setState(() {
            _isLiveConnected = true;
          });
        }
      }
      final techs = await supabase
          .from('techniciens')
          .select()
          .order('nom', ascending: true);
      if (techs.isNotEmpty && mounted) {
        final list = List<Map<String, dynamic>>.from(techs)
            .map((item) => Technicien.fromJson(item))
            .toList();
        if (list.length != techniciens.length) {
          setState(() {
            techniciens = list;
            if (filtreTechnicien != null &&
                !techniciens.any((t) => t.nom == filtreTechnicien)) {
              filtreTechnicien = null;
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Erreur synchro silencieuse: $e');
    }
  }

  List<Map<String, dynamic>> _donneesSecours() {
    return [];
  }

  Future<void> chargerInterventions() async {
    setState(() => _isLoading = true);
    techniciens = await TechnicienService.instance.getTechniciens();

    try {
      final response = await supabase
          .from('interventions')
          .select()
          .order('created_at', ascending: false);

      setState(() {
        _mettreAJourListeInterventions(
          List<Map<String, dynamic>>.from(response),
        );
        _isLiveConnected = true;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Supabase inaccessible ou restrictions RLS actives: $e');
      setState(() {
        _isLiveConnected = false;
        _isLoading = false;
      });
    }
  }

  Future<void> insererDonneesInitialesSupabase() async {
    final exemples = _donneesSecours();
    try {
      await supabase.from('interventions').upsert(exemples);
      setState(() {
        interventions = exemples;
        _isLiveConnected = true;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint(
        'Impossible d\'insérer les données initiales dans Supabase: $e',
      );
      setState(() {
        interventions = exemples;
        _isLiveConnected = false;
        _isLoading = false;
      });
    }
  }

  Map<String, dynamic> assainirInterventionPourSupabase(
    Map<String, dynamic> raw,
  ) {
    final clean = <String, dynamic>{};
    for (final entry in raw.entries) {
      if (kColonnesInterventionsSupabase.contains(entry.key)) {
        clean[entry.key] = entry.value;
      }
    }
    if (raw['id'] != null) clean['id'] = raw['id'].toString();
    if ((clean['numero_serie_systeme'] == null ||
            clean['numero_serie_systeme'].toString().isEmpty) &&
        raw['systeme_wylie'] != null &&
        raw['systeme_wylie'].toString().isNotEmpty) {
      clean['numero_serie_systeme'] = raw['systeme_wylie'];
    }
    if ((clean['adresse'] == null || clean['adresse'].toString().isEmpty) &&
        raw['adresse_intervention'] != null &&
        raw['adresse_intervention'].toString().isNotEmpty) {
      clean['adresse'] = raw['adresse_intervention'];
    }
    if (raw['numero_reference'] != null &&
        raw['numero_reference'].toString().isNotEmpty) {
      clean['numero_reference'] = raw['numero_reference'];
    }
    if (_hasSupabaseExtraCols) {
      if (raw['numero_bon_commande'] != null) {
        clean['numero_bon_commande'] = raw['numero_bon_commande'];
      }
      if (raw['numero_unite'] != null) {
        clean['numero_unite'] = raw['numero_unite'];
      }
    }

    // Sauvegarde préventive dans 'notes' pour persistance même sans les colonnes dédiées
    final notesMeta = <String>[];
    if (raw['numero_bon_commande'] != null &&
        raw['numero_bon_commande'].toString().isNotEmpty) {
      notesMeta.add('[PO: ${raw['numero_bon_commande']}]');
    }
    if (raw['numero_unite'] != null &&
        raw['numero_unite'].toString().isNotEmpty) {
      notesMeta.add('[UNITÉ: ${raw['numero_unite']}]');
    }
    if (raw['numero_reference'] != null &&
        raw['numero_reference'].toString().isNotEmpty) {
      notesMeta.add('[RÉF: ${raw['numero_reference']}]');
    }
    if (notesMeta.isNotEmpty) {
      final existingNotes = (clean['notes'] ?? raw['notes'] ?? '').toString();
      final metaStr = notesMeta.join(' ');
      if (!existingNotes.contains('[PO:') &&
          !existingNotes.contains('[UNITÉ:')) {
        clean['notes'] = existingNotes.isEmpty
            ? metaStr
            : '$existingNotes\n$metaStr';
      }
    }

    clean['created_at'] ??= DateTime.now().toIso8601String();
    clean['updated_at'] = DateTime.now().toIso8601String();
    return clean;
  }

  Future<void> _sauvegarderInterventionSupabase(
    Map<String, dynamic> modifiee, {
    bool isUpdate = true,
  }) async {
    final clean = assainirInterventionPourSupabase(modifiee);
    final idStr = clean['id']?.toString();
    if (!isUpdate && idStr != null) _idsEnAttenteSync.add(idStr);
    try {
      if (isUpdate) {
        await supabase
            .from('interventions')
            .update(clean)
            .eq('id', clean['id']!);
      } else {
        await supabase.from('interventions').upsert(clean);
        _idsEnAttenteSync.remove(idStr);
      }
      if (mounted) setState(() => _isLiveConnected = true);
    } catch (e) {
      debugPrint('Erreur Supabase: $e');
      if (e.toString().contains('42703') ||
          e.toString().contains('does not exist')) {
        _hasSupabaseExtraCols = false;
        final fallback = Map<String, dynamic>.from(clean)
          ..remove('numero_bon_commande')
          ..remove('numero_unite');
        try {
          if (isUpdate) {
            await supabase
                .from('interventions')
                .update(fallback)
                .eq('id', fallback['id']!);
          } else {
            await supabase.from('interventions').upsert(fallback);
            _idsEnAttenteSync.remove(idStr);
          }
          if (mounted) setState(() => _isLiveConnected = true);
        } catch (e2) {
          debugPrint('Erreur Supabase fallback: $e2');
        }
      }
    }
  }

  /// 📦 Archive une intervention complétée (mise à jour mémoire + Supabase)
  Future<void> _archiverIntervention(Map<String, dynamic> item) async {
    archiverIntervention(item);
    setState(() {});

    final id = item['id'];
    if (id != null) {
      try {
        final nowStr = item['date_archivage'] ?? DateTime.now().toUtc().toIso8601String();
        await supabase.from('interventions').update({
          'est_archive': true,
          'date_archivage': nowStr,
          'notes': item['notes'],
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', id);
      } catch (e) {
        debugPrint('Erreur archivage Supabase (fallback notes): $e');
        try {
          await supabase.from('interventions').update({
            'notes': item['notes'],
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }).eq('id', id);
        } catch (_) {}
      }
    }

    try {
      await FeuilleDeTempsRepository.instance.synchroniserIntervention(item);
    } catch (_) {}

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('📦 Intervention ${item['numero_commande'] ?? ''} archivée avec succès.'),
          backgroundColor: const Color(0xFF455A64),
          action: SnackBarAction(
            label: 'Consulter archives',
            textColor: Colors.amberAccent,
            onPressed: _ouvrirEcranArchives,
          ),
        ),
      );
    }
  }

  /// 🔄 Restaure une intervention archivée vers les interventions actives
  Future<void> _restaurerIntervention(Map<String, dynamic> item) async {
    restaurerIntervention(item);
    setState(() {});

    final id = item['id'];
    if (id != null) {
      try {
        await supabase.from('interventions').update({
          'est_archive': false,
          'date_archivage': null,
          'notes': item['notes'],
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', id);
      } catch (e) {
        debugPrint('Erreur restauration Supabase (fallback notes): $e');
        try {
          await supabase.from('interventions').update({
            'notes': item['notes'],
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }).eq('id', id);
        } catch (_) {}
      }
    }

    try {
      await FeuilleDeTempsRepository.instance.synchroniserIntervention(item);
    } catch (_) {}
  }

  /// 🏛️ Ouvre la page dédiée aux Archives et Rapports clôturés
  void _ouvrirEcranArchives() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ArchivesRapportsScreen(
          interventions: interventions,
          onRestaurer: _restaurerIntervention,
          onSupprimerDefinitif: _confirmerSuppressionIntervention,
          onActualiser: chargerInterventions,
        ),
      ),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _confirmerSuppressionIntervention(
    Map<String, dynamic> item,
  ) async {
    final client = item['nom_client'] ?? 'Client inconnu';
    final commande = item['numero_commande'] ?? item['id'] ?? '';
    final confirmer = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade100,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.delete_forever,
                color: Colors.red,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Text('Supprimer l\'intervention'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Êtes-vous sûr de vouloir supprimer définitivement l\'intervention pour $client ($commande) ?',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.grey),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Cette action est irréversible et sera synchronisée en direct sur tous les appareils (Windows & Android).',
                      style: TextStyle(fontSize: 11, color: Colors.black87),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.delete, size: 18),
            label: const Text('Supprimer'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirmer == true) {
      final id = item['id']?.toString();
      if (id == null) return;
      final etaitEnAttente = _idsEnAttenteSync.remove(id);
      _idsSupprimes.add(id);
      setState(() {
        interventions.removeWhere((i) => i['id']?.toString() == id);
      });

      String? erreur;
      try {
        final supprimees = await supabase
            .from('interventions')
            .delete()
            .eq('id', id)
            .select('id');
        if (supprimees.isEmpty && !etaitEnAttente) {
          // Aucune ligne supprimée : soit déjà supprimée, soit bloquée par RLS.
          final encore = await supabase
              .from('interventions')
              .select('id')
              .eq('id', id)
              .maybeSingle();
          if (encore != null) {
            erreur =
                'Supabase a refusé la suppression (politique RLS DELETE manquante ?).';
          }
        }
        if (mounted) setState(() => _isLiveConnected = true);
      } catch (e) {
        debugPrint('Erreur suppression Supabase: $e');
        erreur = e.toString().contains('23503')
            ? 'Des données liées (rapports, photos…) empêchent la suppression.'
            : 'Erreur serveur : $e';
      }

      if (erreur != null) {
        // Échec côté serveur : on restaure l'intervention localement.
        _idsSupprimes.remove(id);
        if (mounted) {
          setState(() {
            if (!interventions.any((i) => i['id']?.toString() == id)) {
              interventions.insert(0, item);
            }
          });
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              erreur == null
                  ? '🗑️ Intervention $commande supprimée avec succès.'
                  : '❌ Suppression impossible : $erreur',
            ),
            backgroundColor:
                erreur == null ? Colors.red.shade800 : Colors.orange.shade900,
            duration: Duration(seconds: erreur == null ? 3 : 6),
          ),
        );
      }
    }
  }

  void ouvrirNouvelleIntervention() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => NouvelleInterventionModal(
        onInterventionCreee: (nouvelle) async {
          setState(() {
            filtreTechnicien = null; // Retire tout filtre pour voir immédiatement la nouvelle intervention
            interventions.removeWhere((i) => i['id'] == nouvelle['id']);
            interventions.insert(0, nouvelle);
          });
          await _sauvegarderInterventionSupabase(nouvelle, isUpdate: false);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '✅ Intervention créée et assignée à ${nouvelle['nom_technicien']} (${nouvelle['numero_camion']}) !',
              ),
              backgroundColor: Colors.green.shade800,
              duration: const Duration(seconds: 4),
            ),
          );
          // 📅 Envoi automatique au calendrier du technicien
          if (nouvelle['envoyer_calendrier_auto'] == true) {
            await CalendrierRendezVousService.envoyerInvitationOutlook(
              context,
              nouvelle,
              automatique: true,
            );
          }
        },
      ),
    );
  }

  void ouvrirGestionTechniciens() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const GestionTechniciensModal(),
    );
    final list = await TechnicienService.instance.getTechniciens();
    setState(() {
      techniciens = list;
    });
  }

  void _ouvrirModifierIntervention(Map<String, dynamic> item, int index) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ModifierInterventionModal(
        intervention: item,
        onInterventionModifiee: (modifiee) async {
          setState(() {
            interventions[index] = modifiee;
          });
          await _sauvegarderInterventionSupabase(modifiee, isUpdate: true);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '✅ Intervention ${modifiee['numero_commande']} mise à jour pour ${modifiee['nom_technicien']} !',
              ),
              backgroundColor: Colors.indigo.shade800,
            ),
          );
          // 📅 Mise à jour automatique au calendrier du technicien si demandée
          if (modifiee['envoyer_calendrier_auto'] == true) {
            await CalendrierRendezVousService.envoyerInvitationOutlook(
              context,
              modifiee,
              automatique: true,
            );
          }
        },
      ),
    );
  }

  void _ouvrirDialogueRendezVous(Map<String, dynamic> item) {
    CalendrierRendezVousService.afficherDialogueRendezVous(
      context,
      item,
      onModifiee: () async {
        setState(() {});
        try {
          await supabase
              .from('interventions')
              .update({
                'date_rendez_vous': item['date_rendez_vous'],
                'heure_rendez_vous': item['heure_rendez_vous'],
                'duree_minutes': item['duree_minutes'],
              })
              .eq('id', item['id']);
        } catch (e) {
          debugPrint('Erreur mise à jour rendez-vous Supabase: $e');
        }
      },
    );
  }

  void _afficherStatutSynchroModal() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: _isLiveConnected
                        ? Colors.green.shade100
                        : Colors.amber.shade100,
                    child: Icon(
                      _isLiveConnected ? Icons.cloud_done : Icons.cloud_off,
                      color: _isLiveConnected
                          ? Colors.green.shade800
                          : Colors.amber.shade900,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isLiveConnected
                            ? 'Synchronisation Supabase Active 🟢'
                            : 'Mode Secours / Local 🟠',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        _isLiveConnected
                            ? 'Temps réel connecté • Bidirectionnel'
                            : 'Données protégées hors-ligne',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
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
                    const Text(
                      '📡 Comment fonctionne la synchronisation :',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '• Le superviseur au bureau attribue ou modifie une intervention : elle s\'affiche instantanément sur le téléphone du technicien sur la route.\n'
                      '• Le technicien lance son trajet, met en pause, signe ou saisit un reçu de dépense : le superviseur le voit en direct sans rafraîchir.',
                      style: TextStyle(fontSize: 12, height: 1.4),
                    ),
                    if (!_isLiveConnected) ...[
                      const Divider(height: 16),
                      Text(
                        '💡 Pour activer le cloud, exécutez le script supabase_setup.sql dans votre tableau de bord Supabase (SQL Editor).',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.amber.shade900,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('Tester / Forcer la synchro'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD1001F),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        chargerInterventions();
                        _ecouterFluxEnDirect();
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBarreFiltreSuperviseur() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.supervisor_account,
                    size: 16,
                    color: Color(0xFFD1001F),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'DISPATCH RAYCOWYLIE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF8B0000),
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    ' (${techniciens.length} camions)',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: _afficherStatutSynchroModal,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2.5,
                      ),
                      decoration: BoxDecoration(
                        color: _isLiveConnected
                            ? Colors.green.shade50
                            : Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _isLiveConnected
                              ? Colors.green.shade300
                              : Colors.amber.shade300,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isLiveConnected
                                  ? Colors.green.shade700
                                  : Colors.amber.shade800,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _isLiveConnected ? 'En direct' : 'Mode local',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: _isLiveConnected
                                  ? Colors.green.shade900
                                  : Colors.amber.shade900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: ouvrirGestionTechniciens,
                child: Row(
                  children: const [
                    Icon(Icons.settings, size: 14, color: Color(0xFFD1001F)),
                    SizedBox(width: 4),
                    Text(
                      'Gérer techniciens',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFFD1001F),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(
                  label: Text('Tous (${interventions.where((i) => !estInterventionArchivee(i)).length})'),
                  selected: filtreTechnicien == null,
                  onSelected: (val) {
                    setState(() {
                      filtreTechnicien = null;
                    });
                  },
                ),
                const SizedBox(width: 6),
                ...techniciens.map((t) {
                  final count = interventions
                      .where((item) => !estInterventionArchivee(item) && item['nom_technicien'] == t.nom)
                      .length;
                  final isSelected = filtreTechnicien == t.nom;

                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      avatar: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: t.estDisponible ? Colors.green : Colors.red,
                        ),
                      ),
                      label: Text('${t.nom} • ${t.numeroCamion} ($count)'),
                      selected: isSelected,
                      onSelected: (val) {
                        setState(() {
                          filtreTechnicien = val ? t.nom : null;
                        });
                      },
                    ),
                  );
                }),
                const SizedBox(width: 8),
                // Accès direct rapide aux archives
                ActionChip(
                  avatar: const Icon(Icons.inventory_2, size: 15, color: Color(0xFF455A64)),
                  label: Text(
                    'Archives (${interventions.where((i) => estInterventionArchivee(i)).length})',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF455A64),
                    ),
                  ),
                  backgroundColor: Colors.blueGrey.shade50,
                  side: BorderSide(color: Colors.blueGrey.shade200),
                  onPressed: _ouvrirEcranArchives,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> insererDonneesTest() async {
    setState(() => _isLoading = true);
    await insererDonneesInitialesSupabase();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Données initialisées et synchronisées !'),
        ),
      );
    }
  }

  Future<void> ouvrirNavigation(dynamic adresseBrute) async {
    // Verrou anti-double-clic pour éviter que Google Maps ne s'ouvre deux fois
    if (_navigationEnCours) return;
    _navigationEnCours = true;

    try {
      final destination = (adresseBrute ?? '')
          .toString()
          .replaceAll(RegExp(r'[\r\n]+'), ' ')
          .trim();

      final String googleMapsUrl = destination.isNotEmpty
          ? "https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(destination)}&travelmode=driving"
          : "https://www.google.com/maps/dir/?api=1";
      final Uri url = Uri.parse(googleMapsUrl);

      // 1. Sous Windows Desktop : ouvrir le navigateur par défaut
      if (!kIsWeb && Platform.isWindows) {
        try {
          await launchUrl(url, mode: LaunchMode.externalApplication);
        } catch (e) {
          debugPrint('Erreur ouverture Google Maps Windows: $e');
        }
        return;
      }

      // 2. Sur Android : tenter d'abord l'URL https Google Maps en externalNonBrowserApplication
      // qui ouvre directement l'application native Google Maps installée
      if (!kIsWeb && Platform.isAndroid) {
        bool lance = false;
        try {
          lance = await launchUrl(
            url,
            mode: LaunchMode.externalNonBrowserApplication,
          );
        } catch (e) {
          debugPrint('Tentative externalNonBrowserApplication: $e');
        }
        if (lance) return;

        // Si non géré, tenter google.navigation
        if (destination.isNotEmpty) {
          try {
            final navUri = Uri.parse(
              "google.navigation:q=${Uri.encodeComponent(destination)}&mode=d",
            );
            if (await canLaunchUrl(navUri)) {
              lance = await launchUrl(
                navUri,
                mode: LaunchMode.externalApplication,
              );
              if (lance) return;
            }
          } catch (e) {
            debugPrint('Tentative google.navigation: $e');
          }

          // Puis geo URI
          try {
            final geoUri = Uri.parse(
              "geo:0,0?q=${Uri.encodeComponent(destination)}",
            );
            if (await canLaunchUrl(geoUri)) {
              lance = await launchUrl(
                geoUri,
                mode: LaunchMode.externalApplication,
              );
              if (lance) return;
            }
          } catch (e) {
            debugPrint('Tentative geo: $e');
          }
        }
      }

      // 3. Fallback universel (navigateur / application externe)
      try {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } catch (e) {
        debugPrint('Tentative fallback launchUrl: $e');
        try {
          await launchUrl(url, mode: LaunchMode.platformDefault);
        } catch (_) {}
      }
    } finally {
      // Déverrouiller après 1.5 seconde
      Future.delayed(const Duration(milliseconds: 1500), () {
        _navigationEnCours = false;
      });
    }
  }

  Future<void> demarrerTrajet(
    String id,
    int index,
    dynamic adresseBrute,
  ) async {
    final adresse = (adresseBrute ?? '').toString().trim();

    // 1. Ouvrir immédiatement et de façon garantie Google Maps pour démarrer le trajet
    unawaited(ouvrirNavigation(adresse));

    // 2. Démarrer immédiatement le temps de déplacement dans l'application (horodatage UTC réel)
    final now = DateTime.now().toUtc();
    final updates = <String, dynamic>{
      'statut': 'En route',
      'en_pause': false,
      'heure_depart_trajet': now.toIso8601String(),
      'duree_pause_secondes': 0,
    };

    if (mounted) {
      setState(() {
        interventions[index].addAll(updates);
      });
      unawaited(
        FeuilleDeTempsRepository.instance.synchroniserInterventions(
          interventions,
        ),
      );
    }

    // Assurer le punch-in automatique du technicien au début du trajet
    final nomTech = (interventions[index]['nom_technicien'] ?? '')
        .toString()
        .trim();
    if (nomTech.isNotEmpty) {
      unawaited(
        FeuilleDeTempsRepository.instance.assurerClockInActif(
          technicien: nomTech,
        ),
      );
    }

    // 3. Récupération GPS non-bloquante avec court timeout de sécurité
    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 3),
        ),
      );
    } catch (_) {}

    if (position != null) {
      updates['gps_depart'] =
          '(${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)})';
      updates['gps_lat_depart'] = position.latitude;
      updates['gps_lng_depart'] = position.longitude;
      if (mounted) {
        setState(() {
          interventions[index].addAll(updates);
        });
      }
    }

    // 4. Enregistrement dans Supabase
    try {
      final clean = <String, dynamic>{};
      for (final e in updates.entries) {
        if (kColonnesInterventionsSupabase.contains(e.key)) {
          clean[e.key] = e.value;
        }
      }
      await supabase.from('interventions').update(clean).eq('id', id);
    } catch (e) {
      debugPrint('Erreur mise à jour départ trajet Supabase: $e');
    }
  }

  Future<void> basculerPauseTrajet(String id, int index) async {
    final item = interventions[index];
    final bool estEnPause =
        item['en_pause'] == true || item['statut'] == 'En pause';
    final now = DateTime.now().toUtc();

    final updates = <String, dynamic>{};
    if (!estEnPause) {
      updates['en_pause'] = true;
      updates['heure_debut_pause'] = now.toIso8601String();
      updates['statut'] = 'En pause';
    } else {
      updates['en_pause'] = false;
      updates['statut'] = 'En route';
      final debutPauseStr = item['heure_debut_pause'] as String?;
      int pauseSec = (item['duree_pause_secondes'] is num)
          ? (item['duree_pause_secondes'] as num).toInt()
          : 0;
      if (debutPauseStr != null) {
        pauseSec += calculerSecondesEcoulees(debutPauseStr);
      }
      updates['duree_pause_secondes'] = pauseSec;

      // Reprise du trajet : assurer que le technicien est punch-in
      final nomTech = (item['nom_technicien'] ?? '').toString().trim();
      if (nomTech.isNotEmpty) {
        unawaited(
          FeuilleDeTempsRepository.instance.assurerClockInActif(
            technicien: nomTech,
          ),
        );
      }
    }

    try {
      final clean = <String, dynamic>{};
      for (final e in updates.entries) {
        if (kColonnesInterventionsSupabase.contains(e.key)) {
          clean[e.key] = e.value;
        }
      }
      await supabase.from('interventions').update(clean).eq('id', id);
    } catch (_) {}

    setState(() {
      interventions[index].addAll(updates);
    });
    unawaited(
      FeuilleDeTempsRepository.instance.synchroniserInterventions(
        interventions,
      ),
    );
  }

  Future<void> _afficherDialoguePauseChantier(String id, int index) async {
    final motifs = [
      {'label': 'Pause repas / dîner', 'icon': Icons.restaurant},
      {'label': 'Attente client / accès site', 'icon': Icons.hourglass_top},
      {'label': 'Attente grue / machine', 'icon': Icons.handyman},
      {
        'label': 'Appel support technique / bureau',
        'icon': Icons.phone_in_talk,
      },
      {'label': 'Pause générale / repos', 'icon': Icons.coffee},
    ];

    final motifChoisi = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.amber.shade100,
                    child: Icon(Icons.pause, color: Colors.amber.shade900),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mettre en pause l\'intervention',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        'Choisissez le motif de la pause :',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
              const Divider(height: 24),
              ...motifs.map(
                (m) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    m['icon'] as IconData,
                    color: Colors.amber.shade800,
                  ),
                  title: Text(
                    m['label'] as String,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: Colors.grey,
                  ),
                  onTap: () => Navigator.pop(ctx, m['label'] as String),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: const Text(
                    'Annuler',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (motifChoisi != null) {
      await basculerPauseIntervention(id, index, motif: motifChoisi);
    }
  }

  Future<void> basculerPauseIntervention(
    String id,
    int index, {
    String? motif,
  }) async {
    final item = interventions[index];
    final bool estEnPause =
        item['en_pause_chantier'] == true ||
        item['statut'] == 'Intervention en pause';
    final now = DateTime.now();

    final updates = <String, dynamic>{};
    if (!estEnPause) {
      updates['en_pause_chantier'] = true;
      updates['heure_debut_pause_chantier'] = now.toIso8601String();
      updates['statut'] = 'Intervention en pause';
      if (motif != null && motif.trim().isNotEmpty) {
        updates['motif_pause_chantier'] = motif.trim();
      }
    } else {
      updates['en_pause_chantier'] = false;
      updates['statut'] = 'Arrivé';
      final debutPauseStr = item['heure_debut_pause_chantier'] as String?;
      int pauseSec = 0;
      if (item['duree_pause_chantier_secondes'] is int) {
        pauseSec = item['duree_pause_chantier_secondes'] as int;
      }
      if (debutPauseStr != null) {
        final debut = DateTime.tryParse(debutPauseStr);
        if (debut != null) {
          pauseSec += now.difference(debut).inSeconds;
        }
      }
      updates['duree_pause_chantier_secondes'] = pauseSec;

      // Reprise de l'intervention : assurer que le technicien est punch-in
      final nomTech = (item['nom_technicien'] ?? '').toString().trim();
      if (nomTech.isNotEmpty) {
        unawaited(
          FeuilleDeTempsRepository.instance.assurerClockInActif(
            technicien: nomTech,
          ),
        );
      }
    }

    try {
      await supabase.from('interventions').update(updates).eq('id', id);
    } catch (_) {}

    setState(() {
      interventions[index].addAll(updates);
    });
    unawaited(
      FeuilleDeTempsRepository.instance.synchroniserInterventions(
        interventions,
      ),
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            !estEnPause
                ? '⏸️ Intervention mise en pause${motif != null ? ' ($motif)' : ''}'
                : '▶️ Intervention reprise !',
          ),
          backgroundColor: !estEnPause ? Colors.amber.shade900 : Colors.green,
        ),
      );
    }
  }

  Future<void> marquerArrive(String id, int index) async {
    final item = interventions[index];
    final now = DateTime.now().toUtc();
    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
    } catch (_) {}

    final departStr = item['heure_depart_trajet'] as String?;
    int pauseSec = (item['duree_pause_secondes'] is num)
        ? (item['duree_pause_secondes'] as num).toInt()
        : 0;
    if ((item['en_pause'] == true || item['statut'] == 'En pause') &&
        item['heure_debut_pause'] != null) {
      pauseSec += calculerSecondesEcoulees(item['heure_debut_pause']);
    }

    int totalTrajetSec = calculerSecondesEcoulees(
      departStr,
      pauseSec: pauseSec,
    );
    // RÈGLE : TOUJOURS ARR ONDIR LE TEMPS DE DÉPLACEMENT AU QUART D'HEURE SUPÉRIEUR (PLUS HAUT)
    final totalTrajetSecArrondi = arrondirAuQuartDHeureSecondes(
      totalTrajetSec > 0 ? totalTrajetSec : 60,
      toujoursPlusHaut: true,
    );
    final dureeTrajet = formatSeconds(totalTrajetSecArrondi);

    String distanceStr =
        (item['distance_km'] != null &&
            item['distance_km'].toString().isNotEmpty &&
            item['distance_km'] != '12.4 km')
        ? item['distance_km'].toString()
        : '--';
    double? latDepart;
    double? lngDepart;
    if (item['gps_lat_depart'] is num) {
      latDepart = (item['gps_lat_depart'] as num).toDouble();
    }
    if (item['gps_lng_depart'] is num) {
      lngDepart = (item['gps_lng_depart'] as num).toDouble();
    }

    if (position != null && latDepart != null && lngDepart != null) {
      final metres = Geolocator.distanceBetween(
        latDepart,
        lngDepart,
        position.latitude,
        position.longitude,
      );
      if (metres > 100) {
        distanceStr = '${(metres / 1000).toStringAsFixed(1)} km';
      }
    }

    final updates = <String, dynamic>{
      'statut': 'Arrivé',
      'en_pause': false,
      'heure_arrivee_site': now.toIso8601String(),
      'duree_trajet': dureeTrajet,
      'distance_km': distanceStr,
      'duree_pause_secondes': pauseSec,
      // Estimation automatique du trajet de retour au même temps et même distance
      'duree_retour': dureeTrajet,
      'duree_retour_secondes': totalTrajetSecArrondi,
      'distance_retour_km': distanceStr,
    };
    updates['duree_trajet_secondes'] = totalTrajetSecArrondi;

    if (position != null) {
      updates['gps_arrivee'] =
          '(${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)})';
    }

    try {
      final clean = <String, dynamic>{};
      for (final e in updates.entries) {
        if (kColonnesInterventionsSupabase.contains(e.key)) {
          clean[e.key] = e.value;
        }
      }
      await supabase.from('interventions').update(clean).eq('id', id);
    } catch (e) {
      debugPrint('Erreur Supabase marquerArrive: $e');
    }

    setState(() {
      interventions[index].addAll(updates);
    });
    unawaited(
      FeuilleDeTempsRepository.instance.synchroniserInterventions(
        interventions,
      ),
    );

    // Arrivée sur site : s'assurer que le punch est toujours actif
    final nomTech = (item['nom_technicien'] ?? '').toString().trim();
    if (nomTech.isNotEmpty) {
      unawaited(
        FeuilleDeTempsRepository.instance.assurerClockInActif(
          technicien: nomTech,
        ),
      );
    }
  }

  Color _getStatusColor(String? statut) {
    switch (statut) {
      case 'En route':
        return Colors.blueAccent;
      case 'En pause':
      case 'Intervention en pause':
        return Colors.amber.shade800;
      case 'Arrivé':
        return Colors.teal;
      case 'En attente d\'approbation':
        return Colors.amber.shade900;
      case 'Complété':
        return Colors.green;
      default:
        return Colors.orange;
    }
  }

  Widget _buildStatusBanner(Map<String, dynamic> item) {
    final statut = item['statut'] ?? 'En attente';
    final itemId = (item['id'] ?? '').toString();
    final now = DateTime.now();

    // Si le bandeau a été masqué (automatiquement après 5s ou manuellement), libérer l'espace
    if (_bandeauxMasques.contains(itemId)) {
      return const SizedBox.shrink();
    }

    if (statut == 'En route') {
      final departStr = item['heure_depart_trajet'] as String?;
      int pauseSec = (item['duree_pause_secondes'] is num)
          ? (item['duree_pause_secondes'] as num).toInt()
          : 0;
      final int elapsedSec = calculerSecondesEcoulees(
        departStr,
        pauseSec: pauseSec,
      );
      final chronoStr = formatChrono(elapsedSec);
      final int minTrajet = (elapsedSec / 60).ceil();
      final int minArrondiSup = minTrajet > 0
          ? arrondirAuQuartDHeureMinutes(minTrajet, toujoursPlusHaut: true)
          : 0;

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.blue.shade300, width: 1.0),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.directions_car,
                  color: Colors.blueAccent,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '🚗 Trajet : $chronoStr',
                        style: const TextStyle(
                          color: Colors.blueAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade700,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          minArrondiSup > 0
                              ? 'Payé : ${formatMinutes(minArrondiSup)} (1/4h)'
                              : '0 min',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 9.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'Départ à ${formatHeure(item['heure_depart_trajet'])}${pauseSec > 0 ? ' • Pause : ${formatSeconds(pauseSec)}' : ''}',
              style: TextStyle(color: Colors.blue.shade900, fontSize: 10.5),
            ),
          ],
        ),
      );
    } else if (statut == 'En pause') {
      final debutPauseStr = item['heure_debut_pause'] as String?;
      final debutPause = debutPauseStr != null
          ? DateTime.tryParse(debutPauseStr)
          : null;
      final int secCettePause = debutPause != null
          ? now.difference(debutPause).inSeconds.clamp(0, 864000)
          : 0;
      final chronoPauseStr = formatChrono(secCettePause);

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.orange.shade400, width: 1.0),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.pause_circle_filled,
              color: Colors.orange,
              size: 16,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '⏸️ Trajet en pause : $chronoPauseStr (depuis ${formatHeure(item['heure_debut_pause'])})',
                style: TextStyle(
                  color: Colors.orange.shade900,
                  fontWeight: FontWeight.bold,
                  fontSize: 11.5,
                ),
              ),
            ),
          ],
        ),
      );
    } else if (statut == 'Arrivé') {
      final arriveeStr = item['heure_arrivee_site'] as String?;
      int pauseChantierSec = (item['duree_pause_chantier_secondes'] is num)
          ? (item['duree_pause_chantier_secondes'] as num).toInt()
          : 0;
      final int chantierLiveSec = calculerSecondesEcoulees(
        arriveeStr,
        pauseSec: pauseChantierSec,
      );
      final chronoChantierStr = formatChrono(chantierLiveSec);
      final int minChantier = (chantierLiveSec / 60).ceil();
      final int minChantierArrondiSup = minChantier > 0
          ? arrondirAuQuartDHeureMinutes(minChantier, toujoursPlusHaut: true)
          : 0;

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.teal.shade50,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.teal.shade300, width: 1.0),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      color: Colors.teal,
                      size: 15,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Trajet: ${item['duree_trajet'] ?? '--'} (${item['distance_km'] ?? '--'})',
                      style: const TextStyle(
                        color: Colors.teal,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1.5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade700,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    'Chantier : ${formatMinutes(minChantierArrondiSup)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 9.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Row(
              children: [
                const Icon(Icons.handyman, color: Colors.teal, size: 15),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    '🏗️ Chantier : $chronoChantierStr (depuis ${formatHeure(item['heure_arrivee_site'])})',
                    style: TextStyle(
                      color: Colors.teal.shade900,
                      fontWeight: FontWeight.bold,
                      fontSize: 11.5,
                    ),
                  ),
                ),
              ],
            ),
            if (pauseChantierSec > 0) ...[
              const SizedBox(height: 2),
              Text(
                'Pause cumulée : ${formatSeconds(pauseChantierSec)}',
                style: TextStyle(
                  color: Colors.amber.shade900,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      );
    } else if (statut == 'Intervention en pause' ||
        item['en_pause_chantier'] == true) {
      final debutPauseStr = item['heure_debut_pause_chantier'] as String?;
      final debutPause = debutPauseStr != null
          ? DateTime.tryParse(debutPauseStr)
          : null;
      final int secCettePause = debutPause != null
          ? now.difference(debutPause).inSeconds.clamp(0, 864000)
          : 0;
      final chronoPauseStr = formatChrono(secCettePause);

      final motif = item['motif_pause_chantier'] as String?;
      final motifTxt = (motif != null && motif.isNotEmpty)
          ? ' • Motif : $motif'
          : '';
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.amber.shade500, width: 1.0),
        ),
        child: Row(
          children: [
            Icon(
              Icons.pause_circle_filled,
              color: Colors.amber.shade900,
              size: 16,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '⏸️ En pause : $chronoPauseStr$motifTxt',
                style: TextStyle(
                  color: Colors.amber.shade900,
                  fontWeight: FontWeight.bold,
                  fontSize: 11.5,
                ),
              ),
            ),
          ],
        ),
      );
    } else if (statut == 'En attente d\'approbation') {
      // Masquage automatique après 5 secondes si non déjà masqué ou planifié
      if (itemId.isNotEmpty && !_bandeauxMasques.contains(itemId) && !_timersMasquagePlanifies.contains(itemId)) {
        _timersMasquagePlanifies.add(itemId);
        Timer(const Duration(seconds: 5), () {
          if (mounted && !_bandeauxMasques.contains(itemId)) {
            setState(() => _bandeauxMasques.add(itemId));
          }
        });
      }

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.amber.shade700, width: 1.0),
        ),
        child: Row(
          children: [
            Icon(
              Icons.hourglass_top_rounded,
              color: Colors.amber.shade900,
              size: 15,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Rapport soumis • En attente approbation superviseur',
                style: TextStyle(
                  color: Colors.amber.shade900,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            InkWell(
              onTap: () => setState(() => _bandeauxMasques.add(itemId)),
              child: Icon(Icons.close, size: 14, color: Colors.amber.shade900),
            ),
          ],
        ),
      );
    } else if (statut == 'Complété') {
      // Masquage automatique après 5 secondes si non déjà masqué ou planifié
      if (itemId.isNotEmpty && !_bandeauxMasques.contains(itemId) && !_timersMasquagePlanifies.contains(itemId)) {
        _timersMasquagePlanifies.add(itemId);
        Timer(const Duration(seconds: 5), () {
          if (mounted && !_bandeauxMasques.contains(itemId)) {
            setState(() => _bandeauxMasques.add(itemId));
          }
        });
      }

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.green.shade300, width: 1.0),
        ),
        child: Row(
          children: [
            const Icon(Icons.verified, color: Colors.green, size: 15),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Trajet : ${item['duree_trajet'] ?? '--'} (${item['distance_km'] ?? '--'}) • Chantier : ${item['duree_chantier'] ?? '--'}',
                style: const TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            InkWell(
              onTap: () => setState(() => _bandeauxMasques.add(itemId)),
              child: const Icon(Icons.close, size: 14, color: Colors.green),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildActionButtons(Map<String, dynamic> item, int index) {
    final statut = item['statut'] ?? 'En attente';
    if (statut == 'En attente') {
      return Row(
        children: [
          Expanded(
            flex: 3,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.edit_note, size: 20),
              label: const Text(
                'Modifier l\'intervention',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo.shade800,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 1.5,
              ),
              onPressed: () => _ouvrirModifierIntervention(item, index),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: OutlinedButton.icon(
              icon: const Icon(
                Icons.event_available,
                size: 18,
                color: Colors.indigo,
              ),
              label: const Text(
                'Rendez-vous',
                style: TextStyle(
                  color: Colors.indigo,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                side: BorderSide(color: Colors.indigo.shade400, width: 1.2),
                backgroundColor: Colors.indigo.shade50.withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () => _ouvrirDialogueRendezVous(item),
            ),
          ),
          const SizedBox(width: 6),
          IconButton.filledTonal(
            icon: const Icon(Icons.navigation, size: 18),
            tooltip: 'Démarrer le Trajet (Déplacement)',
            style: IconButton.styleFrom(
              backgroundColor: Colors.blue.shade50,
              foregroundColor: Colors.blue.shade800,
              padding: const EdgeInsets.all(10),
            ),
            onPressed: () {
              final destination =
                  (item['adresse'] ??
                          item['adresse_intervention'] ??
                          item['nom_client'] ??
                          '')
                      .toString();
              demarrerTrajet(item['id']?.toString() ?? '', index, destination);
            },
          ),
          const SizedBox(width: 6),
          IconButton.filledTonal(
            icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
            tooltip: 'Supprimer l\'intervention',
            style: IconButton.styleFrom(
              backgroundColor: Colors.red.shade50,
              padding: const EdgeInsets.all(10),
            ),
            onPressed: () => _confirmerSuppressionIntervention(item),
          ),
        ],
      );
    } else if (statut == 'En route') {
      return Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.pause),
              label: const Text('Pause'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () => basculerPauseTrajet(item['id'], index),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.flag_circle),
              label: const Text('Arrivé'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () => marquerArrive(item['id'], index),
            ),
          ),
          const SizedBox(width: 6),
          IconButton.filledTonal(
            icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
            tooltip: 'Supprimer l\'intervention',
            style: IconButton.styleFrom(
              backgroundColor: Colors.red.shade50,
              padding: const EdgeInsets.all(10),
            ),
            onPressed: () => _confirmerSuppressionIntervention(item),
          ),
        ],
      );
    } else if (statut == 'En pause') {
      return Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: const Text('Reprendre'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () => basculerPauseTrajet(item['id'], index),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.flag_circle),
              label: const Text('Arrivé'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () => marquerArrive(item['id'], index),
            ),
          ),
          const SizedBox(width: 6),
          IconButton.filledTonal(
            icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
            tooltip: 'Supprimer l\'intervention',
            style: IconButton.styleFrom(
              backgroundColor: Colors.red.shade50,
              padding: const EdgeInsets.all(10),
            ),
            onPressed: () => _confirmerSuppressionIntervention(item),
          ),
        ],
      );
    } else if (statut == 'Arrivé') {
      return Row(
        children: [
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.pause, size: 18),
              label: const Text('Pause'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber.shade800,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () =>
                  _afficherDialoguePauseChantier(item['id'], index),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.assignment_turned_in, size: 18),
              label: const Text('Rapport / Clôture'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => RapportFormScreen(intervention: item),
                  ),
                );
                if (result != null) {
                  chargerInterventions();
                }
              },
            ),
          ),
          const SizedBox(width: 6),
          IconButton.filledTonal(
            icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
            tooltip: 'Supprimer l\'intervention',
            style: IconButton.styleFrom(
              backgroundColor: Colors.red.shade50,
              padding: const EdgeInsets.all(10),
            ),
            onPressed: () => _confirmerSuppressionIntervention(item),
          ),
        ],
      );
    } else if (statut == 'Intervention en pause' ||
        item['en_pause_chantier'] == true) {
      return Row(
        children: [
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.play_arrow, size: 18),
              label: const Text('Reprendre'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () => basculerPauseIntervention(item['id'], index),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.assignment_turned_in, size: 18),
              label: const Text('Rapport / Clôture'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueGrey,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => RapportFormScreen(intervention: item),
                  ),
                );
                if (result != null) {
                  chargerInterventions();
                }
              },
            ),
          ),
          const SizedBox(width: 6),
          IconButton.filledTonal(
            icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
            tooltip: 'Supprimer l\'intervention',
            style: IconButton.styleFrom(
              backgroundColor: Colors.red.shade50,
              padding: const EdgeInsets.all(10),
            ),
            onPressed: () => _confirmerSuppressionIntervention(item),
          ),
        ],
      );
    } else if (statut == 'En attente d\'approbation') {
      return Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.approval, size: 20),
              label: const Text(
                'Consulter / Approuver (Superviseur)',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber.shade900,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        RapportDetailScreen(intervention: item),
                  ),
                );
                if (mounted) setState(() {});
              },
            ),
          ),
          const SizedBox(width: 6),
          IconButton.filledTonal(
            icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
            tooltip: 'Supprimer l\'intervention',
            style: IconButton.styleFrom(
              backgroundColor: Colors.red.shade50,
              padding: const EdgeInsets.all(10),
            ),
            onPressed: () => _confirmerSuppressionIntervention(item),
          ),
        ],
      );
    } else {
      // Complété
      final aSignature = aSignatureClient(item);
      return Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.receipt_long),
              label: const Text('Consulter le Rapport'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        RapportDetailScreen(intervention: item),
                  ),
                );
                if (mounted) setState(() {});
              },
            ),
          ),
          const SizedBox(width: 6),
          if (!aSignature) ...[
            IconButton.filledTonal(
              icon: const Icon(Icons.send_to_mobile, size: 18, color: Color(0xFFD1001F)),
              tooltip: 'Lien signature client à distance',
              style: IconButton.styleFrom(
                backgroundColor: Colors.red.shade50,
                padding: const EdgeInsets.all(10),
              ),
              onPressed: () => SignatureDistanceService.afficherDialoguePartage(
                context,
                intervention: item,
                onTokenGenere: () => setState(() {}),
              ),
            ),
            const SizedBox(width: 6),
          ],
          IconButton.filledTonal(
            icon: const Icon(Icons.archive_outlined, size: 18, color: Color(0xFF455A64)),
            tooltip: 'Archiver l\'intervention complétée',
            style: IconButton.styleFrom(
              backgroundColor: Colors.blueGrey.shade50,
              padding: const EdgeInsets.all(10),
            ),
            onPressed: () => _archiverIntervention(item),
          ),
          const SizedBox(width: 6),
          IconButton.filledTonal(
            icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
            tooltip: 'Supprimer l\'intervention',
            style: IconButton.styleFrom(
              backgroundColor: Colors.red.shade50,
              padding: const EdgeInsets.all(10),
            ),
            onPressed: () => _confirmerSuppressionIntervention(item),
          ),
        ],
      );
    }
  }

  Future<void> _ouvrirGestionPhotosIntervention(
    Map<String, dynamic> item,
  ) async {
    final bool estApprouve = estRapportApprouve(item);
    await WidgetPhotosChantier.afficherDialogue(
      context,
      intervention: item,
      lectureSeule: estApprouve,
      onPhotosModifiees: () async {
        // 1. Sauvegarder dans Supabase
        try {
          final supabase = Supabase.instance.client;
          await supabase
              .from('interventions')
              .update({'photos': item['photos']})
              .eq('id', item['id']);
        } catch (e) {
          debugPrint('Erreur mise à jour photos Supabase: $e');
        }

        // 2. Synchroniser localement
        try {
          await FeuilleDeTempsRepository.instance.synchroniserIntervention(
            item,
          );
        } catch (_) {}

        // 3. Regénérer le PDF si un rapport existe déjà ou en attente d'approbation
        if (item['rapport_pdf_path'] != null ||
            item['statut'] == 'En attente d\'approbation') {
          try {
            final nouveauPdfPath =
                await RapportPdfService.genererEtSauvegarderAutomatiquement(
                  intervention: item,
                  getNumeroDossier: getNumeroDossier,
                  getDossierPhotos: getDossierPhotos,
                  formatSeconds: formatSeconds,
                  formatHeure: formatHeure,
                );
            if (nouveauPdfPath != null) {
              item['rapport_pdf_path'] = nouveauPdfPath;
            }
          } catch (e) {
            debugPrint('Erreur actualisation auto PDF photos: $e');
          }
        }

        if (mounted) setState(() {});
      },
    );
  }

  Future<void> _ouvrirGestionNotesIntervention(
    Map<String, dynamic> item,
  ) async {
    final bool estApprouve = estRapportApprouve(item);
    await WidgetPhotosChantier.afficherDialogueNotesDeService(
      context,
      intervention: item,
      lectureSeule: estApprouve,
      onNotesSauvegardees: (nouvellesNotes) async {
        setNotesDeService(item, nouvellesNotes);

        // 1. Sauvegarder dans Supabase
        try {
          final supabase = Supabase.instance.client;
          await supabase
              .from('interventions')
              .update({'notes': item['notes']})
              .eq('id', item['id']);
        } catch (e) {
          debugPrint('Erreur mise à jour notes Supabase: $e');
        }

        // 2. Synchroniser localement
        try {
          await FeuilleDeTempsRepository.instance.synchroniserIntervention(
            item,
          );
        } catch (_) {}

        // 3. Regénérer le PDF si un rapport existe déjà ou en attente d'approbation
        if (item['rapport_pdf_path'] != null ||
            item['statut'] == 'En attente d\'approbation') {
          try {
            final nouveauPdfPath =
                await RapportPdfService.genererEtSauvegarderAutomatiquement(
                  intervention: item,
                  getNumeroDossier: getNumeroDossier,
                  getDossierPhotos: getDossierPhotos,
                  formatSeconds: formatSeconds,
                  formatHeure: formatHeure,
                );
            if (nouveauPdfPath != null) {
              item['rapport_pdf_path'] = nouveauPdfPath;
            }
          } catch (e) {
            debugPrint('Erreur actualisation auto PDF notes: $e');
          }
        }

        if (mounted) {
          setState(() {});
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Notes de service enregistrées avec succès.'),
              backgroundColor: Colors.indigo,
            ),
          );
        }
      },
    );
  }

  /// 🔩 Enregistre la liste des pièces sur l'intervention (Supabase + local)
  Future<void> _sauvegarderPiecesIntervention(
    Map<String, dynamic> item,
    List<Map<String, dynamic>> pieces,
  ) async {
    item['pieces_utilisees'] = jsonEncode(pieces);
    if (mounted) setState(() {});
    try {
      await supabase
          .from('interventions')
          .update({
            'pieces_utilisees': item['pieces_utilisees'],
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', item['id']);
    } catch (e) {
      debugPrint('Erreur mise à jour pièces Supabase: $e');
    }
    try {
      await FeuilleDeTempsRepository.instance.synchroniserIntervention(item);
    } catch (_) {}
  }

  Future<void> _ouvrirGestionPiecesIntervention(
    Map<String, dynamic> item,
  ) async {
    final bool lectureSeule = estRapportApprouve(item);
    final pieces = getPiecesUtilisees(item);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) {
          Future<void> maj() async {
            setSheet(() {});
            await _sauvegarderPiecesIntervention(item, pieces);
          }

          void ajouter() {
            showModalBottomSheet(
              context: sheetCtx,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => SelecteurPiecesModal(
                camionInitial: item['numero_camion'] as String?,
                technicienInitial: item['nom_technicien'] as String?,
                onPieceSelected: (ArticleCamion article) {
                  final i = pieces.indexWhere(
                    (p) =>
                        p['ref'] == article.ref &&
                        (p['camion'] ?? '') == article.camion,
                  );
                  if (i >= 0) {
                    pieces[i]['utilise'] = (pieces[i]['utilise'] as int) + 1;
                  } else {
                    pieces.add(article.toMap(utilise: 1));
                  }
                  maj();
                },
              ),
            );
          }

          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetCtx).size.height * 0.75,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 6),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                    child: Row(
                      children: [
                        const Icon(Icons.build_circle, color: Color(0xFFD1001F)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Pièces utilisées',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '${item['nom_client'] ?? ''} • ${item['numero_commande'] ?? ''}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(sheetCtx),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 8),
                  Flexible(
                    child: pieces.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.inventory_2_outlined,
                                  size: 40,
                                  color: Colors.grey.shade400,
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Aucune pièce ajoutée pour cette intervention.',
                                  style: TextStyle(color: Colors.black54),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            itemCount: pieces.length,
                            itemBuilder: (_, i) {
                              final p = pieces[i];
                              final utilise = p['utilise'] as int;
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.red.shade200),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${p['ref']}  ${p['camion'] ?? ''}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.indigo.shade800,
                                            ),
                                          ),
                                          Text(
                                            p['nom'] as String,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (!lectureSeule)
                                      IconButton(
                                        icon: const Icon(
                                          Icons.remove_circle_outline,
                                          color: Colors.redAccent,
                                        ),
                                        onPressed: utilise > 1
                                            ? () {
                                                p['utilise'] = utilise - 1;
                                                maj();
                                              }
                                            : null,
                                      ),
                                    Text(
                                      '$utilise ${p['unite']}',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.red.shade700,
                                      ),
                                    ),
                                    if (!lectureSeule) ...[
                                      IconButton(
                                        icon: const Icon(
                                          Icons.add_circle_outline,
                                          color: Colors.green,
                                        ),
                                        onPressed: () {
                                          p['utilise'] = utilise + 1;
                                          maj();
                                        },
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          color: Colors.grey,
                                        ),
                                        tooltip: 'Retirer',
                                        onPressed: () {
                                          pieces.removeAt(i);
                                          maj();
                                        },
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                  if (!lectureSeule)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: ajouter,
                          icon: const Icon(Icons.add_shopping_cart, size: 18),
                          label: const Text('Ajouter une pièce du camion'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo.shade600,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (mounted) setState(() {});
  }

  Widget _buildBarreOutilsIntervention(Map<String, dynamic> item, int idx) {
    final photos = getPhotosIntervention(item);
    final notesService = getNotesDeService(item);
    final nbPieces = getPiecesUtilisees(item)
        .fold<int>(0, (s, p) => s + (p['utilise'] as int));

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          // Bouton Photos
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: photos.isNotEmpty
                    ? Colors.indigo
                    : Colors.blueGrey.shade800,
                side: BorderSide(
                  color: photos.isNotEmpty
                      ? Colors.indigo.shade400
                      : Colors.grey.shade400,
                  width: photos.isNotEmpty ? 1.2 : 1.0,
                ),
                backgroundColor: photos.isNotEmpty
                    ? Colors.indigo.shade50
                    : Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              icon: Icon(
                photos.isNotEmpty ? Icons.photo_library : Icons.add_a_photo,
                size: 16,
                color: photos.isNotEmpty ? Colors.indigo : Colors.blueGrey,
              ),
              label: Text(
                photos.isNotEmpty
                    ? '📸 Photos (${photos.length})'
                    : '📸 + Photo',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onPressed: () => _ouvrirGestionPhotosIntervention(item),
            ),
          ),
          const SizedBox(width: 8),
          // Bouton Pièces
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: nbPieces > 0
                    ? Colors.red.shade900
                    : Colors.blueGrey.shade800,
                side: BorderSide(
                  color: nbPieces > 0
                      ? Colors.red.shade300
                      : Colors.grey.shade400,
                  width: nbPieces > 0 ? 1.2 : 1.0,
                ),
                backgroundColor:
                    nbPieces > 0 ? Colors.red.shade50 : Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              icon: Icon(
                Icons.build_circle_outlined,
                size: 16,
                color: nbPieces > 0 ? Colors.red.shade800 : Colors.blueGrey,
              ),
              label: Text(
                nbPieces > 0 ? '🔩 Pièces ($nbPieces)' : '🔩 + Pièce',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              onPressed: () => _ouvrirGestionPiecesIntervention(item),
            ),
          ),
          const SizedBox(width: 8),
          // Bouton Notes de service
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: notesService.isNotEmpty
                    ? Colors.teal.shade900
                    : Colors.blueGrey.shade800,
                side: BorderSide(
                  color: notesService.isNotEmpty
                      ? Colors.teal.shade500
                      : Colors.grey.shade400,
                  width: notesService.isNotEmpty ? 1.2 : 1.0,
                ),
                backgroundColor: notesService.isNotEmpty
                    ? Colors.teal.shade50
                    : Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              icon: Icon(
                notesService.isNotEmpty
                    ? Icons.assignment_outlined
                    : Icons.note_add_outlined,
                size: 16,
                color: notesService.isNotEmpty
                    ? Colors.teal.shade800
                    : Colors.blueGrey,
              ),
              label: Text(
                notesService.isNotEmpty
                    ? '📝 Notes (${notesService.length > 15 ? '${notesService.substring(0, 12)}...' : notesService})'
                    : '📝 + Notes service',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              onPressed: () => _ouvrirGestionNotesIntervention(item),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final actives = interventions.where((i) => !estInterventionArchivee(i)).toList();
    final nbArchives = interventions.where((i) => estInterventionArchivee(i)).length;

    final listeAffichee = filtreTechnicien == null
        ? actives
        : actives
              .where((i) => i['nom_technicien'] == filtreTechnicien)
              .toList();

    return Scaffold(
      appBar: RaycoWylieHeaderAppBar(
        sousTitre: 'Agenda du Jour • Systèmes de grues & interventions',
        nbArchives: nbArchives,
        onArchives: _ouvrirEcranArchives,
        onFeuilleDeTemps: () async {
          await FeuilleDeTempsRepository.instance.synchroniserInterventions(
            interventions,
          );
          if (!context.mounted) return;
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => FeuilleDeTempsScreen(
                technicienInitial: filtreTechnicien != 'Tous'
                    ? filtreTechnicien
                    : null,
              ),
            ),
          );
          if (mounted) {
            await chargerInterventions();
            setState(() {});
          }
        },
        onGestionTechniciens: ouvrirGestionTechniciens,
        onInventaire: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const InventaireScreen()),
        ),
        onDepenses: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const DepenseScreen()),
        ),
        onBilletsService: () async {
          final uri = Uri.parse('http://localhost:8080/billet_service.html');
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } else {
            final fileUri = Uri.file(
              '${Directory.current.path}/web/billet_service.html',
            );
            await launchUrl(fileUri, mode: LaunchMode.externalApplication);
          }
        },
        onNouvelleIntervention: ouvrirNouvelleIntervention,
        onActualiser: chargerInterventions,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                HorodateurBanniereWidget(
                  onRefresh: () => setState(() {}),
                  technicien: filtreTechnicien != 'Tous'
                      ? filtreTechnicien
                      : null,
                ),
                _buildBarreFiltreSuperviseur(),
                Expanded(
                  child: listeAffichee.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.assignment_outlined,
                                  size: 64,
                                  color: Colors.blueAccent.withValues(
                                    alpha: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  filtreTechnicien != null
                                      ? 'Aucune intervention assignée à $filtreTechnicien'
                                      : 'Aucune intervention pour aujourd\'hui',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Utilisez le bouton + en haut à droite pour créer une intervention.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.grey),
                                ),
                                const SizedBox(height: 20),
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.add),
                                  label: const Text(
                                    'Ajouter une intervention en chantier',
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blueAccent,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 12,
                                    ),
                                  ),
                                  onPressed: ouvrirNouvelleIntervention,
                                ),
                                const SizedBox(height: 10),
                                TextButton.icon(
                                  icon: const Icon(
                                    Icons.restore,
                                    size: 16,
                                    color: Colors.grey,
                                  ),
                                  label: const Text(
                                    'Restaurer les 3 interventions de démonstration',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),
                                  onPressed: () async {
                                    await insererDonneesInitialesSupabase();
                                  },
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: listeAffichee.length,
                          itemBuilder: (context, index) {
                            final item = listeAffichee[index];
                            final realIndex = interventions.indexWhere(
                              (i) => i['id'] == item['id'],
                            );
                            final idx = realIndex != -1 ? realIndex : index;
                            final nomContact = (item['nom_contact'] ?? '')
                                .toString()
                                .trim();
                            final telephoneContact = (item['telephone'] ?? '')
                                .toString()
                                .trim();

                            return Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              elevation: 3,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: Colors.grey.shade300,
                                  width: 0.8,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // ─── EN-TÊTE : STATUT + NOM DU CONTACT + TECHNICIEN & CAMION ───
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 3,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: _getStatusColor(
                                                  item['statut'],
                                                ).withValues(alpha: 0.15),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                item['statut'] ?? 'En attente',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                  color: _getStatusColor(
                                                    item['statut'],
                                                  ),
                                                ),
                                              ),
                                            ),
                                            if (nomContact.isNotEmpty) ...[
                                              const SizedBox(width: 6),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 3,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color:
                                                      Colors.blueGrey.shade50,
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                  border: Border.all(
                                                    color: Colors
                                                        .blueGrey
                                                        .shade200,
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      Icons.person_pin,
                                                      size: 13,
                                                      color: Colors
                                                          .blueGrey
                                                          .shade800,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      telephoneContact
                                                              .isNotEmpty
                                                          ? '$nomContact ($telephoneContact)'
                                                          : nomContact,
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: Colors
                                                            .blueGrey
                                                            .shade900,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            // Badge Technicien & Camion
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 3,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.indigo.shade50,
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                                border: Border.all(
                                                  color: Colors.indigo.shade200,
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(
                                                    Icons.person,
                                                    size: 13,
                                                    color: Colors.indigo,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    '${item['nom_technicien'] ?? 'Non assigné'} • ${item['numero_camion'] ?? 'Camion #101'}',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors
                                                          .indigo
                                                          .shade900,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 2),
                                            Tooltip(
                                              message:
                                                  'Modifier l\'intervention',
                                              child: InkWell(
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                                onTap: () =>
                                                    _ouvrirModifierIntervention(
                                                      item,
                                                      idx,
                                                    ),
                                                child: Padding(
                                                  padding: const EdgeInsets.all(
                                                    4,
                                                  ),
                                                  child: Icon(
                                                    Icons.edit_outlined,
                                                    size: 18,
                                                    color:
                                                        Colors.indigo.shade700,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 2),
                                            Tooltip(
                                              message:
                                                  'Supprimer l\'intervention',
                                              child: InkWell(
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                                onTap: () =>
                                                    _confirmerSuppressionIntervention(
                                                      item,
                                                    ),
                                                child: Padding(
                                                  padding: const EdgeInsets.all(
                                                    4,
                                                  ),
                                                  child: Icon(
                                                    Icons.delete_outline,
                                                    size: 18,
                                                    color: Colors.red.shade700,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),

                                    // ─── NOM DU CLIENT ──────────────────────────────
                                    Text(
                                      item['nom_client'] ?? '',
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    // Badges Commande, Bon de commande (#PO) et Référence (TF)
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: [
                                        if (item['numero_commande'] != null &&
                                            (item['numero_commande'] as String)
                                                .isNotEmpty)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade100,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              border: Border.all(
                                                color: Colors.grey.shade300,
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  Icons.tag,
                                                  size: 11,
                                                  color: Colors.blueGrey,
                                                ),
                                                const SizedBox(width: 3),
                                                Text(
                                                  'Cmd: ${item['numero_commande']}',
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.blueGrey,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        if (item['numero_bon_commande'] !=
                                                null &&
                                            (item['numero_bon_commande']
                                                    as String)
                                                .isNotEmpty)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.teal.shade50,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              border: Border.all(
                                                color: Colors.teal.shade300,
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.receipt,
                                                  size: 11,
                                                  color: Colors.teal.shade800,
                                                ),
                                                const SizedBox(width: 3),
                                                Text(
                                                  'PO: ${item['numero_bon_commande']}',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.teal.shade900,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        if (item['numero_reference'] != null &&
                                            (item['numero_reference'] as String)
                                                .isNotEmpty)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.blue.shade50,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              border: Border.all(
                                                color: Colors.blue.shade300,
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.bookmark_outline,
                                                  size: 11,
                                                  color: Colors.blue.shade800,
                                                ),
                                                const SizedBox(width: 3),
                                                Text(
                                                  'Réf: ${item['numero_reference']}',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.blue.shade900,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),

                                    // ─── LE TROUBLE SIGNALÉ (EN ÉVIDENCE) ────────────
                                    if (item['trouble'] != null &&
                                        (item['trouble'] as String)
                                            .trim()
                                            .isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.amber.shade50,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: Colors.amber.shade400,
                                            width: 1.2,
                                          ),
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Icon(
                                              Icons.report_problem_rounded,
                                              color: Colors.amber.shade900,
                                              size: 18,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'LE TROUBLE :',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color:
                                                          Colors.amber.shade900,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    item['trouble'] as String,
                                                    style: TextStyle(
                                                      fontSize: 12.5,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color:
                                                          Colors.brown.shade900,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],

                                    // ─── RENDEZ-VOUS PLANIFIÉ (CALENDRIER) ────────────
                                    if (item['date_rendez_vous'] != null &&
                                        (item['date_rendez_vous'] as String)
                                            .isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 7,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.indigo.shade50,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: Colors.indigo.shade200,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.event_available,
                                              size: 18,
                                              color: Colors.indigo.shade800,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Rendez-vous : ${item['date_rendez_vous']} à ${item['heure_rendez_vous'] ?? '08:30'} (~${item['duree_minutes'] ?? 120} min)',
                                                    style: TextStyle(
                                                      color: Colors
                                                          .indigo
                                                          .shade900,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 12.5,
                                                    ),
                                                  ),
                                                  if ((item['telephone'] !=
                                                              null &&
                                                          (item['telephone']
                                                                  as String)
                                                              .isNotEmpty) ||
                                                      (item['nom_contact'] !=
                                                              null &&
                                                          (item['nom_contact']
                                                                  as String)
                                                              .isNotEmpty))
                                                    Text(
                                                      'Contact sur place : ${(item['nom_contact'] != null && (item['nom_contact'] as String).isNotEmpty) ? '${item['nom_contact']} • ' : ''}${item['telephone'] ?? ''}',
                                                      style: TextStyle(
                                                        color: Colors
                                                            .indigo
                                                            .shade700,
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                            OutlinedButton.icon(
                                              icon: const Icon(
                                                Icons.share,
                                                size: 13,
                                                color: Colors.indigo,
                                              ),
                                              label: const Text(
                                                'Fichier .ics',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.indigo,
                                                ),
                                              ),
                                              style: OutlinedButton.styleFrom(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4,
                                                    ),
                                                side: BorderSide(
                                                  color: Colors.indigo.shade300,
                                                ),
                                                backgroundColor: Colors.white,
                                                minimumSize: Size.zero,
                                                tapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                              ),
                                              onPressed: () =>
                                                  _ouvrirDialogueRendezVous(
                                                    item,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],

                                    // ─── FACTURATION & CHANTIER ─────────────────────
                                    if (item['adresse_facturation'] != null &&
                                        (item['adresse_facturation'] as String)
                                            .trim()
                                            .isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Icon(
                                            Icons.receipt_long,
                                            color: Colors.indigo,
                                            size: 15,
                                          ),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              'Facturation : ${item['adresse_facturation']}',
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
                                    const SizedBox(height: 4),
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Icon(
                                          Icons.location_on,
                                          color: Colors.grey,
                                          size: 15,
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            'Chantier : ${item['adresse'] ?? ''}',
                                            style: const TextStyle(
                                              color: Colors.grey,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),

                                    // Machine & Équipement
                                    if (item['type_machine'] != null &&
                                        (item['type_machine'] as String)
                                            .trim()
                                            .isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Icon(
                                            Icons.precision_manufacturing,
                                            size: 14,
                                            color: Colors.blueGrey,
                                          ),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              'Machine : ${item['type_machine']}'
                                              '${(item['marque'] != null && (item['marque'] as String).isNotEmpty) ? ' • ${item['marque']} ${item['modele'] ?? ''}' : ''}'
                                              '${(item['numero_unite'] != null && (item['numero_unite'] as String).isNotEmpty) ? ' • Unité: ${item['numero_unite']}' : ''}'
                                              '${(item['numero_serie_machine'] != null && (item['numero_serie_machine'] as String).isNotEmpty) ? ' • S/N: ${item['numero_serie_machine']}' : ''}'
                                              '${(item['systeme_wylie'] != null && (item['systeme_wylie'] as String).isNotEmpty) ? ' (${item['systeme_wylie']})' : ''}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.blueGrey.shade800,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],

                                    const SizedBox(height: 10),
                                    _buildStatusBanner(item),
                                    _buildBarreOutilsIntervention(item, idx),
                                    const Divider(height: 16),
                                    _buildActionButtons(item, idx),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
