import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Takes a photo with the camera and stores a small compressed copy in the
/// app's private folder. Returns the file path, or null if cancelled.
abstract class PhotoService {
  Future<String?> takePhoto();
}

class CameraPhotoService implements PhotoService {
  final _picker = ImagePicker();

  @override
  Future<String?> takePhoto() async {
    final shot = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 80,
    );
    if (shot == null) return null;

    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'photos'));
    await dir.create(recursive: true);
    final target = p.join(dir.path, '${const Uuid().v4()}.jpg');

    // Aim for roughly 150 KB: low-end phones, slow mobile data.
    final compressed = await FlutterImageCompress.compressAndGetFile(
      shot.path,
      target,
      quality: 70,
      minWidth: 800,
      minHeight: 800,
      format: CompressFormat.jpeg,
    );
    if (compressed == null) {
      await File(shot.path).copy(target);
    }
    try {
      await File(shot.path).delete(); // remove the camera's temp copy
    } catch (_) {}
    return target;
  }
}

final photoServiceProvider =
    Provider<PhotoService>((ref) => CameraPhotoService());
