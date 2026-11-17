import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// ============================================================================
// 🔐 SERVICE CENTRALISÉ DE SÉCURITÉ NIP POUR TECHNICIENS RAYCO WYLIE
// ============================================================================

class NipSecuriteService {
  static final NipSecuriteService instance = NipSecuriteService._();
  NipSecuriteService._();

  File? _getFichierNips() {
    if (kIsWeb) return null;
    try {
      final userProfile =
          Platform.environment['USERPROFILE'] ?? 'C:\\Users\\Default';
      final dir = Directory('$userProfile\\Documents\\AppTechnicien');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      return File('${dir.path}\\nips_techniciens.json');
    } catch (_) {
      return null;
    }
  }

  // Dictionnaire local des NIPs (4 chiffres)
  final Map<String, String> _nips = {
    'David Hestin': '1010',
    'Pierre-Olivier Patry': '1020',
    'Patrick Popatry': '1020',
    'Jean-François Allie': '1030',
  };
  bool _nipsCharges = false;

  Future<void> chargerNips() async {
    if (_nipsCharges) return;
    _nipsCharges = true;
    try {
      final file = _getFichierNips();
      if (file != null && await file.exists()) {
        final content = await file.readAsString();
        final Map<String, dynamic> data = jsonDecode(content);
        data.forEach((k, v) {
          _nips[k] = v.toString();
        });
      }
    } catch (e) {
      debugPrint('Erreur chargement NIPs: $e');
    }
  }

  Future<void> _sauvegarderNips() async {
    try {
      final file = _getFichierNips();
      if (file != null) {
        await file.writeAsString(jsonEncode(_nips));
      }
    } catch (e) {
      debugPrint('Erreur sauvegarde NIPs: $e');
    }
  }

  /// Normalisation des noms pour éviter les divergences
  static String normaliserNomTechnicien(String nom) {
    final l = nom.toLowerCase();
    if (l.contains('patry') || l.contains('patrick') || l.contains('pierre')) {
      return 'Pierre-Olivier Patry';
    }
    if (l.contains('hestin') || l.contains('david')) {
      return 'David Hestin';
    }
    if (l.contains('allie') || l.contains('jean')) {
      return 'Jean-François Allie';
    }
    return nom.trim();
  }

  /// Récupère le code NIP configuré pour un technicien
  Future<String> getNipPourTechnicien(String nomTechnicien) async {
    await chargerNips();
    final direct = _nips[nomTechnicien];
    if (direct != null && direct.isNotEmpty) return direct;
    final norm = normaliserNomTechnicien(nomTechnicien);
    final parNorm = _nips[norm];
    if (parNorm != null && parNorm.isNotEmpty) return parNorm;
    return '1234';
  }

  /// Enregistre un nouveau code NIP pour un technicien
  Future<void> setNipPourTechnicien(String nomTechnicien, String nouveauNip) async {
    await chargerNips();
    _nips[nomTechnicien] = nouveauNip;
    _nips[normaliserNomTechnicien(nomTechnicien)] = nouveauNip;
    await _sauvegarderNips();
  }

  /// Vérifie la validité du NIP (avec passe-partout superviseur 9999)
  Future<bool> verifierNip(String nomTechnicien, String nipSaisi) async {
    final clean = nipSaisi.trim();
    if (clean == '9999') return true; // NIP passe-partout superviseur Rayco
    final attendu = await getNipPourTechnicien(nomTechnicien);
    return clean == attendu.trim();
  }

  /// Dialogue interactif de vérification de NIP réutilisable
  Future<bool> afficherDialogueVerificationNip(
    BuildContext context, {
    required String nomTechnicien,
    required String numeroCamion,
    required String actionDescription,
  }) async {
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

            final valide = await verifierNip(nomTechnicien, code);

            if (!dialogCtx.mounted) return;

            if (valide) {
              Navigator.pop(dialogCtx, true);
            } else {
              setDlgState(() {
                enVerification = false;
                messageErreur = 'Code NIP incorrect pour $nomTechnicien. Réessayez.';
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
                              Text(nomTechnicien, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              Text(numeroCamion, style: const TextStyle(fontSize: 11, color: Colors.black54)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Entrez le code NIP (4 chiffres) associé à ce compte pour $actionDescription.',
                    style: const TextStyle(fontSize: 12.5, color: Colors.black87),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    key: const Key('nip_input_field'),
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
                        Icon(Icons.info_outline, size: 16, color: Colors.blue),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Chaque technicien possède son propre code NIP (D. Hestin: 1010, P.-O. Patry: 1020, J.-F. Allie: 1030). Passe-partout superviseur: 9999.',
                            style: TextStyle(fontSize: 10.5, color: Colors.indigo),
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
                child: const Text('Annuler', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                key: const Key('valider_nip_button'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD1001F),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                ),
                onPressed: enVerification ? null : valider,
                child: Text(
                  enVerification ? 'Vérification...' : 'Déverrouiller',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          );
        },
      ),
    );

    return result == true;
  }

  /// Dialogue interactif de modification du NIP
  Future<void> afficherDialogueChangementNip(
    BuildContext context, {
    required String nomTechnicien,
    required String numeroCamion,
  }) async {
    final actuelCtrl = TextEditingController();
    final nouveauCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    String? erreur;

    await showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          Future<void> enregistrer() async {
            final actuel = actuelCtrl.text.trim();
            final nouveau = nouveauCtrl.text.trim();
            final confirm = confirmCtrl.text.trim();

            if (actuel.isEmpty || nouveau.isEmpty || confirm.isEmpty) {
              setDlgState(() => erreur = 'Veuillez remplir tous les champs.');
              return;
            }
            if (nouveau.length != 4 || int.tryParse(nouveau) == null) {
              setDlgState(() => erreur = 'Le nouveau NIP doit contenir exactement 4 chiffres.');
              return;
            }
            if (nouveau != confirm) {
              setDlgState(() => erreur = 'La confirmation ne correspond pas au nouveau NIP.');
              return;
            }

            final checkActuel = await verifierNip(nomTechnicien, actuel);
            if (!checkActuel) {
              setDlgState(() => erreur = 'Le code NIP actuel est incorrect.');
              return;
            }

            await setNipPourTechnicien(nomTechnicien, nouveau);

            if (!dialogCtx.mounted) return;
            Navigator.pop(dialogCtx);
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('✅ Code NIP de $nomTechnicien mis à jour avec succès!'),
                backgroundColor: Colors.green.shade800,
              ),
            );
          }

          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.password, color: Color(0xFFD1001F)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Modifier mon code NIP ($nomTechnicien)'),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (erreur != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(erreur!, style: TextStyle(color: Colors.red.shade900, fontSize: 12)),
                    ),
                  TextField(
                    controller: actuelCtrl,
                    obscureText: true,
                    maxLength: 4,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Code NIP actuel (4 chiffres)',
                      counterText: '',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nouveauCtrl,
                    obscureText: true,
                    maxLength: 4,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Nouveau code NIP (4 chiffres)',
                      counterText: '',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmCtrl,
                    obscureText: true,
                    maxLength: 4,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Confirmer le nouveau code NIP',
                      counterText: '',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Annuler'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD1001F),
                  foregroundColor: Colors.white,
                ),
                onPressed: enregistrer,
                child: const Text('Enregistrer le NIP'),
              ),
            ],
          );
        },
      ),
    );
  }
}
