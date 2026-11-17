import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_helpers.dart';
import 'inventaire_donnees.dart';
import 'cloture_screen.dart';
import 'widget_photos_chantier.dart';

// ==========================================
// 📝 ÉCRAN : FORMULAIRE DU RAPPORT D'INTERVENTION
// ==========================================
class RapportFormScreen extends StatefulWidget {
  final Map<String, dynamic> intervention;
  const RapportFormScreen({super.key, required this.intervention});

  @override
  State<RapportFormScreen> createState() => _RapportFormScreenState();
}

class _RapportFormScreenState extends State<RapportFormScreen> {
  final _formKey = GlobalKey<FormState>();

  // ─── Numéro de rapport ───────────────────────────────────────────────
  late final String _numeroRapport;

  // ─── Informations client ─────────────────────────────────────────────
  final _adresseFactCtrl  = TextEditingController();
  final _adresseIntCtrl   = TextEditingController();
  final _contactCtrl      = TextEditingController();
  final _telephoneCtrl    = TextEditingController();
  final _courrielCtrl     = TextEditingController();
  final _bonCommandeCtrl  = TextEditingController();
  final _dateChantierCtrl = TextEditingController();
  final _technicienCtrl   = TextEditingController();
  final _numCommandeCtrl  = TextEditingController(); // CO-XXXXX
  final _numRefCtrl       = TextEditingController(); // TF-XXXXX

  // ─── Type d'intervention ─────────────────────────────────────────────
  String? _typeIntervention;
  final List<String> _typesIntervention = [
    'Calibration', 'Certification', 'Formation',
    'Inspection', 'Installation', 'Réparation', 'Autre',
  ];

  // ─── Machine ─────────────────────────────────────────────────────────
  String? _typeMachine;
  final List<String> _typesMachine = kTypesMachineRayco;
  final _marqueCtrl         = TextEditingController();
  final _modeleCtrl         = TextEditingController();
  final _anneeCtrl          = TextEditingController();
  final _serieCtrl          = TextEditingController();
  final _uniteCtrl          = TextEditingController();

  String? _alimentation; // 12v / 24v

  // ─── Système installé ────────────────────────────────────────────────
  final _numProduitCtrl     = TextEditingController();
  final _serieSystemeCtrl   = TextEditingController();
  final _versionLogicielCtrl = TextEditingController();
  final _engrenageCtrl      = TextEditingController();
  final _bypassCtrl         = TextEditingController();
  final _notesCtrl          = TextEditingController();

  // ─── Inventaire pièces utilisées ─────────────────────────────────────
  final List<Map<String, dynamic>> _piecesChoisies = [];

  // ─── Contrôles de sécurité & conformité (RaycoWylie) ─────────────────
  List<String> _controlesSecurite = [];

  // ─── Chronomètre temps facturable en direct (Trajet Aller + Chantier + Trajet Retour) ─────
  Timer? _liveTimer;
  late final DateTime _debutRedaction;

  // ─── Déplacement retour (estimé par défaut = aller, ajustable) ─────
  int _secondesRetour = 0;
  final _distanceRetourCtrl = TextEditingController();
  bool _retourAjusteManuellement = false;

  // 1. Déplacement ALLER (arrondi au quart d'heure supérieur)
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

  // 2. Chantier & Rédaction en direct (jusqu'à la signature)
  int get _secondesChantierLive {
    final arriveeStr = (widget.intervention['heure_arrivee_site'] ?? _debutRedaction.toIso8601String()) as String?;
    int pauseChantierSec = (widget.intervention['duree_pause_chantier_secondes'] is num)
        ? (widget.intervention['duree_pause_chantier_secondes'] as num).toInt()
        : 0;
    if (_estEnPause && widget.intervention['heure_debut_pause_chantier'] != null) {
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

  // 3. Déplacement RETOUR (estimé au même temps et même distance que l'aller, ou ajusté)
  int get _secondesRetourFinal {
    if (_retourAjusteManuellement) return _secondesRetour;
    final aller = _secondesTrajetAller;
    return aller > 0 ? aller : _secondesRetour;
  }

  // 4. TOTAL FACTURABLE GLOBAL (Aller + Chantier/Rédaction + Retour)
  int get _secondesTotalFacturable =>
      _secondesTrajetAller + _secondesChantierArrondi + _secondesRetourFinal;

  String _formatChrono(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  void initState() {
    super.initState();
    _numeroRapport = genererNumeroRapport();
    _debutRedaction = DateTime.now().toUtc();
    widget.intervention['heure_debut_redaction_rapport'] ??= _debutRedaction.toIso8601String();

    // Démarrage du chronomètre en direct rafraîchi chaque seconde
    _liveTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });

    final it = widget.intervention;

    // Initialisation du trajet de retour (estimé par défaut = aller)
    final trajetSec = (it['duree_trajet_secondes'] is num)
        ? (it['duree_trajet_secondes'] as num).toInt()
        : dureeChaineVersSecondes(it['duree_trajet']);
    if (it['duree_retour_secondes'] is num && (it['duree_retour_secondes'] as num) > 0) {
      _secondesRetour = (it['duree_retour_secondes'] as num).toInt();
      _retourAjusteManuellement = it['retour_ajuste'] == true;
    } else if (it['duree_retour'] != null) {
      _secondesRetour = dureeChaineVersSecondes(it['duree_retour']);
      _retourAjusteManuellement = it['retour_ajuste'] == true;
    } else {
      _secondesRetour = trajetSec > 0 ? trajetSec : 0;
    }

    final distAller = (it['distance_km'] ?? '').toString();
    final distRetour = (it['distance_retour_km'] ?? distAller).toString();
    _distanceRetourCtrl.text = distRetour;

    // Pré-remplir certains champs si disponibles
    _technicienCtrl.text = it['nom_technicien'] ?? '';
    _adresseIntCtrl.text = it['adresse'] ?? '';
    _adresseFactCtrl.text = it['adresse_facturation'] ?? it['adresse'] ?? '';
    _numCommandeCtrl.text = it['numero_commande'] ?? '';
    _numRefCtrl.text = it['numero_reference'] ?? '';
    _bonCommandeCtrl.text = it['numero_bon_commande'] ?? '';
    _contactCtrl.text = it['nom_contact'] ?? '';
    _telephoneCtrl.text = it['telephone'] ?? '';
    _courrielCtrl.text = it['courriel'] ?? '';
    _marqueCtrl.text = it['marque'] ?? '';
    _modeleCtrl.text = it['modele'] ?? '';
    _anneeCtrl.text = it['annee'] ?? '';
    _serieCtrl.text = it['numero_serie_machine'] ?? '';
    _uniteCtrl.text = it['numero_unite'] ?? '';
    _serieSystemeCtrl.text = it['systeme_wylie'] ?? it['numero_serie_systeme'] ?? '';
    if (it['alimentation'] != null && it['alimentation'].toString().isNotEmpty) {
      _alimentation = it['alimentation'].toString();
    }
    if (it['type_machine'] != null && it['type_machine'].toString().isNotEmpty) {
      final t = it['type_machine'].toString();
      _typeMachine = _typesMachine.contains(t) ? t : (_typesMachine.isNotEmpty ? _typesMachine.first : null);
    }
    final now = DateTime.now();
    _dateChantierCtrl.text =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    // Initialisation des contrôles de sécurité effectivement cochés
    _controlesSecurite = getControlesSecurite(it);

    // Initialisation des notes de service
    _notesCtrl.text = getNotesDeService(it);

    // Pièces déjà ajoutées pendant l'intervention (page principale)
    _piecesChoisies.addAll(getPiecesUtilisees(it));
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    _distanceRetourCtrl.dispose();
    _notesCtrl.dispose();
    for (final c in [
      _adresseFactCtrl, _adresseIntCtrl, _contactCtrl, _telephoneCtrl,
      _courrielCtrl, _bonCommandeCtrl, _dateChantierCtrl, _technicienCtrl,
      _numCommandeCtrl, _numRefCtrl, _marqueCtrl, _modeleCtrl, _anneeCtrl,
      _serieCtrl, _uniteCtrl, _numProduitCtrl, _serieSystemeCtrl, _versionLogicielCtrl,
      _engrenageCtrl, _bypassCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  List<Map<String, dynamic>> get _piecesUtilisees =>
      _piecesChoisies.where((p) => (p['utilise'] as int) > 0).toList();

  void _ouvrirSelecteurPieces() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SelecteurPiecesModal(
        camionInitial: widget.intervention['numero_camion'] as String?,
        technicienInitial: widget.intervention['nom_technicien'] as String?,
        onPieceSelected: (ArticleCamion article) {
          setState(() {
            final existIdx = _piecesChoisies.indexWhere((p) =>
                p['ref'] == article.ref &&
                (p['camion'] ?? '') == article.camion);
            if (existIdx >= 0) {
              final act = _piecesChoisies[existIdx]['utilise'] as int;
              _piecesChoisies[existIdx]['utilise'] = act + 1;
            } else {
              _piecesChoisies.add(article.toMap(utilise: 1));
            }
          });
        },
      ),
    );
  }

  Future<void> _continuerVersSignature() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Veuillez remplir tous les champs obligatoires.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final distRetour = _distanceRetourCtrl.text.trim().isNotEmpty
        ? _distanceRetourCtrl.text.trim()
        : (widget.intervention['distance_km'] ?? '--').toString();

    // Enrichir l'objet intervention avec toutes les infos du formulaire
    final extraData = <String, dynamic>{
      'numero_rapport': _numeroRapport,
      'adresse_facturation': _adresseFactCtrl.text.trim(),
      'adresse_intervention': _adresseIntCtrl.text.trim(),
      'nom_contact': _contactCtrl.text.trim(),
      'telephone': _telephoneCtrl.text.trim(),
      'courriel': _courrielCtrl.text.trim(),
      'numero_bon_commande': _bonCommandeCtrl.text.trim(),
      'date_chantier': _dateChantierCtrl.text.trim(),
      'nom_technicien': _technicienCtrl.text.trim(),
      'numero_commande': _numCommandeCtrl.text.trim(),
      'numero_reference': _numRefCtrl.text.trim(),
      'type_intervention': _typeIntervention ?? '',
      'type_machine': _typeMachine ?? '',
      'marque': _marqueCtrl.text.trim(),
      'modele': _modeleCtrl.text.trim(),
      'annee': _anneeCtrl.text.trim(),
      'numero_serie_machine': _serieCtrl.text.trim(),
      'numero_unite': _uniteCtrl.text.trim(),
      'alimentation': _alimentation ?? '',
      'numero_produit': _numProduitCtrl.text.trim(),
      'numero_serie_systeme': _serieSystemeCtrl.text.trim(),
      'version_logiciel': _versionLogicielCtrl.text.trim(),
      'engrenage': _engrenageCtrl.text.trim(),
      'position_bypass': _bypassCtrl.text.trim(),
      'pieces_utilisees': jsonEncode(_piecesUtilisees),
      'controles_securite': jsonEncode(_controlesSecurite),
      // Données de déplacement retour et facturation globale certifiée
      'duree_retour': formatSeconds(_secondesRetourFinal),
      'duree_retour_secondes': _secondesRetourFinal,
      'distance_retour_km': distRetour,
      'retour_ajuste': _retourAjusteManuellement,
      'duree_totale_facturable': formatSeconds(_secondesTotalFacturable),
      'duree_totale_facturable_secondes': _secondesTotalFacturable,
    };

    // Ajout d'une trace retour, contrôles et notes pour persistance Supabase
    setNotesDeService(widget.intervention, _notesCtrl.text.trim());
    final existingNotes = (widget.intervention['notes'] ?? '').toString();
    final retourTag = '[RETOUR: ${formatSeconds(_secondesRetourFinal)} | $distRetour]';
    final controlesTag = '[CONTROLES: ${jsonEncode(_controlesSecurite)}]';
    String notesMaj = existingNotes;
    if (!notesMaj.contains('[RETOUR:')) {
      notesMaj = notesMaj.isEmpty ? retourTag : '$notesMaj\n$retourTag';
    } else {
      notesMaj = notesMaj.replaceAll(RegExp(r'\[RETOUR:[^\]]+\]'), retourTag);
    }
    if (!notesMaj.contains('[CONTROLES:')) {
      notesMaj = '$notesMaj\n$controlesTag'.trim();
    } else {
      notesMaj = notesMaj.replaceAll(RegExp(r'\[CONTROLES:[^\]]+\]'), controlesTag);
    }
    extraData['notes'] = notesMaj;
    extraData['photos'] = widget.intervention['photos'];

    widget.intervention.addAll(extraData);

    try {
      final supabase = Supabase.instance.client;
      final clean = <String, dynamic>{};
      for (final entry in extraData.entries) {
        if (kColonnesInterventionsSupabase.contains(entry.key)) {
          clean[entry.key] = entry.value;
        }
      }
      await supabase
          .from('interventions')
          .update(clean)
          .eq('id', widget.intervention['id']);
    } catch (e) {
      debugPrint('Sync rapport brouillon Supabase: $e');
    }

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ClotureScreen(intervention: widget.intervention),
      ),
    );
  }

  bool get _estEnPause =>
      widget.intervention['en_pause_chantier'] == true ||
      widget.intervention['statut'] == 'Intervention en pause';

  Future<void> _basculerPauseForm() async {
    final now = DateTime.now();
    final bool estEnPause = _estEnPause;
    final updates = <String, dynamic>{};

    if (!estEnPause) {
      final motifs = [
        {'label': 'Pause repas / dîner', 'icon': Icons.restaurant},
        {'label': 'Attente client / accès site', 'icon': Icons.hourglass_top},
        {'label': 'Attente grue / machine', 'icon': Icons.handyman},
        {'label': 'Appel support technique / bureau', 'icon': Icons.phone_in_talk},
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
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
                ...motifs.map((m) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(m['icon'] as IconData, color: Colors.amber.shade800),
                      title: Text(m['label'] as String, style: const TextStyle(fontWeight: FontWeight.w500)),
                      trailing: const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
                      onTap: () => Navigator.pop(ctx, m['label'] as String),
                    )),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx, null),
                    child: const Text('Annuler', style: TextStyle(color: Colors.grey)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      if (motifChoisi == null) return;

      updates['en_pause_chantier'] = true;
      updates['heure_debut_pause_chantier'] = now.toIso8601String();
      updates['statut'] = 'Intervention en pause';
      updates['motif_pause_chantier'] = motifChoisi;
    } else {
      updates['en_pause_chantier'] = false;
      updates['statut'] = 'Arrivé';
      final debutPauseStr = widget.intervention['heure_debut_pause_chantier'] as String?;
      int pauseSec = 0;
      if (widget.intervention['duree_pause_chantier_secondes'] is int) {
        pauseSec = widget.intervention['duree_pause_chantier_secondes'] as int;
      }
      if (debutPauseStr != null) {
        final debut = DateTime.tryParse(debutPauseStr);
        if (debut != null) {
          pauseSec += now.difference(debut).inSeconds;
        }
      }
      updates['duree_pause_chantier_secondes'] = pauseSec;
    }

    try {
      final supabase = Supabase.instance.client;
      await supabase
          .from('interventions')
          .update(updates)
          .eq('id', widget.intervention['id']);
    } catch (_) {}

    setState(() {
      widget.intervention.addAll(updates);
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(!estEnPause ? '⏸️ Intervention mise en pause' : '▶️ Intervention reprise !'),
          backgroundColor: !estEnPause ? Colors.amber.shade900 : Colors.green,
        ),
      );
    }
  }

  // ─── Helpers UI ──────────────────────────────────────────────────────

  Widget _sectionTitle(String title, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: color.withValues(alpha: 0.15),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _decor(String label, {String? hint, IconData? icon}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon != null ? Icon(icon, size: 20) : null,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      filled: true,
      fillColor: Colors.grey.shade50,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label, {
    String? hint,
    IconData? icon,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    bool required = false,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: ctrl,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        maxLines: maxLines,
        decoration: _decor(label, hint: hint, icon: icon),
        validator: required
            ? (v) => (v == null || v.trim().isEmpty) ? 'Champ requis' : null
            : null,
      ),
    );
  }

  Widget _dropdown<T>(
    String label,
    T? value,
    List<T> items,
    ValueChanged<T?> onChanged, {
    bool required = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<T>(
        initialValue: value,
        decoration: _decor(label),
        isExpanded: true,
        items: items
            .map((e) => DropdownMenuItem<T>(value: e, child: Text(e.toString())))
            .toList(),
        onChanged: onChanged,
        validator: required
            ? (v) => v == null ? 'Sélection requise' : null
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Rapport d\'Intervention',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Text(
              'Nº $_numeroRapport',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
        backgroundColor: const Color(0xFFD1001F),
        actions: [
          IconButton(
            icon: Icon(
              _estEnPause ? Icons.play_circle_fill : Icons.pause_circle_outline,
              color: _estEnPause ? Colors.amberAccent : Colors.white,
            ),
            tooltip: _estEnPause ? 'Reprendre l\'intervention' : 'Mettre l\'intervention en pause',
            onPressed: _basculerPauseForm,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: _continuerVersSignature,
              icon: const Icon(Icons.arrow_forward, color: Colors.white),
              label: const Text('Suivant', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ⏸️ Bannière d'intervention en pause
              if (_estEnPause) ...[
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber.shade600),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.pause_circle_filled, color: Colors.amber.shade900, size: 24),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Intervention en pause${widget.intervention['motif_pause_chantier'] != null && (widget.intervention['motif_pause_chantier'] as String).isNotEmpty ? ' • ${widget.intervention['motif_pause_chantier']}' : ''}',
                          style: TextStyle(
                            color: Colors.amber.shade900,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: _basculerPauseForm,
                        icon: const Icon(Icons.play_arrow, size: 16),
                        label: const Text('Reprendre', style: TextStyle(fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              // ⏱️ BANDEAU TEMPS TOTAL FACTURABLE EN DIRECT (ALLER + CHANTIER/RÉDACTION + RETOUR ESTIMÉ)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.indigo.shade900, const Color(0xFF1E2640)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.indigo.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.timer, color: Colors.greenAccent, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'TOTAL FACTURABLE EN DIRECT',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: _estEnPause ? Colors.orange.shade700 : Colors.green.shade600,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _estEnPause ? Icons.pause : Icons.fiber_manual_record,
                                color: Colors.white,
                                size: 10,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _estEnPause ? 'EN PAUSE' : 'EN COURS',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          formatSeconds(_secondesTotalFacturable),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.shade800,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Arrondi 1/4h supérieur',
                            style: TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Détail des 3 volets du temps facturable
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.directions_car, color: Colors.blueAccent, size: 16),
                                  const SizedBox(width: 6),
                                  Text(
                                    '1. Trajet Aller : ${formatSeconds(_secondesTrajetAller)}',
                                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                              Text(
                                (widget.intervention['distance_km'] != null && widget.intervention['distance_km'].toString().isNotEmpty)
                                    ? '${widget.intervention['distance_km']}'
                                    : '--',
                                style: const TextStyle(color: Colors.white70, fontSize: 11),
                              ),
                            ],
                          ),
                          const Divider(color: Colors.white24, height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.handyman, color: Colors.tealAccent, size: 16),
                                  const SizedBox(width: 6),
                                  Text(
                                    '2. Chantier & Rédaction : ${formatSeconds(_secondesChantierArrondi)}',
                                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                              Text(
                                'Live : ${_formatChrono(Duration(seconds: _secondesChantierLive))}',
                                style: const TextStyle(color: Colors.tealAccent, fontSize: 11, fontFamily: 'monospace'),
                              ),
                            ],
                          ),
                          const Divider(color: Colors.white24, height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.rotate_right, color: Colors.orangeAccent, size: 16),
                                  const SizedBox(width: 6),
                                  Text(
                                    '3. Trajet Retour : ${formatSeconds(_secondesRetourFinal)}',
                                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                              Text(
                                _retourAjusteManuellement
                                    ? 'Ajusté (${_distanceRetourCtrl.text.isNotEmpty ? _distanceRetourCtrl.text : "--"})'
                                    : 'Estimé (${_distanceRetourCtrl.text.isNotEmpty ? _distanceRetourCtrl.text : "--"})',
                                style: TextStyle(
                                  color: _retourAjusteManuellement ? Colors.orangeAccent : Colors.white70,
                                  fontSize: 11,
                                  fontWeight: _retourAjusteManuellement ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '⏱️ Le temps facturable inclut le trajet aller, les travaux/rapport et le retour estimé (ajustable ci-dessous).',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ),

              // ─── Section Déplacement & Retour ───────────────
              _sectionTitle('Déplacement & Temps de Retour (Estimé)', Icons.alt_route, Colors.indigo.shade800),
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            backgroundColor: Colors.indigo.shade50,
                            child: Icon(Icons.directions_car, color: Colors.indigo.shade800),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Estimation du trajet de retour',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Par défaut, estimé au même temps (${formatSeconds(_secondesTrajetAller)}) et même distance que l\'aller. Ajustez ici si le trajet retour varie (trafic, autre chantier, etc.) :',
                                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Temps retour payé :', style: TextStyle(fontSize: 12, color: Colors.grey)),
                              const SizedBox(height: 2),
                              Text(
                                formatSeconds(_secondesRetourFinal),
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: _retourAjusteManuellement ? Colors.indigo.shade900 : Colors.black87,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              IconButton.filledTonal(
                                icon: const Icon(Icons.remove, size: 18),
                                tooltip: 'Moins 15 minutes',
                                onPressed: () {
                                  setState(() {
                                    _retourAjusteManuellement = true;
                                    _secondesRetour = (_secondesRetourFinal - 900).clamp(0, 86400);
                                  });
                                },
                              ),
                              const SizedBox(width: 6),
                              IconButton.filledTonal(
                                icon: const Icon(Icons.add, size: 18),
                                tooltip: 'Plus 15 minutes',
                                onPressed: () {
                                  setState(() {
                                    _retourAjusteManuellement = true;
                                    _secondesRetour = (_secondesRetourFinal + 900).clamp(0, 86400);
                                  });
                                },
                              ),
                              if (_retourAjusteManuellement) ...[
                                const SizedBox(width: 6),
                                TextButton.icon(
                                  icon: const Icon(Icons.restart_alt, size: 16),
                                  label: const Text('Reset', style: TextStyle(fontSize: 11)),
                                  onPressed: () {
                                    setState(() {
                                      _retourAjusteManuellement = false;
                                      _secondesRetour = _secondesTrajetAller;
                                      _distanceRetourCtrl.text = (widget.intervention['distance_km'] ?? '--').toString();
                                    });
                                  },
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _distanceRetourCtrl,
                        decoration: _decor(
                          'Distance de retour estimée (km)',
                          hint: 'Ex: 24.5 km',
                          icon: Icons.straighten,
                        ),
                        onChanged: (_) {
                          setState(() => _retourAjusteManuellement = true);
                        },
                      ),
                    ],
                  ),
                ),
              ),

              // ─── Numéro de rapport ─────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade700,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.confirmation_number, color: Colors.white70, size: 22),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Numéro de rapport', style: TextStyle(color: Colors.white70, fontSize: 12)),
                        Text(
                          _numeroRapport,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.copy, color: Colors.white70),
                      tooltip: 'Copier',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _numeroRapport));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Numéro copié !')),
                        );
                      },
                    ),
                  ],
                ),
              ),

              // ─── Informations client ────────────────────────
              _sectionTitle('Informations Client', Icons.business, Colors.blue.shade700),
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      _field(_adresseFactCtrl, 'Adresse de facturation', icon: Icons.receipt, required: true),
                      _field(_adresseIntCtrl, 'Adresse d\'intervention', icon: Icons.location_on, required: true),
                      _field(_contactCtrl, 'Nom du contact', icon: Icons.person, required: true),
                      _field(
                        _telephoneCtrl, 'Téléphone',
                        icon: Icons.phone,
                        keyboardType: TextInputType.phone,
                        required: true,
                      ),
                      _field(
                        _courrielCtrl, 'Courriel',
                        icon: Icons.email,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      _field(_bonCommandeCtrl, 'Numéro de bon de commande', icon: Icons.numbers),
                      _field(
                        _dateChantierCtrl, 'Date de chantier',
                        icon: Icons.calendar_today,
                        required: true,
                      ),
                    ],
                  ),
                ),
              ),

              // ─── Informations technicien & travaux ──────────
              _sectionTitle('Travaux & Intervention', Icons.engineering, Colors.teal.shade700),
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      _field(_technicienCtrl, 'Nom du technicien', icon: Icons.badge, required: true),
                      _field(
                        _numCommandeCtrl, 'Numéro de commande (CO-XXXXX)',
                        hint: 'CO-12345',
                        icon: Icons.work_outline,
                      ),
                      _dropdown<String>(
                        'Type d\'intervention',
                        _typeIntervention,
                        _typesIntervention,
                        (val) => setState(() => _typeIntervention = val),
                        required: true,
                      ),
                      _field(
                        _numRefCtrl, 'Numéro de référence (TF-XXXXX)',
                        hint: 'TF-12345',
                        icon: Icons.tag,
                      ),
                    ],
                  ),
                ),
              ),

              // ─── Machine ─────────────────────────────────────
              _sectionTitle('Informations Machine', Icons.precision_manufacturing, Colors.orange.shade700),
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      _dropdown<String>(
                        'Type de machine',
                        _typeMachine,
                        _typesMachine,
                        (val) => setState(() => _typeMachine = val),
                        required: true,
                      ),
                      Row(
                        children: [
                          Expanded(child: _field(_marqueCtrl, 'Marque', required: true)),
                          const SizedBox(width: 10),
                          Expanded(child: _field(_modeleCtrl, 'Modèle', required: true)),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                            flex: 1,
                            child: _field(
                              _anneeCtrl, 'Année',
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: _field(_serieCtrl, 'Nº de série machine', icon: Icons.qr_code),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: _field(_uniteCtrl, 'Nº d\'unité machine', icon: Icons.pin_outlined),
                          ),
                        ],
                      ),
                      // Alimentation : chips radio
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Alimentation', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                            const SizedBox(height: 6),
                            Row(
                              children: ['12v', '24v'].map((v) {
                                final selected = _alimentation == v;
                                return Padding(
                                  padding: const EdgeInsets.only(right: 10),
                                  child: ChoiceChip(
                                    label: Text(v),
                                    selected: selected,
                                    onSelected: (_) => setState(() => _alimentation = v),
                                    selectedColor: Colors.orange.shade100,
                                    labelStyle: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: selected ? Colors.orange.shade800 : Colors.black54,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ─── Système installé ────────────────────────────
              _sectionTitle('Système Installé', Icons.settings_input_component, Colors.purple.shade700),
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      _field(_numProduitCtrl, 'Numéro de produit', icon: Icons.inventory_2),
                      _field(_serieSystemeCtrl, 'Numéro de série du système installé', icon: Icons.qr_code_2),
                      _field(_versionLogicielCtrl, 'Version de logiciel', icon: Icons.code),
                      Row(
                        children: [
                          Expanded(child: _field(_engrenageCtrl, 'Engrenage')),
                          const SizedBox(width: 10),
                          Expanded(child: _field(_bypassCtrl, 'Position du bypass')),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // ─── Pièces utilisées ────────────────────────────
              _sectionTitle('Pièces Utilisées (Inventaire)', Icons.construction, Colors.red.shade700),
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      if (_piecesChoisies.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Column(
                            children: [
                              Icon(Icons.inventory_2_outlined, size: 40, color: Colors.grey.shade400),
                              const SizedBox(height: 8),
                              const Text(
                                'Aucune pièce ajoutée pour cette intervention.',
                                style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton.icon(
                                onPressed: _ouvrirSelecteurPieces,
                                icon: const Icon(Icons.add_shopping_cart, size: 18),
                                label: const Text('Ajouter une pièce du camion'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.indigo.shade600,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ],
                          ),
                        )
                      else ...[
                        ..._piecesChoisies.map((piece) {
                          final utilise = piece['utilise'] as int;
                          final dispo = piece['quantite'] as int;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Wrap(
                                        spacing: 6,
                                        crossAxisAlignment: WrapCrossAlignment.center,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.indigo.shade100,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              piece['ref'],
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.indigo.shade800,
                                              ),
                                            ),
                                          ),
                                          if (piece['camion'] != null && piece['camion'].toString().isNotEmpty)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                              decoration: BoxDecoration(
                                                color: Colors.red.shade100,
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                piece['camion'].toString(),
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.red.shade900,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        piece['nom'] as String,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                      Text(
                                        'Stock: $dispo ${piece['unite']} • ${piece['camion'] ?? 'Camion'}',
                                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                      ),
                                    ],
                                  ),
                                ),
                                Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
                                      onPressed: utilise > 1
                                          ? () => setState(() => piece['utilise'] = utilise - 1)
                                          : null,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 10),
                                      child: Column(
                                        children: [
                                          Text(
                                            '$utilise',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.red.shade700,
                                            ),
                                          ),
                                          const Text('utilisé', style: TextStyle(fontSize: 9, color: Colors.grey)),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.add_circle_outline, color: Colors.green),
                                      onPressed: () => setState(() => piece['utilise'] = utilise + 1),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, color: Colors.grey, size: 22),
                                      tooltip: 'Retirer',
                                      onPressed: () => setState(() => _piecesChoisies.remove(piece)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _ouvrirSelecteurPieces,
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text('Ajouter une autre pièce'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.indigo.shade700,
                                  side: BorderSide(color: Colors.indigo.shade300),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.red.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.inventory, size: 16, color: Colors.redAccent),
                              const SizedBox(width: 6),
                              Text(
                                '${_piecesUtilisees.length} type(s) de pièce(s) à déduire de l\'inventaire',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.redAccent,
                                  fontSize: 13,
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

              const SizedBox(height: 24),

              // ─── Contrôles de Sécurité & Conformité RaycoWylie ───
              _sectionTitle('Contrôles de Sécurité & Conformité', Icons.verified_user, Colors.green.shade800),
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.green.shade300),
                            ),
                            child: Text(
                              '${_controlesSecurite.length} / ${kControlesSecuriteStandards.length} points vérifiés',
                              style: TextStyle(
                                color: Colors.green.shade900,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    _controlesSecurite = List<String>.from(kControlesSecuriteStandards);
                                  });
                                },
                                child: const Text('Tout cocher', style: TextStyle(fontSize: 12)),
                              ),
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    _controlesSecurite.clear();
                                  });
                                },
                                child: const Text('Tout décocher', style: TextStyle(fontSize: 12, color: Colors.grey)),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Cochez les points de sécurité et conformité validés lors de cette intervention :',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                      const Divider(height: 16),
                      ...kControlesSecuriteStandards.map((item) {
                        final isChecked = _controlesSecurite.contains(item);
                        return CheckboxListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                          activeColor: const Color(0xFFD1001F),
                          title: Text(
                            item,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isChecked ? FontWeight.w600 : FontWeight.normal,
                              color: isChecked ? Colors.black87 : Colors.black54,
                            ),
                          ),
                          value: isChecked,
                          onChanged: (val) {
                            setState(() {
                              if (val == true) {
                                if (!_controlesSecurite.contains(item)) _controlesSecurite.add(item);
                              } else {
                                _controlesSecurite.remove(item);
                              }
                            });
                          },
                        );
                      }),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // ─── Notes de Service & Description des travaux ───
              _sectionTitle('Notes de Service & Travaux Réalisés', Icons.note_alt, Colors.indigo.shade800),
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Indiquez les détails de l\'intervention, pièces testées, calibrations ou recommandations :',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _notesCtrl,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: 'Ex: Remplacement du câble longueur, vérification du capteur de pression sous charge de 5T, système testé conforme...',
                          prefixIcon: Icon(Icons.edit_note),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // ─── Photos du chantier (Restauration avec solution Windows & Mobile) ───
              _sectionTitle('Photos du Chantier & Équipement', Icons.photo_camera, Colors.blue.shade800),
              WidgetPhotosChantier(
                intervention: widget.intervention,
                onPhotosModifiees: () async {
                  setState(() {});
                },
              ),

              const SizedBox(height: 24),

              // ─── Bouton continuer ────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 3,
                  ),
                  icon: const Icon(Icons.draw),
                  label: const Text(
                    'Continuer → Signature Client',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  onPressed: _continuerVersSignature,
                ),
              ),
              const SizedBox(height: 50),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// ==============================================================================
// 🔍 MODAL DE SÉLECTION DES PIÈCES DU CAMION (RAYCO WYLIE)
// ==============================================================================
class SelecteurPiecesModal extends StatefulWidget {
  final ValueChanged<ArticleCamion> onPieceSelected;
  final String? camionInitial;
  final String? technicienInitial;

  const SelecteurPiecesModal({
    super.key,
    required this.onPieceSelected,
    this.camionInitial,
    this.technicienInitial,
  });

  @override
  State<SelecteurPiecesModal> createState() => _SelecteurPiecesModalState();
}

class _SelecteurPiecesModalState extends State<SelecteurPiecesModal> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  bool _enStockSeulement = true;
  late String _camionSelectionne;

  @override
  void initState() {
    super.initState();
    _camionSelectionne = InventaireService.normaliserCamion(
      widget.camionInitial,
      widget.technicienInitial,
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = InventaireService.instance;
    final baseList = service.getArticlesPourCamion(
      _camionSelectionne,
      seulementEnStock: _enStockSeulement,
    );
    final q = _searchQuery.trim().toLowerCase();

    final filtered = q.isEmpty
        ? baseList
        : baseList.where((a) {
            return a.ref.toLowerCase().contains(q) ||
                a.nom.toLowerCase().contains(q) ||
                a.camion.toLowerCase().contains(q) ||
                a.technicien.toLowerCase().contains(q) ||
                a.entrepot.toLowerCase().contains(q) ||
                a.notes.toLowerCase().contains(q);
          }).toList();

    final techDuCamion = InventaireService.camionVersTech[_camionSelectionne] ?? '';

    return Material(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: Column(
        children: [
          // Poignée
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                const Icon(Icons.inventory_2, color: Color(0xFFD1001F)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Pièces & Composantes Camion',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Inventaire assigné : $_camionSelectionne ${techDuCamion.isNotEmpty ? "($techDuCamion)" : ""}',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Sélecteur horizontal de camions
          Container(
            color: Colors.grey.shade50,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildTabCamion('Camion #101', 'David Hestin (TECH 1)'),
                  const SizedBox(width: 6),
                  _buildTabCamion('Camion #102', 'P-O Patry (TECH 2)'),
                  const SizedBox(width: 6),
                  _buildTabCamion('Camion #103', 'J-F Allie (TECH 3)'),
                  const SizedBox(width: 6),
                  _buildTabCamion('Tous', 'Tous les camions'),
                ],
              ),
            ),
          ),

          // Barre de recherche
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Rechercher par référence (11EMA...), nom...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),

          // Filtres rapides Stock
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Row(
              children: [
                ChoiceChip(
                  label: Text('En stock ($_camionSelectionne)'),
                  selected: _enStockSeulement,
                  selectedColor: Colors.green.shade100,
                  labelStyle: TextStyle(
                    color: _enStockSeulement ? Colors.green.shade900 : Colors.black87,
                    fontWeight: _enStockSeulement ? FontWeight.bold : FontWeight.normal,
                    fontSize: 11,
                  ),
                  onSelected: (val) => setState(() => _enStockSeulement = true),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Tout le catalogue'),
                  selected: !_enStockSeulement,
                  selectedColor: Colors.indigo.shade100,
                  labelStyle: TextStyle(
                    color: !_enStockSeulement ? Colors.indigo.shade900 : Colors.black87,
                    fontWeight: !_enStockSeulement ? FontWeight.bold : FontWeight.normal,
                    fontSize: 11,
                  ),
                  onSelected: (val) => setState(() => _enStockSeulement = false),
                ),
                const Spacer(),
                Text(
                  '${filtered.length} réf.',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const Divider(height: 12),

          // Liste des pièces
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Text(
                        'Aucune pièce trouvée pour "$_searchQuery" dans $_camionSelectionne',
                        style: const TextStyle(color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      final hasStock = item.quantite > 0;
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          backgroundColor: hasStock ? Colors.green.shade50 : Colors.grey.shade100,
                          child: Icon(
                            hasStock ? Icons.check_circle_outline : Icons.inventory_2_outlined,
                            color: hasStock ? Colors.green.shade700 : Colors.grey,
                            size: 20,
                          ),
                        ),
                        title: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.indigo.shade50,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                item.ref,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: Colors.indigo.shade800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                item.camion,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red.shade900,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                item.nom,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Text(
                          [
                            if (item.technicien.isNotEmpty) item.technicien,
                            if (item.cout > 0) '${item.cout.toStringAsFixed(2)} \$',
                            if (item.notes.isNotEmpty) item.notes,
                          ].join(' • '),
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: hasStock ? Colors.green.shade100 : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                hasStock ? '${item.quantite} ${item.unite}' : '0 dispo',
                                style: TextStyle(
                                  color: hasStock ? Colors.green.shade800 : Colors.grey.shade700,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.add_circle, color: Color(0xFFD1001F), size: 22),
                          ],
                        ),
                        onTap: () {
                          widget.onPieceSelected(item);
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Pièce ajoutée : ${item.ref} (${item.nom}) - ${item.camion}',
                              ),
                              duration: const Duration(seconds: 2),
                              backgroundColor: Colors.green.shade700,
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
  );
  }

  Widget _buildTabCamion(String id, String label) {
    final isSelected = _camionSelectionne == id;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: const Color(0xFFD1001F),
      backgroundColor: Colors.white,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.black87,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 11,
      ),
      onSelected: (_) => setState(() => _camionSelectionne = id),
    );
  }
}

