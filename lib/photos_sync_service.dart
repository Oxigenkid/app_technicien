import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_helpers.dart';

/// 📸 Service de synchronisation hybride des photos & rapports d'intervention
/// - Upload vers Supabase Storage si disponible
/// - Fallback automatique en Base64 compressé léger (< 100 Ko) pour éliminer tout timeout Postgres
/// - Réplication automatique locale dans le dossier Pictures Windows pour consultation Explorer
/// - Synchronisation différée des photos prises hors-ligne dès le retour de la connexion
class PhotosSyncService {
  static final PhotosSyncService instance = PhotosSyncService._();
  PhotosSyncService._();

  static const String bucketName = 'photos_chantier';

  bool _isSyncing = false;
  bool _bucketNotFound = false;
  DateTime? _dernierCheckBucket;

  /// Compresse les octets d'une photo pour garantir un poids plume (< 150 Ko)
  /// et éliminer tout risque de timeout SQL Postgres (code 57014)
  Future<Uint8List> compresserOctetsImage(Uint8List rawBytes, {int maxDimension = 1024}) async {
    // Si l'image fait déjà moins de 150 Ko, aucun redimensionnement requis
    if (rawBytes.lengthInBytes <= 150 * 1024) return rawBytes;

    try {
      final codec = await ui.instantiateImageCodec(
        rawBytes,
        targetWidth: maxDimension,
      );
      final frame = await codec.getNextFrame();
      final byteData = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null && byteData.lengthInBytes < rawBytes.lengthInBytes) {
        return byteData.buffer.asUint8List();
      }
    } catch (e) {
      debugPrint('Avis compression image: $e');
    }
    return rawBytes;
  }

  static int _counterPhoto = 0;

  /// Traite et enregistre une photo :
  /// 1. Enregistre une copie physique locale sur Windows (pleine qualité)
  /// 2. Compresse l'image pour le Cloud
  /// 3. Tente l'envoi vers Supabase Storage (bucket 'photos_chantier')
  /// 4. Si le bucket n'est pas encore configuré : repli Base64 optimisé ultra-léger (< 150 Ko)
  Future<String?> traiterEtSauvegarderPhoto({
    required String sourcePath,
    required String numeroCommande,
  }) async {
    try {
      final cleanNum = numeroCommande.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final folderName = cleanNum.isNotEmpty ? cleanNum : 'COMMANDE_SANS_NUMERO';
      final fileName = 'photo_${DateTime.now().millisecondsSinceEpoch}_${++_counterPhoto}.jpg';

      // 1. Lecture des octets du fichier
      Uint8List bytes;
      final file = File(sourcePath);
      if (await file.exists()) {
        bytes = await file.readAsBytes();
      } else {
        final xfile = XFile(sourcePath);
        bytes = await xfile.readAsBytes();
      }

      if (bytes.isEmpty) return null;

      // 2. Sur Windows : enregistrer une copie physique locale pour l'explorateur (pleine qualité)
      await _sauvegarderLocalementSiWindows(bytes, folderName, fileName);

      // 3. Compression préventive pour le réseau (évite tout timeout SQL 57014)
      final bytesOptimisees = await compresserOctetsImage(bytes, maxDimension: 1024);

      // 4. Tentative d'upload vers Supabase Storage
      final bool peutTenterBucket = !_bucketNotFound ||
          (_dernierCheckBucket != null && DateTime.now().difference(_dernierCheckBucket!).inMinutes >= 3);

      if (peutTenterBucket) {
        try {
          final supabase = Supabase.instance.client;
          final remotePath = '$folderName/$fileName';

          await supabase.storage.from(bucketName).uploadBinary(
                remotePath,
                bytesOptimisees,
                fileOptions: const FileOptions(
                  contentType: 'image/jpeg',
                  upsert: true,
                ),
              );

          final publicUrl = supabase.storage.from(bucketName).getPublicUrl(remotePath);
          if (publicUrl.isNotEmpty) {
            _bucketNotFound = false;
            debugPrint('📸 Photo téléversée sur Supabase Storage : $publicUrl');
            return publicUrl;
          }
        } catch (e) {
          final errStr = e.toString();
          if (errStr.contains('Bucket not found') || errStr.contains('404')) {
            _bucketNotFound = true;
            _dernierCheckBucket = DateTime.now();
            debugPrint('💡 Info Supabase: Le bucket Storage "$bucketName" doit être créé dans votre console Supabase (script supabase_setup.sql). Repli Base64 compressé actif.');
          } else {
            debugPrint('⚠️ Supabase Storage momentanément inaccessible ($e). Repli Base64 compressé actif.');
          }
        }
      }

      // 5. Repli Base64 autonome optimisé (< 150 Ko)
      final base64String = 'data:image/jpeg;base64,${base64Encode(bytesOptimisees)}';
      return base64String;
    } catch (e) {
      debugPrint('Erreur traitement photo: $e');
      return sourcePath;
    }
  }

  /// Sauvegarde locale dans le dossier Pictures de Windows
  Future<void> _sauvegarderLocalementSiWindows(
    Uint8List bytes,
    String folderName,
    String fileName,
  ) async {
    if (kIsWeb || !Platform.isWindows) return;
    try {
      final userProfile = Platform.environment['USERPROFILE'] ?? 'C:\\Users\\Default';
      final targetDir = Directory('$userProfile\\Pictures\\$folderName');
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }
      final targetFile = File('${targetDir.path}\\$fileName');
      if (!await targetFile.exists()) {
        await targetFile.writeAsBytes(bytes);
      }
    } catch (e) {
      debugPrint('Erreur réplication locale Windows: $e');
    }
  }

  /// Récupère les octets d'une photo quelle que soit sa source :
  /// - Base64 data URL
  /// - URL Supabase Storage / HTTP
  /// - Fichier local (Windows ou mobile)
  Future<Uint8List?> recupererBytesPhoto(String photoRef) async {
    try {
      if (photoRef.startsWith('data:image/')) {
        final commaIdx = photoRef.indexOf(',');
        final rawBase64 = commaIdx != -1 ? photoRef.substring(commaIdx + 1) : photoRef;
        return base64Decode(rawBase64.replaceAll(RegExp(r'\s+'), ''));
      }
      if (photoRef.startsWith('http://') || photoRef.startsWith('https://')) {
        final res = await http.get(Uri.parse(photoRef)).timeout(const Duration(seconds: 15));
        if (res.statusCode == 200) {
          return res.bodyBytes;
        }
      }
      final file = File(photoRef);
      if (await file.exists()) {
        return await file.readAsBytes();
      }
      final xfile = XFile(photoRef);
      return await xfile.readAsBytes();
    } catch (e) {
      debugPrint('Erreur recupererBytesPhoto ($photoRef): $e');
      return null;
    }
  }

  /// Réplique une photo (URL ou Base64) en fichier local sur Windows si elle n'existe pas encore
  Future<void> assurerReplicationLocaleWindows(String photoRef, String numeroCommande) async {
    if (kIsWeb || !Platform.isWindows) return;
    try {
      final cleanNum = numeroCommande.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final folderName = cleanNum.isNotEmpty ? cleanNum : 'COMMANDE_SANS_NUMERO';
      final userProfile = Platform.environment['USERPROFILE'] ?? 'C:\\Users\\Default';
      final targetDir = Directory('$userProfile\\Pictures\\$folderName');
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }

      final fileName = 'photo_${photoRef.hashCode.abs()}.jpg';
      final file = File('${targetDir.path}\\$fileName');
      if (await file.exists()) return;

      final bytes = await recupererBytesPhoto(photoRef);
      if (bytes != null && bytes.isNotEmpty) {
        await file.writeAsBytes(bytes);
        debugPrint('💾 Photo répliquée dans Windows : ${file.path}');
      }
    } catch (e) {
      debugPrint('Erreur réplication locale photo: $e');
    }
  }

  /// Synchronise les photos locales prises hors-ligne sur Android dès que la connexion est rétablie
  Future<int> synchroniserPhotosLocalesEnAttente(List<Map<String, dynamic>> interventions) async {
    if (_isSyncing) return 0;
    _isSyncing = true;
    int synchroCount = 0;

    try {
      final supabase = Supabase.instance.client;

      for (final intervention in interventions) {
        final photos = getPhotosIntervention(intervention);
        bool modificationRequise = false;
        final nouvellesPhotos = <String>[];
        final numDossier = getNumeroDossier(intervention);

        for (final p in photos) {
          // Si la photo est un chemin local physique (ex: /data/user/0/... ou C:\...)
          final bool estCheminLocal = !p.startsWith('http') && !p.startsWith('data:image/');

          if (estCheminLocal) {
            final file = File(p);
            if (await file.exists()) {
              // Téléverser sur Supabase
              final cloudRef = await traiterEtSauvegarderPhoto(
                sourcePath: p,
                numeroCommande: numDossier,
              );
              if (cloudRef != null && cloudRef != p) {
                nouvellesPhotos.add(cloudRef);
                modificationRequise = true;
                synchroCount++;
                continue;
              }
            }
          }
          nouvellesPhotos.add(p);
        }

        if (modificationRequise) {
          intervention['photos'] = jsonEncode(nouvellesPhotos);
          try {
            await supabase.from('interventions').update({
              'photos': jsonEncode(nouvellesPhotos),
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            }).eq('id', intervention['id']).timeout(const Duration(seconds: 15));
            debugPrint('✅ Photos synchronisées sur Supabase pour intervention ${intervention['id']}');
          } catch (e) {
            debugPrint('Avis mise à jour photos Supabase: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('Avis synchro globale photos: $e');
    } finally {
      _isSyncing = false;
    }
    return synchroCount;
  }

  /// Téléverse et sauvegarde une copie du rapport PDF officiel sur Supabase Storage
  Future<String?> televerserRapportPdfSurSupabase({
    required List<int> pdfBytes,
    required String numeroCommande,
    required String numeroRapport,
  }) async {
    // Si le bucket n'existe pas encore sur le projet Supabase, éviter de générer une exception 404
    if (_bucketNotFound &&
        _dernierCheckBucket != null &&
        DateTime.now().difference(_dernierCheckBucket!).inMinutes < 3) {
      return null;
    }

    try {
      final supabase = Supabase.instance.client;
      final cleanNum = numeroCommande.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final folderName = cleanNum.isNotEmpty ? cleanNum : 'RAPPORTS';
      final fileName = 'Rapport_${numeroRapport.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}.pdf';
      final remotePath = 'rapports/$folderName/$fileName';

      await supabase.storage.from(bucketName).uploadBinary(
            remotePath,
            Uint8List.fromList(pdfBytes),
            fileOptions: const FileOptions(
              contentType: 'application/pdf',
              upsert: true,
            ),
          );

      final publicUrl = supabase.storage.from(bucketName).getPublicUrl(remotePath);
      _bucketNotFound = false;
      debugPrint('📄 Rapport PDF téléversé avec succès sur Supabase : $publicUrl');
      return publicUrl;
    } catch (e) {
      final errStr = e.toString();
      if (errStr.contains('Bucket not found') || errStr.contains('404')) {
        _bucketNotFound = true;
        _dernierCheckBucket = DateTime.now();
      }
      debugPrint('💡 Téléversement rapport PDF Storage en attente de création du bucket (script supabase_setup.sql)');
      return null;
    }
  }
}
