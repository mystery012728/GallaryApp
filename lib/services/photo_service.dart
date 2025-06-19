import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class PhotoService {
  static const String _binFolderKey = 'bin_folder_photos';
  static const int _binRetentionDays = 30;

  static Future<List<AssetPathEntity>> getAlbums() async {
    final FilterOptionGroup filterOptionGroup = FilterOptionGroup(
      imageOption: const FilterOption(
        sizeConstraint: SizeConstraint(
          minWidth: 100,
          minHeight: 100,
          maxWidth: 100000,
          maxHeight: 100000,
        ),
      ),
      orders: [
        const OrderOption(
          type: OrderOptionType.createDate,
          asc: false,
        ),
      ],
    );

    return await PhotoManager.getAssetPathList(
      type: RequestType.image,
      filterOption: filterOptionGroup,
    );
  }

  static Future<List<AssetEntity>> getPhotosFromAlbum(
    AssetPathEntity album, {
    int start = 0,
    int end = 1000,
  }) async {
    return await album.getAssetListRange(
      start: start,
      end: end,
    );
  }

  static Future<AssetPathEntity?> getCameraAlbum() async {
    final List<AssetPathEntity> albums = await getAlbums();

    for (var album in albums) {
      if (album.name.toLowerCase().contains('camera')) {
        return album;
      }
    }

    return null;
  }

  static Future<AssetPathEntity?> getAllPhotosAlbum() async {
    final List<AssetPathEntity> albums = await getAlbums();

    for (var album in albums) {
      if (album.isAll) {
        return album;
      }
    }

    return albums.isNotEmpty ? albums.first : null;
  }

  // Bin folder functionality
  static Future<void> moveToTrash(AssetEntity photo) async {
    try {
      // Get the file from the asset
      final file = await photo.file;
      if (file == null) return;

      // Save photo info to bin folder
      final binPhotos = await getBinPhotos();

      // Create a bin photo entry
      final binPhoto = {
        'id': photo.id,
        'path': file.path,
        'title': await photo.titleAsync,
        'createDateTime': photo.createDateTime.toIso8601String(),
        'width': photo.width,
        'height': photo.height,
        'deletedAt': DateTime.now().toIso8601String(),
        'expiresAt': DateTime.now()
            .add(const Duration(days: _binRetentionDays))
            .toIso8601String(),
      };

      // Add to bin photos list
      binPhotos.add(binPhoto);

      // Save updated bin photos list
      await saveBinPhotos(binPhotos);

      // Copy file to app documents directory
      final appDir = await getApplicationDocumentsDirectory();
      final binDir = Directory('${appDir.path}/bin');
      if (!await binDir.exists()) {
        await binDir.create(recursive: true);
      }

      final fileName = file.path.split('/').last;
      final binFilePath = '${binDir.path}/$fileName';

      // Copy the file to bin directory
      await file.copy(binFilePath);

      // Now delete the original photo
      await PhotoManager.editor.deleteWithIds([photo.id]);
    } catch (e) {
      debugPrint('Error moving photo to trash: $e');
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> getBinPhotos() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final binPhotosJson = prefs.getString(_binFolderKey);

      if (binPhotosJson == null) {
        return [];
      }

      final List<dynamic> decoded = jsonDecode(binPhotosJson);
      final List<Map<String, dynamic>> binPhotos =
          decoded.cast<Map<String, dynamic>>();

      // Filter out expired photos
      final now = DateTime.now();
      final validPhotos = binPhotos.where((photo) {
        final expiresAt = DateTime.parse(photo['expiresAt']);
        return expiresAt.isAfter(now);
      }).toList();

      // If some photos were expired, update the stored list
      if (validPhotos.length != binPhotos.length) {
        await saveBinPhotos(validPhotos);

        // Delete expired photo files
        final expiredPhotos = binPhotos.where((photo) {
          final expiresAt = DateTime.parse(photo['expiresAt']);
          return expiresAt.isBefore(now);
        }).toList();

        for (var photo in expiredPhotos) {
          await _deletePhotoFile(photo);
        }
      }

      return validPhotos;
    } catch (e) {
      debugPrint('Error getting bin photos: $e');
      return [];
    }
  }

  static Future<void> saveBinPhotos(
      List<Map<String, dynamic>> binPhotos) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final binPhotosJson = jsonEncode(binPhotos);
      await prefs.setString(_binFolderKey, binPhotosJson);
    } catch (e) {
      debugPrint('Error saving bin photos: $e');
    }
  }

  static Future<void> restoreFromBin(Map<String, dynamic> binPhoto) async {
    try {
      // Get the file path from bin photo
      final String filePath = binPhoto['path'];

      // Check if the file exists in the bin directory
      final appDir = await getApplicationDocumentsDirectory();
      final binDir = Directory('${appDir.path}/bin');
      final fileName = filePath.split('/').last;
      final binFilePath = '${binDir.path}/$fileName';
      final binFile = File(binFilePath);

      if (await binFile.exists()) {
        // Save the file back to gallery
        await PhotoManager.editor.saveImageWithPath(
          binFilePath,
          title: binPhoto['title'] ?? 'Restored photo',
        );

        // Remove from bin photos list
        final binPhotos = await getBinPhotos();
        binPhotos.removeWhere((photo) => photo['id'] == binPhoto['id']);
        await saveBinPhotos(binPhotos);

        // Delete the file from bin directory
        await binFile.delete();
      }
    } catch (e) {
      debugPrint('Error restoring photo from bin: $e');
      rethrow;
    }
  }

  static Future<void> deleteFromBin(Map<String, dynamic> binPhoto) async {
    try {
      await _deletePhotoFile(binPhoto);

      // Remove from bin photos list
      final binPhotos = await getBinPhotos();
      binPhotos.removeWhere((photo) => photo['id'] == binPhoto['id']);
      await saveBinPhotos(binPhotos);
    } catch (e) {
      debugPrint('Error deleting photo from bin: $e');
      rethrow;
    }
  }

  static Future<void> _deletePhotoFile(Map<String, dynamic> binPhoto) async {
    // Get the file path from bin photo
    final appDir = await getApplicationDocumentsDirectory();
    final binDir = Directory('${appDir.path}/bin');
    final fileName = binPhoto['path'].split('/').last;
    final binFilePath = '${binDir.path}/$fileName';
    final binFile = File(binFilePath);

    // Delete the file if it exists
    if (await binFile.exists()) {
      await binFile.delete();
    }
  }

  static Future<void> emptyBin() async {
    try {
      // Delete all files in bin directory
      final appDir = await getApplicationDocumentsDirectory();
      final binDir = Directory('${appDir.path}/bin');

      if (await binDir.exists()) {
        await binDir.delete(recursive: true);
        await binDir.create();
      }

      // Clear bin photos list
      await saveBinPhotos([]);
    } catch (e) {
      debugPrint('Error emptying bin: $e');
      rethrow;
    }
  }

  static Future<int> getRemainingDays(Map<String, dynamic> binPhoto) async {
    final expiresAt = DateTime.parse(binPhoto['expiresAt']);
    final now = DateTime.now();
    final difference = expiresAt.difference(now);
    return difference.inDays + 1; // +1 to include the current day
  }
}
