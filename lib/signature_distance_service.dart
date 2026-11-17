import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_helpers.dart';

/// 🌐 Service et dialogue pour générer et partager le lien de signature client à distance
class SignatureDistanceService {
  /// URL de base web pour la signature à distance (serveur local ou domaine de production)
  static const String kBaseUrlDefaut = 'http://192.168.68.93:8085/#/signer';

  /// Génère un token aléatoire sécurisé de 24 caractères hexadécimaux
  static String genererTokenSecurise() {
    final now = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final randomPart = List.generate(4, (_) => DateTime.now().millisecond.toRadixString(16).padLeft(3, '0')).join();
    return '${now}_$randomPart';
  }

  /// Construit l'URL complète avec le token
  static String construireUrlSignature(String token, {String? baseUrl}) {
    final base = (baseUrl != null && baseUrl.trim().isNotEmpty) ? baseUrl.trim() : kBaseUrlDefaut;
    if (base.contains('?')) {
      return '$base&token=$token';
    } else {
      return '$base?token=$token';
    }
  }

  /// Initialise et enregistre le token de signature pour une intervention
  static Future<String> initialiserTokenPourIntervention(
    Map<String, dynamic> intervention, {
    bool notifierSupabase = true,
  }) async {
    String? tokenExistant = getSignatureToken(intervention);
    if (tokenExistant == null || tokenExistant.isEmpty) {
      tokenExistant = genererTokenSecurise();
    }

    intervention['signature_token'] = tokenExistant;
    intervention['signature_a_distance_demandee'] = true;

    // Sauvegarde de secours dans les notes
    final notes = (intervention['notes'] ?? '').toString();
    final tokenTag = '[SIG_TOKEN: $tokenExistant]';
    const distTag = '[SIG_DISTANTE: OUI]';
    String notesMaj = notes;
    if (!notesMaj.contains('[SIG_TOKEN:')) {
      notesMaj = notesMaj.isEmpty ? tokenTag : '$notesMaj\n$tokenTag';
    } else {
      notesMaj = notesMaj.replaceAll(RegExp(r'\[SIG_TOKEN:[^\]]+\]'), tokenTag);
    }
    if (!notesMaj.contains('[SIG_DISTANTE:')) {
      notesMaj = '$notesMaj\n$distTag';
    }
    intervention['notes'] = notesMaj;

    if (notifierSupabase && intervention['id'] != null) {
      try {
        final supabase = Supabase.instance.client;
        final updates = <String, dynamic>{
          'signature_token': tokenExistant,
          'signature_a_distance_demandee': true,
          'notes': notesMaj,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        };
        await supabase
            .from('interventions')
            .update(updates)
            .eq('id', intervention['id']);
      } catch (e) {
        debugPrint('Erreur sauvegarde token signature Supabase: $e');
        // Fallback sans colonnes dédiées
        try {
          final supabase = Supabase.instance.client;
          await supabase
              .from('interventions')
              .update({
                'notes': notesMaj,
                'updated_at': DateTime.now().toUtc().toIso8601String(),
              })
              .eq('id', intervention['id']);
        } catch (_) {}
      }
    }

    return tokenExistant;
  }

  /// Affiche le dialogue modal de partage de lien au client
  static Future<void> afficherDialoguePartage(
    BuildContext context, {
    required Map<String, dynamic> intervention,
    VoidCallback? onTokenGenere,
  }) async {
    final client = intervention['nom_client'] ?? 'Client';
    final commande = intervention['numero_commande'] ?? intervention['id'] ?? '';
    final courriel = intervention['courriel'] ?? '';
    final telephone = intervention['telephone'] ?? '';
    final contact = intervention['nom_contact'] ?? '';

    // Initialise le token si non existant
    final token = await initialiserTokenPourIntervention(intervention);
    onTokenGenere?.call();

    final lienWeb = construireUrlSignature(token);

    if (!context.mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Poignée de glissement
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD1001F).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.draw, color: Color(0xFFD1001F), size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Signature Client à Distance',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              '$client • $commande',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, size: 20, color: Colors.blue.shade800),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Le client recevra un lien sécurisé lui permettant de visualiser le résumé du rapport et d\'apposer sa signature tactile directement depuis son smartphone ou ordinateur.',
                            style: TextStyle(fontSize: 12, color: Colors.blue.shade900, height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Affichage du lien avec bouton copier
                  const Text(
                    'Lien sécurisé généré :',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            lienWeb,
                            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                            maxLines: 2,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy, size: 20, color: Colors.indigo),
                          tooltip: 'Copier le lien',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: lienWeb));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('📋 Lien de signature copié dans le presse-papier !'),
                                backgroundColor: Colors.indigo,
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Actions de partage rapide (SMS, Courriel, WhatsApp)
                  const Text(
                    'Envoyer directement au client :',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),

                  Row(
                    children: [
                      // Bouton SMS
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.sms, size: 18),
                          label: const Text('SMS'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.green.shade800,
                            side: BorderSide(color: Colors.green.shade400),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () async {
                            final telClean = telephone.toString().replaceAll(RegExp(r'[^0-9+]'), '');
                            final message = 'Bonjour $contact, veuillez valider et signer votre rapport d\'intervention Rayco Wylie ($commande) via ce lien : $lienWeb';
                            final uri = Uri.parse('sms:$telClean?body=${Uri.encodeComponent(message)}');
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(uri);
                            } else {
                              Clipboard.setData(ClipboardData(text: message));
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Message copié pour SMS !')),
                                );
                              }
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Bouton Courriel
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.email, size: 18),
                          label: const Text('Courriel'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.blue.shade800,
                            side: BorderSide(color: Colors.blue.shade400),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () async {
                            final subject = 'Rapport d\'intervention Rayco Wylie à signer - $commande';
                            final body = '''Bonjour $contact,

Votre rapport d'intervention pour la commande $commande a été rédigé.
Veuillez cliquer sur le lien ci-dessous pour le consulter et apposer votre signature de validation :

$lienWeb

Merci de votre confiance,
L'équipe Rayco Wylie''';

                            final uri = Uri.parse('mailto:$courriel?subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}');
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(uri);
                            } else {
                              Clipboard.setData(ClipboardData(text: body));
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Message copié pour courriel !')),
                                );
                              }
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Bouton Copier / Autre
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.share, size: 18),
                          label: const Text('Copier'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFD1001F),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () {
                            final message = 'Bonjour, voici le lien de signature de votre rapport Rayco Wylie ($commande) : $lienWeb';
                            Clipboard.setData(ClipboardData(text: message));
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('✅ Message et lien copiés ! Vous pouvez le coller dans WhatsApp ou votre messagerie.'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
