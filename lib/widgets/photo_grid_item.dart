import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_blurhash/flutter_blurhash.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shimmer/shimmer.dart';

class PhotoGridItem extends StatelessWidget {
  final dynamic photo; // Can be AssetEntity or Map for bin photos
  final VoidCallback onTap;
  final bool showDate;
  final Map<String, Uint8List?>? thumbnailCache;
  final Uint8List? cachedImage; // Added for direct cached image passing
  final bool isBinPhoto;
  final bool isSelected;
  final VoidCallback? onLongPress;
  final String? blurhash;

  const PhotoGridItem({
    super.key,
    required this.photo,
    required this.onTap,
    this.showDate = false,
    this.thumbnailCache,
    this.cachedImage, // New parameter
    this.isBinPhoto = false,
    this.isSelected = false,
    this.onLongPress,
    this.blurhash,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Hero(
        tag: isBinPhoto ? 'bin_photo_${photo['id']}' : 'photo_${photo.id}',
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8.r),
            border: isSelected
                ? Border.all(color: Theme.of(context).primaryColor, width: 2)
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8.r),
            child: isBinPhoto
                ? FutureBuilder<String>(
                    future: () async {
                      final appDir = await getApplicationDocumentsDirectory();
                      final binDir = Directory('${appDir.path}/bin');
                      final fileName = photo['path'].split('/').last;
                      return '${binDir.path}/$fileName';
                    }(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return _buildShimmer();
                      }
                      if (snapshot.hasError || !snapshot.hasData) {
                        return const Center(
                          child: Icon(
                            Icons.error,
                            color: Colors.red,
                            size: 24,
                          ),
                        );
                      }
                      return Image.file(
                        File(snapshot.data!),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return const Center(
                            child: Icon(
                              Icons.error,
                              color: Colors.red,
                              size: 24,
                            ),
                          );
                        },
                      );
                    },
                  )
                : FutureBuilder<Uint8List?>(
                    future: photo.thumbnailData,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return _buildShimmer();
                      }
                      if (snapshot.hasError || !snapshot.hasData) {
                        return const Center(
                          child: Icon(
                            Icons.error,
                            color: Colors.red,
                            size: 24,
                          ),
                        );
                      }
                      return Image.memory(
                        snapshot.data!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return const Center(
                            child: Icon(
                              Icons.error,
                              color: Colors.red,
                              size: 24,
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildShimmer() {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: Container(
        color: Colors.white,
      ),
    );
  }

  Widget _buildThumbnail() {
    // First priority: directly provided cached image
    if (cachedImage != null) {
      return Image.memory(
        cachedImage!,
        fit: BoxFit.cover,
      );
    }

    // Second priority: thumbnail from cache
    if (thumbnailCache != null) {
      final String id = isBinPhoto ? photo['id'] : photo.id;
      if (thumbnailCache!.containsKey(id) && thumbnailCache![id] != null) {
        return Image.memory(
          thumbnailCache![id]!,
          fit: BoxFit.cover,
        );
      }
    }

    // For bin photos, use file path
    if (isBinPhoto) {
      return Image.file(
        File(photo['path']),
        fit: BoxFit.cover,
      );
    }

    // For regular photos, use thumbnail data
    return FutureBuilder<Uint8List?>(
      future: photo.thumbnailDataWithSize(const ThumbnailSize(200, 200)),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildShimmer();
        }
        if (snapshot.connectionState == ConnectionState.done &&
            snapshot.data != null) {
          return Image.memory(
            snapshot.data!,
            fit: BoxFit.cover,
          );
        }
        return _buildShimmer();
      },
    );
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}';
  }
}
