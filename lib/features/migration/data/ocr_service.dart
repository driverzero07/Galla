import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/ocr_response.dart';

/// Reads names and balances from a photo of the paper copy.
///
/// OFF in v1 (see FeatureFlags.ocrImport): nothing calls this and the option
/// is hidden. The photo is sent to the Supabase Edge Function `ocr-ledger`,
/// which holds the vision-model key; the app never sees any API key.
abstract class OcrService {
  /// Throws [OcrException] when the photo cannot be read.
  Future<List<OcrEntry>> read(String photoPath);
}

class OcrException implements Exception {
  const OcrException(this.reason);

  /// 'offline' | 'failed' | 'nothing'
  final String reason;
  @override
  String toString() => 'OcrException($reason)';
}

class SupabaseOcrService implements OcrService {
  @override
  Future<List<OcrEntry>> read(String photoPath) async {
    final List<int> bytes;
    try {
      bytes = await File(photoPath).readAsBytes();
    } catch (_) {
      throw const OcrException('failed');
    }
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'ocr-ledger',
        body: {'image_base64': base64Encode(bytes), 'mime': 'image/jpeg'},
      );
      final entries = parseOcrResponse(res.data);
      if (entries.isEmpty) throw const OcrException('nothing');
      return entries;
    } on OcrException {
      rethrow;
    } on SocketException {
      throw const OcrException('offline');
    } catch (_) {
      throw const OcrException('failed');
    }
  }
}

final ocrServiceProvider = Provider<OcrService>((ref) => SupabaseOcrService());
