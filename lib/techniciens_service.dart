import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_helpers.dart';

// ============================================================================
// 👷 MODÈLE DE DONNÉES TECHNICIEN & CAMION
// ============================================================================

class Technicien {
  final String id;
  String nom;
  String numeroCamion;
  bool estDisponible;
  String telephone;
  String courriel;

  Technicien({
    required this.id,
    required this.nom,
    required this.numeroCamion,
    this.estDisponible = true,
    this.telephone = '',
    this.courriel = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'nom': nom,
        'numeroCamion': numeroCamion,
        'numero_camion': numeroCamion,
        'estDisponible': estDisponible,
        'est_disponible': estDisponible,
        'telephone': telephone,
        'courriel': courriel,
      };

  Map<String, dynamic> toSupabase() => {
        'id': id,
        'nom': nom,
        'numero_camion': numeroCamion,
        'est_disponible': estDisponible,
        'telephone': telephone,
        'courriel': courriel,
      };

  factory Technicien.fromJson(Map<String, dynamic> json) => Technicien(
        id: json['id'] as String,
        nom: json['nom'] as String? ?? 'Technicien',
        numeroCamion: (json['numero_camion'] ?? json['numeroCamion']) as String? ?? 'Camion #100',
        estDisponible: (json['est_disponible'] ?? json['estDisponible']) as bool? ?? true,
        telephone: json['telephone'] as String? ?? '',
        courriel: json['courriel'] as String? ?? '',
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Technicien && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

// ============================================================================
// 📁 GESTIONNAIRE DE PERSISTANCE DES TECHNICIENS (LOCAL & SUPABASE)
// ============================================================================

class TechnicienService extends ChangeNotifier {
  static final TechnicienService instance = TechnicienService._();
  TechnicienService._() {
    _initialiserStream();
  }

  List<Technicien> _techniciens = [];
  bool _initialise = false;
  StreamSubscription<List<Map<String, dynamic>>>? _streamSub;

  List<Technicien> get techniciens => _techniciens;

  void _initialiserStream() {
    try {
      _streamSub?.cancel();
      _streamSub = Supabase.instance.client
          .from('techniciens')
          .stream(primaryKey: ['id'])
          .order('nom', ascending: true)
          .listen(
            (data) {
              if (data.isNotEmpty) {
                _techniciens = data.map((item) => Technicien.fromJson(item)).toList();
                _sauvegarderLocal();
                notifyListeners();
              }
            },
            onError: (e) {
              debugPrint('Stream techniciens: $e');
            },
          );
    } catch (e) {
      debugPrint('Erreur stream techniciens: $e');
    }
  }

  Future<List<Technicien>> getTechniciens() async {
    if (!_initialise) {
      await charger();
    }
    return _techniciens;
  }

  List<Technicien> getTechniciensDisponibles() {
    return _techniciens.where((t) => t.estDisponible).toList();
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
      return File('${dir.path}\\techniciens.json');
    } catch (_) {
      return null;
    }
  }

  Future<void> charger() async {
    _initialise = true;

    // 1. Essai de chargement depuis Supabase
    try {
      final response = await Supabase.instance.client
          .from('techniciens')
          .select()
          .order('nom', ascending: true);
      if (response.isNotEmpty) {
        _techniciens = List<Map<String, dynamic>>.from(response)
            .map((item) => Technicien.fromJson(item))
            .toList();
        await _sauvegarderLocal();
        notifyListeners();
        return;
      }
    } catch (e) {
      debugPrint('Supabase techniciens indisponible (mode local): $e');
    }

    // 2. Fallback cache local
    try {
      final file = _getFichierSauvegarde();
      if (file != null && await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> jsonList = jsonDecode(content) as List<dynamic>;
        _techniciens = jsonList
            .map((item) => Technicien.fromJson(item as Map<String, dynamic>))
            .toList();
        if (_techniciens.isNotEmpty) {
          notifyListeners();
          return;
        }
      }
    } catch (e) {
      debugPrint('Erreur chargement local techniciens: $e');
    }

    // 3. 3 techniciens et camions officiels RaycoWylie
    _techniciens = [
      Technicien(
        id: 'tech_01',
        nom: 'David Hestin',
        numeroCamion: 'Camion #101',
        estDisponible: true,
        telephone: '418-555-0101',
        courriel: 'd.hestin@raycowylie.com',
      ),
      Technicien(
        id: 'tech_02',
        nom: 'Pierre-Olivier Patry',
        numeroCamion: 'Camion #102',
        estDisponible: true,
        telephone: '418-555-0102',
        courriel: 'p.patry@raycowylie.com',
      ),
      Technicien(
        id: 'tech_03',
        nom: 'Jean-François Allie',
        numeroCamion: 'Camion #103',
        estDisponible: false,
        telephone: '418-555-0103',
        courriel: 'jf.allie@raycowylie.com',
      ),
    ];
    await _sauvegarderLocal();
    notifyListeners();

    // Tenter de synchroniser vers Supabase en arrière-plan
    for (final t in _techniciens) {
      try {
        await Supabase.instance.client.from('techniciens').upsert(t.toSupabase());
      } catch (_) {}
    }
  }

  Future<void> _sauvegarderLocal() async {
    try {
      final file = _getFichierSauvegarde();
      if (file != null) {
        final jsonStr = jsonEncode(_techniciens.map((t) => t.toJson()).toList());
        await file.writeAsString(jsonStr);
      }
    } catch (e) {
      debugPrint('Erreur sauvegarde locale techniciens: $e');
    }
  }

  Future<void> sauvegarder() async {
    await _sauvegarderLocal();
  }

  Future<void> ajouterTechnicien({
    required String nom,
    required String numeroCamion,
    String telephone = '',
    String courriel = '',
    bool estDisponible = true,
  }) async {
    final nouveau = Technicien(
      id: 'tech_${DateTime.now().millisecondsSinceEpoch}',
      nom: nom.trim(),
      numeroCamion: numeroCamion.trim(),
      telephone: telephone.trim(),
      courriel: courriel.trim(),
      estDisponible: estDisponible,
    );
    _techniciens.add(nouveau);
    notifyListeners();
    await _sauvegarderLocal();
    try {
      await Supabase.instance.client.from('techniciens').upsert(nouveau.toSupabase());
    } catch (e) {
      debugPrint('Erreur Supabase ajouterTechnicien: $e');
    }
  }

  Future<void> supprimerTechnicien(String id) async {
    _techniciens.removeWhere((t) => t.id == id);
    notifyListeners();
    await _sauvegarderLocal();
    try {
      await Supabase.instance.client.from('techniciens').delete().eq('id', id);
    } catch (e) {
      debugPrint('Erreur Supabase supprimerTechnicien: $e');
    }
  }

  Future<void> basculerDisponibilite(String id) async {
    final t = _techniciens.firstWhere((item) => item.id == id);
    t.estDisponible = !t.estDisponible;
    notifyListeners();
    await _sauvegarderLocal();
    try {
      await Supabase.instance.client
          .from('techniciens')
          .update({'est_disponible': t.estDisponible})
          .eq('id', id);
    } catch (e) {
      debugPrint('Erreur Supabase basculerDisponibilite: $e');
    }
  }

  Future<void> modifierTechnicien(Technicien t) async {
    final idx = _techniciens.indexWhere((item) => item.id == t.id);
    if (idx != -1) {
      _techniciens[idx] = t;
    }
    notifyListeners();
    await _sauvegarderLocal();
    try {
      await Supabase.instance.client.from('techniciens').upsert(t.toSupabase());
    } catch (e) {
      debugPrint('Erreur Supabase modifierTechnicien: $e');
    }
  }
}

// ============================================================================
// 👥 MODAL DE GESTION DES TECHNICIENS & CAMIONS POUR LE SUPERVISEUR
// ============================================================================

class GestionTechniciensModal extends StatefulWidget {
  const GestionTechniciensModal({super.key});

  @override
  State<GestionTechniciensModal> createState() => _GestionTechniciensModalState();
}

class _GestionTechniciensModalState extends State<GestionTechniciensModal> {
  final TechnicienService _service = TechnicienService.instance;
  List<Technicien> _techniciens = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _charger();
    _service.addListener(_onTechniciensUpdated);
  }

  @override
  void dispose() {
    _service.removeListener(_onTechniciensUpdated);
    super.dispose();
  }

  void _onTechniciensUpdated() {
    if (mounted) {
      setState(() {
        _techniciens = _service.techniciens;
      });
    }
  }

  Future<void> _charger() async {
    setState(() => _isLoading = true);
    final list = await _service.getTechniciens();
    setState(() {
      _techniciens = list;
      _isLoading = false;
    });
  }

  Future<void> _ajouterNouveauTechnicien() async {
    final nomCtrl = TextEditingController();
    final camionCtrl = TextEditingController(text: 'Camion #${_techniciens.length + 101}');
    final telCtrl = TextEditingController();
    final courrielCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.person_add_alt_1, color: Colors.blueAccent),
            SizedBox(width: 8),
            Text('Ajouter un technicien'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nomCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nom complet du technicien *',
                  prefixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: camionCtrl,
                decoration: const InputDecoration(
                  labelText: 'Numéro ou nom du camion *',
                  prefixIcon: Icon(Icons.local_shipping),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: courrielCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Courriel (invitations calendrier)',
                  prefixIcon: Icon(Icons.email),
                  border: OutlineInputBorder(),
                  hintText: 'ex: technicien@raycowylie.com',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: telCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Téléphone (optionnel)',
                  prefixIcon: Icon(Icons.phone),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
            onPressed: () {
              if (nomCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await _service.ajouterTechnicien(
        nom: nomCtrl.text,
        numeroCamion: camionCtrl.text.isNotEmpty ? camionCtrl.text : 'Camion #100',
        courriel: courrielCtrl.text.trim(),
        telephone: telCtrl.text,
      );
      await _charger();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Technicien ${nomCtrl.text} ajouté avec succès !'),
            backgroundColor: Colors.green.shade800,
          ),
        );
      }
    }
  }

  Future<void> _editerTechnicien(Technicien tech) async {
    final nomCtrl = TextEditingController(text: tech.nom);
    final camionCtrl = TextEditingController(text: tech.numeroCamion);
    final telCtrl = TextEditingController(text: tech.telephone);
    final courrielCtrl = TextEditingController(text: tech.courriel);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.edit, color: Colors.indigo),
            SizedBox(width: 8),
            Text('Modifier le technicien'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nomCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nom complet du technicien',
                  prefixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: camionCtrl,
                decoration: const InputDecoration(
                  labelText: 'Numéro ou nom du camion',
                  prefixIcon: Icon(Icons.local_shipping),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: telCtrl,
                decoration: const InputDecoration(
                  labelText: 'Téléphone (optionnel)',
                  prefixIcon: Icon(Icons.phone),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: courrielCtrl,
                decoration: const InputDecoration(
                  labelText: 'Courriel (optionnel)',
                  prefixIcon: Icon(Icons.email),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
            onPressed: () {
              if (nomCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );

    if (ok == true) {
      tech.nom = nomCtrl.text.trim();
      tech.numeroCamion = camionCtrl.text.trim();
      tech.telephone = telCtrl.text.trim();
      tech.courriel = courrielCtrl.text.trim();
      await _service.modifierTechnicien(tech);
      await _charger();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Technicien ${tech.nom} modifié avec succès !'),
            backgroundColor: Colors.indigo.shade800,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.indigo.shade50,
                child: const Icon(Icons.groups, color: Colors.indigo),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Gestion des Techniciens & Camions',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Text(
                      'Gestion des disponibilités et de la flotte pour le superviseur',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
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
          const Divider(height: 20),

          if (_isLoading)
            const Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())
          else ...[
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.45),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _techniciens.length,
                separatorBuilder: (ctx, i) => const Divider(height: 8),
                itemBuilder: (ctx, i) {
                  final tech = _techniciens[i];
                  return Container(
                    decoration: BoxDecoration(
                      color: tech.estDisponible ? Colors.green.shade50.withValues(alpha: 0.3) : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: tech.estDisponible ? Colors.green.shade300 : Colors.grey.shade300,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: tech.estDisponible ? Colors.green.shade700 : Colors.grey.shade600,
                          child: const Icon(Icons.person, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    tech.nom,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: tech.estDisponible ? Colors.green.shade100 : Colors.red.shade100,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      tech.estDisponible ? 'DISPONIBLE' : 'NON DISPO',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: tech.estDisponible ? Colors.green.shade900 : Colors.red.shade900,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  Icon(Icons.local_shipping, size: 14, color: Colors.blueGrey.shade700),
                                  const SizedBox(width: 4),
                                  Text(tech.numeroCamion, style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade800)),
                                  if (tech.telephone.isNotEmpty) ...[
                                    const SizedBox(width: 10),
                                    Icon(Icons.phone, size: 13, color: Colors.grey.shade600),
                                    const SizedBox(width: 3),
                                    Text(tech.telephone, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  Icon(
                                    Icons.email,
                                    size: 13,
                                    color: tech.courriel.isNotEmpty ? Colors.indigo.shade700 : Colors.orange.shade700,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      tech.courriel.isNotEmpty ? tech.courriel : 'Aucun courriel (calendrier inactif)',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: tech.courriel.isNotEmpty ? FontWeight.w500 : FontWeight.normal,
                                        color: tech.courriel.isNotEmpty ? Colors.indigo.shade900 : Colors.orange.shade800,
                                        fontStyle: tech.courriel.isEmpty ? FontStyle.italic : FontStyle.normal,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (tech.courriel.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: Colors.indigo.shade50,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: Colors.indigo.shade200),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.calendar_today, size: 9, color: Colors.indigo.shade800),
                                          const SizedBox(width: 3),
                                          Text(
                                            'Sync',
                                            style: TextStyle(fontSize: 9, color: Colors.indigo.shade800, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        // Bascule de disponibilité
                        Switch(
                          value: tech.estDisponible,
                          activeThumbColor: Colors.green.shade700,
                          onChanged: (val) async {
                            await _service.basculerDisponibilite(tech.id);
                            await _charger();
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, color: Colors.indigo, size: 20),
                          tooltip: 'Modifier technicien',
                          onPressed: () => _editerTechnicien(tech),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                          tooltip: 'Retirer technicien',
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Confirmer la suppression'),
                                content: Text('Voulez-vous retirer ${tech.nom} de la liste ?'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('Supprimer', style: TextStyle(color: Colors.white)),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              await _service.supprimerTechnicien(tech.id);
                              await _charger();
                            }
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.add, size: 20),
                label: const Text('Ajouter un Technicien & Camion', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo.shade800,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _ajouterNouveauTechnicien,
              ),
            ),
          ],
        ],
      ),
    ),
  );
  }
}

// ============================================================================
// ➕ MODAL D'AJOUT D'INTERVENTION EN CHANTIER (OUTIL SUPERVISEUR)
// ============================================================================

class NouvelleInterventionModal extends StatefulWidget {
  final Function(Map<String, dynamic>) onInterventionCreee;

  const NouvelleInterventionModal({super.key, required this.onInterventionCreee});

  @override
  State<NouvelleInterventionModal> createState() => _NouvelleInterventionModalState();
}

class _NouvelleInterventionModalState extends State<NouvelleInterventionModal> {
  final _formKey = GlobalKey<FormState>();

  final _clientCtrl = TextEditingController();
  final _adresseChantierCtrl = TextEditingController();
  final _adresseFacturationCtrl = TextEditingController();
  final _commandeCtrl = TextEditingController();
  final _referenceCtrl = TextEditingController();
  final _bonCommandeCtrl = TextEditingController();
  final _troubleCtrl = TextEditingController();
  final _nomContactCtrl = TextEditingController();
  final _telephoneCtrl = TextEditingController();
  final _courrielCtrl = TextEditingController();
  final _camionCtrl = TextEditingController(text: 'Camion #101');

  // 🏗️ Informations Machine & Système (identique au rapport de service)
  String _typeMachine = 'Grue téléscopique';
  final _marqueCtrl = TextEditingController();
  final _modeleCtrl = TextEditingController();
  final _anneeCtrl = TextEditingController();
  final _serieMachineCtrl = TextEditingController();
  final _uniteCtrl = TextEditingController();
  String _alimentation = '12v';
  final _systemeCtrl = TextEditingController(text: 'Rayco Wylie i4500');

  List<Technicien> _techniciens = [];
  Technicien? _technicienSelectionne;
  String _statut = 'En attente';
  bool _isLoading = true;

  // 📅 Planification Calendrier
  DateTime _dateRdv = DateTime.now();
  TimeOfDay _heureRdv = const TimeOfDay(hour: 8, minute: 30);
  int _dureeMinutes = 120; // 2 heures par défaut
  bool _envoyerCalendrierAuto = true;

  @override
  void initState() {
    super.initState();
    _initialiserNumCommande();
    _chargerTechniciens();
  }

  void _initialiserNumCommande() {
    final now = DateTime.now();
    _commandeCtrl.text = 'CO-${now.year}-${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}';
    _referenceCtrl.text = 'TF-${(10000 + (now.millisecondsSinceEpoch % 89999))}';
    _bonCommandeCtrl.text = '#PO-${now.year}${(100000 + (now.millisecond * 73 % 899999))}';
  }

  Future<void> _chargerTechniciens() async {
    final list = await TechnicienService.instance.getTechniciens();
    setState(() {
      _techniciens = list;
      final dispo = list.where((t) => t.estDisponible).toList();
      _technicienSelectionne = dispo.isNotEmpty ? dispo.first : (list.isNotEmpty ? list.first : null);
      if (_technicienSelectionne != null) {
        _camionCtrl.text = _technicienSelectionne!.numeroCamion;
      }
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _clientCtrl.dispose();
    _adresseChantierCtrl.dispose();
    _adresseFacturationCtrl.dispose();
    _commandeCtrl.dispose();
    _referenceCtrl.dispose();
    _bonCommandeCtrl.dispose();
    _troubleCtrl.dispose();
    _nomContactCtrl.dispose();
    _telephoneCtrl.dispose();
    _courrielCtrl.dispose();
    _camionCtrl.dispose();
    _marqueCtrl.dispose();
    _modeleCtrl.dispose();
    _anneeCtrl.dispose();
    _serieMachineCtrl.dispose();
    _uniteCtrl.dispose();
    _systemeCtrl.dispose();
    super.dispose();
  }

  Future<void> _choisirDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateRdv,
      firstDate: DateTime(2025),
      lastDate: DateTime(2030),
      helpText: 'SÉLECTIONNER LA DATE DU RENDEZ-VOUS',
      cancelText: 'Annuler',
      confirmText: 'Confirmer',
    );
    if (picked != null) {
      setState(() => _dateRdv = picked);
    }
  }

  Future<void> _choisirHeure() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _heureRdv,
      helpText: 'HEURE DU RENDEZ-VOUS EN CHANTIER',
      cancelText: 'Annuler',
      confirmText: 'Confirmer',
    );
    if (picked != null) {
      setState(() => _heureRdv = picked);
    }
  }

  void _preRemplirExemple() {
    setState(() {
      _clientCtrl.text = 'Levage & Grues du Québec Inc.';
      _adresseChantierCtrl.text = '2450 Rue Dalton, Québec, QC G1P 3X1';
      _adresseFacturationCtrl.text = 'C.P. 4402, Succ. Principale, Québec, QC G1K 8Z4';
      _referenceCtrl.text = 'TF-12345';
      _bonCommandeCtrl.text = '#PO-12345678';
      _troubleCtrl.text = 'Afficheur Rayco Wylie ne s\'allume pas. Câble de détection de flèche coupé et calibration requise.';
      _nomContactCtrl.text = 'Jean Tremblay (Surintendant)';
      _telephoneCtrl.text = '418-650-2020';
      _courrielCtrl.text = 'service@levagequebec.com';
      _typeMachine = 'Grue téléscopique';
      _marqueCtrl.text = 'Tadano';
      _modeleCtrl.text = 'GR-700XL';
      _anneeCtrl.text = '2021';
      _serieMachineCtrl.text = 'TD-847291';
      _uniteCtrl.text = 'Unité #GR-4021';
      _alimentation = '24v';
      _systemeCtrl.text = 'Rayco Wylie i4500 RCI';
      _heureRdv = const TimeOfDay(hour: 9, minute: 0);
      _dureeMinutes = 180;
      _envoyerCalendrierAuto = true;
    });
  }

  Future<void> _soumettre() async {
    if (!_formKey.currentState!.validate()) return;

    final dateRdvStr =
        '${_dateRdv.year}-${_dateRdv.month.toString().padLeft(2, '0')}-${_dateRdv.day.toString().padLeft(2, '0')}';
    final heureRdvStr =
        '${_heureRdv.hour.toString().padLeft(2, '0')}:${_heureRdv.minute.toString().padLeft(2, '0')}';

    final nouvelle = {
      'id': 'cmd_${DateTime.now().millisecondsSinceEpoch}',
      'nom_client': _clientCtrl.text.trim(),
      'adresse': _adresseChantierCtrl.text.trim(),
      'adresse_facturation': _adresseFacturationCtrl.text.trim().isNotEmpty
          ? _adresseFacturationCtrl.text.trim()
          : _adresseChantierCtrl.text.trim(),
      'numero_commande': _commandeCtrl.text.trim(),
      'numero_reference': _referenceCtrl.text.trim().isNotEmpty ? _referenceCtrl.text.trim() : 'TF-12345',
      'numero_bon_commande': _bonCommandeCtrl.text.trim().isNotEmpty ? _bonCommandeCtrl.text.trim() : '#PO-12345678',
      'trouble': _troubleCtrl.text.trim(),
      'nom_contact': _nomContactCtrl.text.trim(),
      'telephone': _telephoneCtrl.text.trim(),
      'courriel': _courrielCtrl.text.trim(),
      'type_machine': _typeMachine,
      'marque': _marqueCtrl.text.trim(),
      'modele': _modeleCtrl.text.trim(),
      'annee': _anneeCtrl.text.trim(),
      'numero_serie_machine': _serieMachineCtrl.text.trim(),
      'numero_unite': _uniteCtrl.text.trim().isNotEmpty ? _uniteCtrl.text.trim() : 'Unité #XX-XXXX',
      'alimentation': _alimentation,
      'systeme_wylie': _systemeCtrl.text.trim(),
      'numero_serie_systeme': _systemeCtrl.text.trim(),
      'nom_technicien': _technicienSelectionne?.nom ?? 'Non assigné',
      'courriel_technicien': _technicienSelectionne?.courriel ?? '',
      'envoyer_calendrier_auto': _envoyerCalendrierAuto,
      'numero_camion': _camionCtrl.text.trim().isNotEmpty
          ? _camionCtrl.text.trim()
          : (_technicienSelectionne?.numeroCamion ?? 'Camion #101'),
      'priorite': 'Normale',
      'statut': _statut,
      'date_rendez_vous': dateRdvStr,
      'heure_rendez_vous': heureRdvStr,
      'duree_minutes': _dureeMinutes,
      'date_chantier': dateRdvStr,
    };

    widget.onInterventionCreee(nouvelle);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final dateAffichee =
        '${_dateRdv.year}-${_dateRdv.month.toString().padLeft(2, '0')}-${_dateRdv.day.toString().padLeft(2, '0')}';
    final heureAffichee =
        '${_heureRdv.hour.toString().padLeft(2, '0')}:${_heureRdv.minute.toString().padLeft(2, '0')}';

    return Material(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 18,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // EN-TÊTE
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: Colors.indigo.shade100,
                          child: Icon(Icons.add_task, color: Colors.indigo.shade800),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Nouvelle Intervention & Calendrier',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              Text(
                                'Planifier au calendrier, définir le trouble et assigner le technicien',
                                style: TextStyle(color: Colors.grey, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.auto_fix_high, size: 16),
                          label: const Text('Exemple', style: TextStyle(fontSize: 12)),
                          onPressed: _preRemplirExemple,
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const Divider(height: 20),

                    // ─── 📅 SECTION PLANIFICATION CALENDRIER (EN VEDETTE) ───
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.indigo.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.indigo.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.calendar_month, color: Colors.indigo.shade900, size: 18),
                              const SizedBox(width: 6),
                              Text(
                                'PLANIFICATION DU RENDEZ-VOUS DANS LE CALENDRIER',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: Colors.indigo.shade900,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: InkWell(
                                  onTap: _choisirDate,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.indigo.shade300),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.event, size: 18, color: Colors.indigo),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Text('Date rendez-vous', style: TextStyle(fontSize: 10, color: Colors.grey)),
                                              Text(dateAffichee, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: InkWell(
                                  onTap: _choisirHeure,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.indigo.shade300),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.access_time, size: 18, color: Colors.indigo),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Text('Heure', style: TextStyle(fontSize: 10, color: Colors.grey)),
                                              Text(heureAffichee, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // Durée estimée
                          Row(
                            children: [
                              const Text(
                                'Durée estimée :',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black87),
                              ),
                              const SizedBox(width: 8),
                              ...[60, 120, 180, 240].map((mins) {
                                final isSel = _dureeMinutes == mins;
                                final label = mins == 60 ? '1h' : mins == 120 ? '2h' : mins == 180 ? '3h' : '4h';
                                return Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: ChoiceChip(
                                    label: Text(
                                      label,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                    selected: isSel,
                                    onSelected: (val) {
                                      if (val) setState(() => _dureeMinutes = mins);
                                    },
                                    selectedColor: Colors.indigo.shade200,
                                  ),
                                );
                              }),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ─── CLIENT & NUMÉRO DE COMMANDE ─────────────────
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextFormField(
                            controller: _clientCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Nom du client / Compagnie *',
                              prefixIcon: Icon(Icons.business),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            validator: (v) => v == null || v.trim().isEmpty ? 'Requis' : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: _commandeCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Nº Commande',
                              prefixIcon: Icon(Icons.tag),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // ─── BON DE COMMANDE CLIENT & RÉFÉRENCE ─────────
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _bonCommandeCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Bon de commande client (#PO-XXXXX)',
                              hintText: 'Ex: #PO-12345678',
                              prefixIcon: Icon(Icons.receipt),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: _referenceCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Nº de référence (TF-XXXXX)',
                              hintText: 'Ex: TF-12345',
                              prefixIcon: Icon(Icons.bookmark_outline),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // ─── LE TROUBLE / PANNE SIGNALÉE ──────
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.shade400, width: 1.5),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.report_problem, color: Colors.amber.shade900, size: 18),
                              const SizedBox(width: 6),
                              Text(
                                'LE TROUBLE / PROBLÈME SIGNALÉ',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: Colors.amber.shade900,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _troubleCtrl,
                            maxLines: 2,
                            decoration: const InputDecoration(
                              hintText: 'Ex: Afficheur Rayco Wylie ne s\'allume pas, capteur d\'angle défectueux, calibration flèche...',
                              border: OutlineInputBorder(),
                              fillColor: Colors.white,
                              filled: true,
                              isDense: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),

                    // ─── ADRESSES (CHANTIER & FACTURATION) ───
                    TextFormField(
                      controller: _adresseChantierCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Adresse du chantier (Lieu d\'intervention)',
                        prefixIcon: Icon(Icons.location_on, color: Colors.red),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _adresseFacturationCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Adresse de facturation (si différente)',
                        prefixIcon: Icon(Icons.receipt_long, color: Colors.indigo),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // ─── INFORMATIONS MACHINE & SYSTÈME ───
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
                          Row(
                            children: [
                              Icon(Icons.precision_manufacturing, color: Colors.orange.shade800, size: 18),
                              const SizedBox(width: 6),
                              Text(
                                'INFORMATIONS MACHINE & SYSTÈME RAYCO WYLIE',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: Colors.orange.shade900,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          // Type de machine déroulant standardisé
                          DropdownButtonFormField<String>(
                            initialValue: _typeMachine,
                            decoration: const InputDecoration(
                              labelText: 'Type de machine *',
                              prefixIcon: Icon(Icons.precision_manufacturing),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: kTypesMachineRayco.map((type) {
                              return DropdownMenuItem<String>(
                                value: type,
                                child: Text(type),
                              );
                            }).toList(),
                            onChanged: (v) {
                              if (v != null) setState(() => _typeMachine = v);
                            },
                          ),
                          const SizedBox(height: 10),
                          // Marque et Modèle
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _marqueCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Marque',
                                    prefixIcon: Icon(Icons.business_center),
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextFormField(
                                  controller: _modeleCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Modèle',
                                    prefixIcon: Icon(Icons.model_training),
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          // Année, Nº de série machine et Nº d'unité
                          Row(
                            children: [
                              Expanded(
                                flex: 1,
                                child: TextFormField(
                                  controller: _anneeCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Année',
                                    prefixIcon: Icon(Icons.calendar_today),
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  controller: _serieMachineCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Nº de série machine',
                                    prefixIcon: Icon(Icons.pin),
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  controller: _uniteCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Nº d\'unité machine',
                                    hintText: 'Ex: Unité #XX-XXXX',
                                    prefixIcon: Icon(Icons.pin_outlined),
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          // Système Rayco Wylie et Alimentation
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                flex: 3,
                                child: TextFormField(
                                  controller: _systemeCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Système Rayco Wylie',
                                    hintText: 'Ex: i4500, i4300, W2245...',
                                    prefixIcon: Icon(Icons.speed),
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Alimentation', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: ['12v', '24v'].map((v) {
                                      final isSel = _alimentation == v;
                                      return Padding(
                                        padding: const EdgeInsets.only(right: 4),
                                        child: ChoiceChip(
                                          label: Text(v, style: TextStyle(fontSize: 11, fontWeight: isSel ? FontWeight.bold : FontWeight.normal)),
                                          selected: isSel,
                                          onSelected: (val) {
                                            if (val) setState(() => _alimentation = v);
                                          },
                                          selectedColor: Colors.orange.shade200,
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),

                    // ─── ASSIGNATION TECHNICIEN & CAMION ───
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: DropdownButtonFormField<Technicien>(
                            initialValue: _technicienSelectionne,
                            decoration: const InputDecoration(
                              labelText: 'Technicien assigné *',
                              prefixIcon: Icon(Icons.person),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: _techniciens.map((t) {
                              return DropdownMenuItem(
                                value: t,
                                child: Text('${t.nom} (${t.numeroCamion})'),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _technicienSelectionne = val;
                                  _camionCtrl.text = val.numeroCamion;
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: _camionCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Camion',
                              prefixIcon: Icon(Icons.local_shipping),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    // ─── INFO COURRIEL DU TECHNICIEN POUR CALENDRIER ───
                    Container(
                      margin: const EdgeInsets.only(top: 6, bottom: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: (_technicienSelectionne?.courriel.isNotEmpty == true)
                            ? Colors.indigo.shade50
                            : Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: (_technicienSelectionne?.courriel.isNotEmpty == true)
                              ? Colors.indigo.shade200
                              : Colors.orange.shade300,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            (_technicienSelectionne?.courriel.isNotEmpty == true)
                                ? Icons.mark_email_read
                                : Icons.warning_amber_rounded,
                            size: 16,
                            color: (_technicienSelectionne?.courriel.isNotEmpty == true)
                                ? Colors.indigo.shade800
                                : Colors.orange.shade900,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              (_technicienSelectionne?.courriel.isNotEmpty == true)
                                  ? 'Courriel calendrier : ${_technicienSelectionne!.courriel}'
                                  : 'Aucun courriel configuré pour ce technicien (calendrier inactif)',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: (_technicienSelectionne?.courriel.isNotEmpty == true)
                                    ? Colors.indigo.shade900
                                    : Colors.orange.shade900,
                              ),
                            ),
                          ),
                          if (_technicienSelectionne?.courriel.isNotEmpty == true)
                            const Icon(Icons.check_circle, size: 14, color: Colors.green),
                        ],
                      ),
                    ),
                    CheckboxListTile(
                      value: _envoyerCalendrierAuto,
                      onChanged: (val) => setState(() => _envoyerCalendrierAuto = val ?? true),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Envoyer automatiquement l\'invitation au calendrier du technicien',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      subtitle: const Text(
                        'Crée l\'invitation .ics pour synchronisation Outlook / Google Calendar / Téléphone',
                        style: TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    const SizedBox(height: 10),

                    // ─── CONTACT SUR PLACE (NOM & TÉLÉPHONE RELIÉS) ───
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextFormField(
                            controller: _nomContactCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Nom du contact sur place',
                              prefixIcon: Icon(Icons.person),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: _telephoneCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Téléphone contact *',
                              prefixIcon: Icon(Icons.phone),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            keyboardType: TextInputType.phone,
                            validator: (v) => v == null || v.trim().isEmpty ? 'Téléphone requis' : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // ─── COURRIEL CONTACT & STATUT INITIAL ───
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextFormField(
                            controller: _courrielCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Courriel contact',
                              prefixIcon: Icon(Icons.email),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            keyboardType: TextInputType.emailAddress,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<String>(
                            initialValue: _statut,
                            decoration: const InputDecoration(
                              labelText: 'Statut initial',
                              prefixIcon: Icon(Icons.sync),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: const [
                              DropdownMenuItem(value: 'En attente', child: Text('En attente')),
                              DropdownMenuItem(value: 'En route', child: Text('En route')),
                              DropdownMenuItem(value: 'Arrivé', child: Text('Arrivé')),
                            ],
                            onChanged: (v) => setState(() => _statut = v ?? 'En attente'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // ─── BOUTONS D'ACTION ───
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.calendar_month, size: 20),
                            label: const Text(
                              'Créer & Planifier au Calendrier',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.indigo.shade800,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: _soumettre,
                          ),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text('Annuler'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
      ),
    );
  }
}
