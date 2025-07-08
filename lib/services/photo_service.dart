import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class PhotoService {
  static const String _binFolderKey = 'bin_folder_photos';
  static const int _binRetentionDays = 30;

  static Future<List<AssetEntity>> getAllVideos() async {
    try {
      // Request permissions first
      final PermissionState permission = await PhotoManager.requestPermissionExtend();
      if (!permission.isAuth) {
        throw Exception('Permission denied');
      }

      // Get all video albums without restrictive filters
      final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
        type: RequestType.video,
        hasAll: true,
      );

      List<AssetEntity> allVideos = [];

      // Get videos from all albums, not just the "All" album
      for (var album in albums) {
        try {
          final count = await album.assetCountAsync;
          if (count > 0) {
            final videos = await album.getAssetListRange(start: 0, end: count);
            // Filter to ensure we only get videos and avoid duplicates
            for (var video in videos) {
              if (video.type == AssetType.video && !allVideos.any((v) => v.id == video.id)) {
                allVideos.add(video);
              }
            }
          }
        } catch (e) {
          debugPrint('Error loading videos from album ${album.name}: $e');
          continue;
        }
      }

      // Sort by creation date (newest first)
      allVideos.sort((a, b) => b.createDateTime.compareTo(a.createDateTime));

      debugPrint('Found ${allVideos.length} videos');
      return allVideos;
    } catch (e) {
      debugPrint('Error in getAllVideos: $e');
      return [];
    }
  }

  static Future<AssetPathEntity?> getVideosAlbum() async {
    final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
      type: RequestType.video,
    );

    for (var album in albums) {
      if (album.isAll) {
        return album;
      }
    }

    return albums.isNotEmpty ? albums.first : null;
  }

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

    final imageAlbums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      filterOption: filterOptionGroup,
    );

    final videoAlbums = await PhotoManager.getAssetPathList(
      type: RequestType.video,
      filterOption: filterOptionGroup,
    );

    // Combine and return unique albums
    final allAlbums = <AssetPathEntity>[];
    allAlbums.addAll(imageAlbums);

    // Add video albums that aren't already included
    for (var videoAlbum in videoAlbums) {
      if (!allAlbums.any((album) => album.id == videoAlbum.id)) {
        allAlbums.add(videoAlbum);
      }
    }

    return allAlbums;
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

  // Move photo to specific album
  static Future<void> movePhotoToAlbum(AssetEntity photo, AssetPathEntity targetAlbum) async {
    try {
      // Note: This is a simplified implementation
      // In a real app, you might need to use platform-specific APIs
      // For now, we'll just show a success message
      debugPrint('Moving photo ${photo.id} to album ${targetAlbum.name}');

      // You could implement actual photo moving logic here
      // This might involve copying the file and updating album metadata

    } catch (e) {
      debugPrint('Error moving photo to album: $e');
      rethrow;
    }
  }

  // Create new album
  static Future<AssetPathEntity?> createNewAlbum(String albumName) async {
    try {
      // Note: Creating albums programmatically is limited on mobile platforms
      // This is a placeholder implementation
      debugPrint('Creating new album: $albumName');

      // In a real implementation, you might:
      // 1. Create a directory in the device's photo storage
      // 2. Use platform-specific APIs to register the album
      // 3. Return the created album entity

      return null;
    } catch (e) {
      debugPrint('Error creating new album: $e');
      rethrow;
    }
  }

  // Quick delete without confirmation
  static Future<void> quickMoveToTrash(AssetEntity photo) async {
    try {
      final file = await photo.file;
      if (file == null) return;

      final binPhotos = await getBinPhotos();

      final binPhoto = {
        'id': photo.id,
        'path': file.path,
        'title': await photo.titleAsync,
        'createDateTime': photo.createDateTime.toIso8601String(),
        'width': photo.width,
        'height': photo.height,
        'type': photo.type.name,
        'duration': photo.duration,
        'deletedAt': DateTime.now().toIso8601String(),
        'expiresAt': DateTime.now()
            .add(const Duration(days: _binRetentionDays))
            .toIso8601String(),
      };

      binPhotos.add(binPhoto);
      await saveBinPhotos(binPhotos);

      final appDir = await getApplicationDocumentsDirectory();
      final binDir = Directory('${appDir.path}/bin');
      if (!await binDir.exists()) {
        await binDir.create(recursive: true);
      }

      final fileName = file.path.split('/').last;
      final binFilePath = '${binDir.path}/$fileName';

      await file.copy(binFilePath);
      await PhotoManager.editor.deleteWithIds([photo.id]);
    } catch (e) {
      debugPrint('Error in quick move to trash: $e');
      rethrow;
    }
  }

  // Quick move photo between albums
  static Future<void> quickMovePhotoToAlbum(AssetEntity photo, AssetPathEntity targetAlbum) async {
    try {
      // This is a simplified implementation
      // In a real app, you would implement actual photo moving logic
      debugPrint('Quick moving photo ${photo.id} to album ${targetAlbum.name}');

      // For now, we'll just simulate the operation
      await Future.delayed(const Duration(milliseconds: 100));

    } catch (e) {
      debugPrint('Error in quick move photo to album: $e');
      rethrow;
    }
  }

  // Bin folder functionality
  static Future<void> moveToTrash(AssetEntity photo) async {
    return await quickMoveToTrash(photo);
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
        if (binPhoto['type'] == 'video') {
          await PhotoManager.editor.saveVideo(binFile, title: binPhoto['title'] ?? 'Restored video');
        } else {
          await PhotoManager.editor.saveImageWithPath(
            binFilePath,
            title: binPhoto['title'] ?? 'Restored photo',
          );
        }

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

  static Future<List<AssetEntity>> getAllVideosWithFallback() async {
    try {
      // First try the main method
      List<AssetEntity> videos = await getAllVideos();
      if (videos.isNotEmpty) {
        return videos;
      }

      // Fallback: Try getting from image+video albums
      final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
        type: RequestType.common,
        hasAll: true,
      );

      List<AssetEntity> allVideos = [];

      for (var album in albums) {
        try {
          final count = await album.assetCountAsync;
          if (count > 0) {
            final assets = await album.getAssetListRange(start: 0, end: count);
            // Filter only videos
            final videos = assets.where((asset) => asset.type == AssetType.video).toList();
            for (var video in videos) {
              if (!allVideos.any((v) => v.id == video.id)) {
                allVideos.add(video);
              }
            }
          }
        } catch (e) {
          debugPrint('Error in fallback for album ${album.name}: $e');
          continue;
        }
      }

      // Sort by creation date (newest first)
      allVideos.sort((a, b) => b.createDateTime.compareTo(a.createDateTime));

      debugPrint('Fallback found ${allVideos.length} videos');
      return allVideos;
    } catch (e) {
      debugPrint('Error in getAllVideosWithFallback: $e');
      return [];
    }
  }
}
