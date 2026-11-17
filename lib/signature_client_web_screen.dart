import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:signature/signature.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_helpers.dart';

/// 🌐 Page Web épurée et moderne permettant au client de consulter son rapport et de signer à distance
class SignatureClientWebScreen extends StatefulWidget {
  final String token;

  const SignatureClientWebScreen({
    super.key,
    required this.token,
  });

  @override
  State<SignatureClientWebScreen> createState() => _SignatureClientWebScreenState();
}

class _SignatureClientWebScreenState extends State<SignatureClientWebScreen> {
  final SignatureController _sigController = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black87,
    exportBackgroundColor: Colors.transparent,
  );
  final TextEditingController _nomSignataireController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _dejaSigne = false;
  String? _errorMessage;
  Map<String, dynamic>? _intervention;

  @override
  void initState() {
    super.initState();
    _chargerInterventionParToken();
  }

  @override
  void dispose() {
    _sigController.dispose();
    _nomSignataireController.dispose();
    super.dispose();
  }

  Future<void> _chargerInterventionParToken() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final supabase = Supabase.instance.client;
      final cleanToken = widget.token.trim();

      // 1. Recherche par colonne signature_token
      var res = await supabase
          .from('interventions')
          .select()
          .eq('signature_token', cleanToken)
          .maybeSingle();

      // 2. Fallback recherche dans les notes si la colonne n'est pas encore migrée
      if (res == null) {
        final all = await supabase
            .from('interventions')
            .select()
            .ilike('notes', '%[SIG_TOKEN: $cleanToken]%')
            .limit(1);
        if (all.isNotEmpty) {
          res = all.first;
        }
      }

      // Dernier fallback : si le token est directement l'ID de l'intervention
      res ??= await supabase
          .from('interventions')
          .select()
          .eq('id', cleanToken)
          .maybeSingle();

      if (res == null) {
        setState(() {
          _errorMessage = 'Ce lien de signature est invalide ou a expiré. Veuillez contacter votre technicien Rayco Wylie.';
          _isLoading = false;
        });
        return;
      }

      final it = Map<String, dynamic>.from(res);
      final sigExistant = it['signature'] as String?;
      final contactClient = it['nom_contact'] ?? it['nom_client'] ?? '';

      _nomSignataireController.text = it['nom_signataire_distant'] ?? contactClient;

      setState(() {
        _intervention = it;
        _dejaSigne = sigExistant != null && sigExistant.isNotEmpty;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Erreur chargement intervention par token: $e');
      setState(() {
        _errorMessage = 'Erreur lors du chargement du rapport. Veuillez vérifier votre connexion.';
        _isLoading = false;
      });
    }
  }

  Future<void> _validerEtEnvoyerSignature() async {
    if (_sigController.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Veuillez apposer votre signature dans le cadre ci-dessous.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final nomSignataire = _nomSignataireController.text.trim();
    if (nomSignataire.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Veuillez saisir votre nom complet.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final Uint8List? sigBytes = await _sigController.toPngBytes();
      if (sigBytes == null) throw Exception('Impossible d\'exporter la signature');
      final sigBase64 = base64Encode(sigBytes);
      final now = DateTime.now().toUtc().toIso8601String();

      final existingNotes = (_intervention?['notes'] ?? '').toString();
      final nomTag = '[SIG_NOM: $nomSignataire]';
      String notesMaj = existingNotes;
      if (!notesMaj.contains('[SIG_NOM:')) {
        notesMaj = notesMaj.isEmpty ? nomTag : '$notesMaj\n$nomTag';
      } else {
        notesMaj = notesMaj.replaceAll(RegExp(r'\[SIG_NOM:[^\]]+\]'), nomTag);
      }

      final supabase = Supabase.instance.client;
      final id = _intervention!['id'];

      // Mettre à jour l'intervention dans Supabase
      try {
        await supabase.from('interventions').update({
          'signature': sigBase64,
          'heure_signature': now,
          'nom_signataire_distant': nomSignataire,
          'notes': notesMaj,
          'updated_at': now,
        }).eq('id', id);
      } catch (e) {
        // Fallback sans colonnes optionnelles
        await supabase.from('interventions').update({
          'signature': sigBase64,
          'heure_signature': now,
          'notes': notesMaj,
          'updated_at': now,
        }).eq('id', id);
      }

      setState(() {
        _intervention!['signature'] = sigBase64;
        _intervention!['heure_signature'] = now;
        _intervention!['nom_signataire_distant'] = nomSignataire;
        _dejaSigne = true;
        _isSaving = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Signature enregistrée avec succès ! Merci de votre confiance.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      debugPrint('Erreur enregistrement signature distante: $e');
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors de l\'enregistrement : $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Color(0xFFD1001F)),
                    SizedBox(height: 16),
                    Text('Chargement du rapport...', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              )
            : _errorMessage != null
                ? _buildErrorView()
                : _buildContenuValidation(),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 20, offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 60, color: Color(0xFFD1001F)),
            const SizedBox(height: 16),
            const Text(
              'Lien Invalide ou Expiré',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              _errorMessage ?? 'Impossible d\'accéder à ce rapport.',
              style: const TextStyle(color: Colors.grey, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _chargerInterventionParToken,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD1001F),
                foregroundColor: Colors.white,
              ),
              child: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContenuValidation() {
    final it = _intervention!;
    final client = it['nom_client'] ?? 'Client';
    final commande = it['numero_commande'] ?? it['id'] ?? '';
    final numRapport = it['numero_rapport'] ?? 'RPT-${it['id']}';
    final machine = '${it['type_machine'] ?? ''} ${it['marque'] ?? ''} ${it['modele'] ?? ''}'.trim();
    final technicien = it['nom_technicien'] ?? 'Technicien Rayco Wylie';
    final date = (it['date_chantier'] ?? it['created_at'] ?? '').toString().split('T').first;
    final pieces = getPiecesUtilisees(it);
    final controles = getControlesSecurite(it);
    final dureeChantier = it['duree_chantier'] ?? '--';
    final totalFacturable = it['duree_totale_facturable'] ?? dureeChantier;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 720),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 25, offset: const Offset(0, 6)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ─── En-tête officiel Rayco Wylie ───
              Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  color: Color(0xFF0F172A),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD1001F),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'RAYCO WYLIE',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Validation du Rapport d\'Intervention',
                            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Rapport Nº $numRapport • Commande $commande',
                            style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Badge récapitulatif
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        children: [
                          _buildLigneInfo('Client', client),
                          const Divider(height: 16),
                          _buildLigneInfo('Date de l\'intervention', date),
                          const Divider(height: 16),
                          _buildLigneInfo('Technicien assigné', technicien),
                          if (machine.isNotEmpty) ...[
                            const Divider(height: 16),
                            _buildLigneInfo('Machine / Équipement', machine),
                          ],
                          const Divider(height: 16),
                          _buildLigneInfo('Durée facturable certifiée', totalFacturable, estGras: true),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ─── Pièces utilisées ───
                    if (pieces.isNotEmpty) ...[
                      const Text(
                        '🔩 Pièces & Composantes Installées',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.red.shade50.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.red.shade100),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: pieces.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final p = pieces[i];
                            return ListTile(
                              dense: true,
                              title: Text(p['nom'] ?? p['ref'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                              subtitle: Text('Réf : ${p['ref']}', style: const TextStyle(fontSize: 11)),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.red.shade200),
                                ),
                                child: Text(
                                  'Qté : ${p['utilise']} ${p['unite']}',
                                  style: TextStyle(color: Colors.red.shade900, fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // ─── Contrôles de sécurité Rayco Wylie ───
                    if (controles.isNotEmpty) ...[
                      const Text(
                        '🛡️ Contrôles de Sécurité & Conformité Effectués',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Column(
                          children: controles.map((c) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: [
                                const Icon(Icons.check_circle, size: 16, color: Colors.green),
                                const SizedBox(width: 8),
                                Expanded(child: Text(c, style: const TextStyle(fontSize: 12))),
                              ],
                            ),
                          )).toList(),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // ─── Zone de signature ───
                    if (_dejaSigne)
                      _buildVueDejaSigne()
                    else
                      _buildFormulaireSignature(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLigneInfo(String label, String valeur, {bool estGras = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
        Text(
          valeur,
          style: TextStyle(
            fontSize: 13,
            fontWeight: estGras ? FontWeight.bold : FontWeight.w600,
            color: estGras ? const Color(0xFFD1001F) : Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildVueDejaSigne() {
    final sigBase64 = _intervention!['signature'] as String?;
    final dateSig = (_intervention!['heure_signature'] ?? '').toString().replaceAll('T', ' ').split('.').first;
    final nomSignataire = _intervention!['nom_signataire_distant'] ?? _intervention!['nom_contact'] ?? 'Client';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade300),
      ),
      child: Column(
        children: [
          const Icon(Icons.verified, size: 48, color: Colors.green),
          const SizedBox(height: 10),
          const Text(
            'Ce rapport a déjà été signé et validé',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green),
          ),
          const SizedBox(height: 4),
          Text(
            'Signé par : $nomSignataire le $dateSig',
            style: TextStyle(fontSize: 12, color: Colors.green.shade800),
          ),
          const SizedBox(height: 16),
          if (sigBase64 != null && sigBase64.isNotEmpty)
            Container(
              height: 100,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Image.memory(base64Decode(sigBase64), fit: BoxFit.contain),
            ),
        ],
      ),
    );
  }

  Widget _buildFormulaireSignature() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '✍️ Signature de Validation Client',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'En signant ci-dessous, vous attestez de la bonne réalisation des travaux et de l\'exactitude des temps d\'intervention.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 16),

        TextField(
          controller: _nomSignataireController,
          decoration: InputDecoration(
            labelText: 'Nom et prénom du signataire autorisée *',
            hintText: 'Ex: Jean Tremblay',
            prefixIcon: const Icon(Icons.person_outline),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            filled: true,
            fillColor: Colors.grey.shade50,
          ),
        ),
        const SizedBox(height: 14),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Tracez votre signature ci-dessous :',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            TextButton.icon(
              icon: const Icon(Icons.clear, size: 16),
              label: const Text('Effacer'),
              style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
              onPressed: () => _sigController.clear(),
            ),
          ],
        ),
        const SizedBox(height: 6),

        Container(
          height: 160,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.grey.shade400, width: 1.5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Signature(
              controller: _sigController,
              backgroundColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 20),

        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            icon: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Icon(Icons.check_circle_outline),
            label: Text(
              _isSaving ? 'Enregistrement en cours...' : 'Valider & Confirmer la Signature',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD1001F),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 2,
            ),
            onPressed: _isSaving ? null : _validerEtEnvoyerSignature,
          ),
        ),
      ],
    );
  }
}
