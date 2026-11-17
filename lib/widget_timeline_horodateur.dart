import 'package:flutter/material.dart';
import 'app_helpers.dart';

class WidgetTimelineHorodateur extends StatelessWidget {
  final Map<String, dynamic> intervention;
  final bool compact;

  const WidgetTimelineHorodateur({
    super.key,
    required this.intervention,
    this.compact = false,
  });

  /// Calcule précisément les durées en secondes pour tous les segments horodatés
  static Map<String, dynamic> calculerBilanTemps(Map<String, dynamic> intervention) {
    final now = DateTime.now();

    // 1. Trajet aller
    int trajetSec = 0;
    if (intervention['duree_trajet_secondes'] is num) {
      trajetSec = (intervention['duree_trajet_secondes'] as num).toInt();
    } else if (intervention['duree_trajet'] != null) {
      trajetSec = dureeChaineVersSecondes(intervention['duree_trajet'].toString());
    } else if (intervention['heure_depart_trajet'] != null && intervention['heure_arrivee_site'] != null) {
      final dep = DateTime.tryParse(intervention['heure_depart_trajet'].toString());
      final arr = DateTime.tryParse(intervention['heure_arrivee_site'].toString());
      if (dep != null && arr != null && arr.isAfter(dep)) {
        trajetSec = arr.difference(dep).inSeconds;
      }
    } else if (intervention['statut'] == 'En route' && intervention['heure_depart_trajet'] != null) {
      final dep = DateTime.tryParse(intervention['heure_depart_trajet'].toString());
      if (dep != null) {
        trajetSec = now.difference(dep).inSeconds;
      }
    }

    // 2. Chantier brut
    int chantierSec = 0;
    if (intervention['duree_chantier_secondes'] is num) {
      chantierSec = (intervention['duree_chantier_secondes'] as num).toInt();
    } else if (intervention['heure_arrivee_site'] != null && intervention['heure_depart_chantier'] != null) {
      final arr = DateTime.tryParse(intervention['heure_arrivee_site'].toString());
      final dep = DateTime.tryParse(intervention['heure_depart_chantier'].toString());
      if (arr != null && dep != null && dep.isAfter(arr)) {
        chantierSec = dep.difference(arr).inSeconds;
      }
    } else if (intervention['statut'] == 'Arrivé' && intervention['heure_arrivee_site'] != null) {
      final arr = DateTime.tryParse(intervention['heure_arrivee_site'].toString());
      if (arr != null) {
        chantierSec = now.difference(arr).inSeconds;
      }
    }

    // 3. Pause chantier déduite
    int pauseSec = 0;
    if (intervention['duree_pause_chantier_secondes'] is num) {
      pauseSec = (intervention['duree_pause_chantier_secondes'] as num).toInt();
    }

    // 4. Rédaction rapport
    int redactionSec = 0;
    if (intervention['duree_redaction_secondes'] is num) {
      redactionSec = (intervention['duree_redaction_secondes'] as num).toInt();
    }

    // 5. Trajet retour
    int retourSec = 0;
    if (intervention['duree_retour_secondes'] is num) {
      retourSec = (intervention['duree_retour_secondes'] as num).toInt();
    } else if (intervention['duree_retour'] != null) {
      retourSec = dureeChaineVersSecondes(intervention['duree_retour'].toString());
    }

    // Total Net Facturable = Trajet aller + (Chantier - Pauses) + Rédaction + Retour
    final int chantierNetSec = (chantierSec - pauseSec) > 0 ? (chantierSec - pauseSec) : 0;
    final int totalFacturableSec = trajetSec + chantierNetSec + redactionSec + retourSec;

    return {
      'trajetSec': trajetSec,
      'chantierSec': chantierSec,
      'pauseSec': pauseSec,
      'chantierNetSec': chantierNetSec,
      'redactionSec': redactionSec,
      'retourSec': retourSec,
      'totalFacturableSec': totalFacturableSec,
    };
  }

  Map<String, dynamic> _calculerBilanTemps() => calculerBilanTemps(intervention);

  static String formatDuree(int seconds) {
    if (seconds <= 0) return '0m';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) {
      return '${h}h ${m.toString().padLeft(2, '0')}m';
    }
    return '${m}m';
  }

  String _formatHms(int seconds) => formatDuree(seconds);

  @override
  Widget build(BuildContext context) {
    final bilan = _calculerBilanTemps();
    final statut = (intervention['statut'] ?? '').toString();
    final bool estEnRoute = statut == 'En route';
    final bool estArrive = statut == 'Arrivé';
    final bool estEnPause = statut == 'En pause' || statut == 'Intervention en pause' || intervention['en_pause_chantier'] == true;
    final bool estComplete = statut == 'Complété' || statut == 'Rapport soumis' || statut == 'Terminé';

    final trajetFait = bilan['trajetSec'] > 0;
    final chantierFait = bilan['chantierSec'] > 0;
    final pauseFait = bilan['pauseSec'] > 0;
    final redactionFait = bilan['redactionSec'] > 0;
    final retourFait = bilan['retourSec'] > 0;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: EdgeInsets.all(compact ? 8 : 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFDEE2E6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // En-tête : Titre & Total Facturable
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.timeline, size: compact ? 15 : 18, color: const Color(0xFF1E293B)),
                  const SizedBox(width: 6),
                  Text(
                    'CHRONOLOGIE & TEMPS EN DIRECT',
                    style: TextStyle(
                      fontSize: compact ? 10.5 : 12,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1E293B),
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF81C784)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.paid_outlined, size: 14, color: Color(0xFF2E7D32)),
                    const SizedBox(width: 4),
                    Text(
                      'Total Net : ${_formatHms(bilan['totalFacturableSec'])}',
                      style: TextStyle(
                        fontSize: compact ? 11 : 12.5,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1B5E20),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Barre de progression / Timeline horizontale des 5 étapes
          LayoutBuilder(
            builder: (ctx, constraints) {
              final isVeryNarrow = constraints.maxWidth < 360;

              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // 1. ALLER
                      _buildTimelineStep(
                        title: 'Aller',
                        duration: _formatHms(bilan['trajetSec']),
                        distance: intervention['distance_km']?.toString(),
                        icon: Icons.directions_car,
                        active: estEnRoute,
                        done: trajetFait && !estEnRoute,
                        color: Colors.blue,
                        compact: isVeryNarrow,
                      ),
                      _buildSeparator(done: trajetFait),

                      // 2. CHANTIER
                      _buildTimelineStep(
                        title: 'Chantier',
                        duration: _formatHms(bilan['chantierSec']),
                        icon: Icons.precision_manufacturing,
                        active: estArrive && !estEnPause,
                        done: chantierFait && (redactionFait || retourFait || estComplete),
                        color: Colors.indigo,
                        compact: isVeryNarrow,
                      ),
                      _buildSeparator(done: chantierFait),

                      // 3. PAUSE (DÉDUITE)
                      _buildTimelineStep(
                        title: 'Pause',
                        duration: pauseFait ? '-${_formatHms(bilan['pauseSec'])}' : '0m',
                        icon: Icons.pause_circle_outline,
                        active: estEnPause,
                        done: pauseFait,
                        color: Colors.amber.shade800,
                        compact: isVeryNarrow,
                        isDeduction: pauseFait,
                      ),
                      _buildSeparator(done: redactionFait || retourFait || estComplete),

                      // 4. RAPPORT
                      _buildTimelineStep(
                        title: 'Rapport',
                        duration: _formatHms(bilan['redactionSec']),
                        icon: Icons.assignment_turned_in_outlined,
                        active: false,
                        done: redactionFait || estComplete,
                        color: Colors.teal,
                        compact: isVeryNarrow,
                      ),
                      _buildSeparator(done: retourFait || estComplete),

                      // 5. RETOUR
                      _buildTimelineStep(
                        title: 'Retour',
                        duration: _formatHms(bilan['retourSec']),
                        distance: intervention['distance_retour_km']?.toString(),
                        icon: Icons.home_work_outlined,
                        active: false,
                        done: retourFait,
                        color: Colors.deepPurple,
                        compact: isVeryNarrow,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineStep({
    required String title,
    required String duration,
    String? distance,
    required IconData icon,
    required bool active,
    required bool done,
    required Color color,
    required bool compact,
    bool isDeduction = false,
  }) {
    Color bg = const Color(0xFFECEFF1);
    Color fg = const Color(0xFF607D8B);
    Color borderColor = Colors.transparent;

    if (active) {
      bg = color.withValues(alpha: 0.15);
      fg = color;
      borderColor = color;
    } else if (done) {
      bg = isDeduction ? Colors.amber.shade50 : color.withValues(alpha: 0.1);
      fg = isDeduction ? Colors.amber.shade900 : color;
      borderColor = isDeduction ? Colors.amber.shade300 : color.withValues(alpha: 0.3);
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: active ? 1.5 : 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: compact ? 12 : 14, color: fg),
              const SizedBox(width: 4),
              Text(
                title,
                style: TextStyle(
                  fontSize: compact ? 9.5 : 11,
                  fontWeight: FontWeight.bold,
                  color: fg,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            duration,
            style: TextStyle(
              fontSize: compact ? 10 : 11.5,
              fontWeight: FontWeight.w800,
              color: isDeduction ? Colors.amber.shade900 : const Color(0xFF1E293B),
            ),
          ),
          if (distance != null && distance.isNotEmpty) ...[
            Text(
              distance,
              style: TextStyle(
                fontSize: compact ? 8 : 9.5,
                color: Colors.blueGrey.shade600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSeparator({required bool done}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Icon(
        Icons.chevron_right,
        size: 16,
        color: done ? const Color(0xFF2E7D32) : const Color(0xFFB0BEC5),
      ),
    );
  }
}
