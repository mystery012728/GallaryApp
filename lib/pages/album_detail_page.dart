import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:intl/intl.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import '../widgets/photo_grid_item.dart';
import 'image_detail_page.dart';

class AlbumDetailPage extends StatefulWidget {
  final AssetPathEntity album;
  final Map<String, Uint8List?>? thumbnailCache;

  const AlbumDetailPage({
    super.key,
    required this.album,
    this.thumbnailCache,
  });

  @override
  State<AlbumDetailPage> createState() => _AlbumDetailPageState();
}

class _AlbumDetailPageState extends State<AlbumDetailPage> {
  List<AssetEntity>? _photos;
  bool _isLoading = true;
  String? _error;
  Map<String, List<AssetEntity>> _groupedPhotos = {};
  bool _hasChanges = false;

  // Cache for loaded images
  final Map<String, Uint8List> _imageCache = {};

  // Selection functionality
  Set<String> _selectedPhotos = {};
  bool _isSelectionMode = false;

  @override
  void initState() {
    super.initState();
    _isLoading = false; // Start with no loading
    _loadPhotos();
  }

  @override
  void dispose() {
    _imageCache.clear();
    super.dispose();
  }

  void _preloadImages(List<AssetEntity> photos, {int startIndex = 0, int count = 20}) {
    final endIndex = (startIndex + count) < photos.length
        ? startIndex + count
        : photos.length;

    for (int i = startIndex; i < endIndex; i++) {
      _loadAndCacheImage(photos[i]);
    }
  }

  Future<void> _loadAndCacheImage(AssetEntity asset) async {
    if (!_imageCache.containsKey(asset.id)) {
      try {
        final thumbnail = await asset.thumbnailDataWithSize(const ThumbnailSize(300, 300));
        if (thumbnail != null && mounted) {
          setState(() {
            _imageCache[asset.id] = thumbnail;
            if (widget.thumbnailCache != null) {
              widget.thumbnailCache![asset.id] = thumbnail;
            }
          });
        }
      } catch (e) {
        debugPrint('Failed to load thumbnail for ${asset.id}: $e');
      }
    }
  }

  Future<void> _loadPhotos() async {
    try {
      // Don't set loading state - load silently in background
      final totalCount = await widget.album.assetCountAsync;
      final photos = await widget.album.getAssetListRange(start: 0, end: totalCount);

      // Start preloading immediately
      _preloadImages(photos);
      _groupPhotos(photos);

      if (mounted) {
        setState(() {
          _photos = photos;
          _isLoading = false; // Set to false immediately
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load photos: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _groupPhotos(List<AssetEntity> photos) {
    _groupedPhotos = {};

    for (var photo in photos) {
      final date = photo.createDateTime;
      final dateString = DateFormat('yyyy-MM-dd').format(date);

      if (!_groupedPhotos.containsKey(dateString)) {
        _groupedPhotos[dateString] = [];
      }

      _groupedPhotos[dateString]!.add(photo);
    }
  }

  String _formatDateHeader(String dateString) {
    final date = DateTime.parse(dateString);
    final now = DateTime.now();
    final yesterday = DateTime.now().subtract(const Duration(days: 1));

    if (DateFormat('yyyy-MM-dd').format(now) == dateString) {
      return 'Today';
    } else if (DateFormat('yyyy-MM-dd').format(yesterday) == dateString) {
      return 'Yesterday';
    } else if (date.year == now.year) {
      return DateFormat('MMMM d').format(date);
    } else {
      return DateFormat('MMMM d, yyyy').format(date);
    }
  }

  void _openPhoto(AssetEntity photo, {int? index}) {
    final List<AssetEntity> allPhotos = _photos ?? [];
    final int effectiveIndex = index ?? allPhotos.indexOf(photo);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ImageDetailPage(
          photo: photo,
          photoList: allPhotos,
          currentIndex: effectiveIndex,
          thumbnailCache: _imageCache,
          onPhotoDeleted: (photoId) {
            // Instant update without any loading
            _instantUpdateAfterDelete(photoId);
          },
        ),
      ),
    );
  }

  void _startSelection(String photoId) {
    setState(() {
      _isSelectionMode = true;
      _selectedPhotos.add(photoId);
    });
  }

  void _togglePhotoSelection(String photoId) {
    setState(() {
      if (_selectedPhotos.contains(photoId)) {
        _selectedPhotos.remove(photoId);
        if (_selectedPhotos.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedPhotos.add(photoId);
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedPhotos.clear();
      _isSelectionMode = false;
    });
  }

  void _handlePanUpdate(DragUpdateDetails details, String photoId) {
    if (_isSelectionMode && !_selectedPhotos.contains(photoId)) {
      setState(() {
        _selectedPhotos.add(photoId);
      });
    }
  }

  Uint8List? _getCachedImage(String id) {
    if (_imageCache.containsKey(id)) {
      return _imageCache[id];
    } else if (widget.thumbnailCache != null && widget.thumbnailCache!.containsKey(id)) {
      return widget.thumbnailCache![id];
    }
    return null;
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  // Instant update method - no loading, immediate UI change
  void _instantUpdateAfterDelete(String photoId) {
    setState(() {
      if (_photos != null) {
        _photos!.removeWhere((photo) => photo.id == photoId);
        _groupPhotos(_photos!);
        _imageCache.remove(photoId);
        _hasChanges = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, _hasChanges);
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.grey.shade50,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          title: Text(
            _isSelectionMode ? '${_selectedPhotos.length} selected' : widget.album.name,
            style: GoogleFonts.poppins(
              fontSize: _isSelectionMode ? 20.sp : 24.sp,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black87),
            onPressed: () => Navigator.pop(context, _hasChanges),
          ),
          actions: _isSelectionMode ? [
            IconButton(
              icon: const Icon(Icons.share, color: Colors.black87),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Sharing photos')),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.more_vert, color: Colors.black87),
              onPressed: () {
                // Show more options
              },
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.black87),
              onPressed: _clearSelection,
            ),
          ] : [
            IconButton(
              icon: const Icon(Icons.search, color: Colors.black87),
              onPressed: () {
                // Implement search functionality
              },
            ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48.sp, color: Colors.red.shade300),
            SizedBox(height: 16.h),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 16.sp),
            ),
            SizedBox(height: 16.h),
            ElevatedButton(
              onPressed: _loadPhotos,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_photos == null || _photos!.isEmpty) {
      // Show empty grid immediately instead of loading
      return RefreshIndicator(
        onRefresh: _loadPhotos,
        child: GridView.builder(
          padding: EdgeInsets.all(8.w),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 1,
            mainAxisSpacing: 1,
            childAspectRatio: 1.0,
          ),
          itemCount: 0,
          itemBuilder: (context, index) => const SizedBox.shrink(),
        ),
      );
    }

    if (_groupedPhotos.isNotEmpty) {
      final dateKeys = _groupedPhotos.keys.toList()
        ..sort((a, b) => b.compareTo(a));

      return RefreshIndicator(
        onRefresh: _loadPhotos,
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: dateKeys.length,
          itemBuilder: (context, index) {
            final dateKey = dateKeys[index];
            final photosInGroup = _groupedPhotos[dateKey]!;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 12.h),
                  child: Text(
                    _formatDateHeader(dateKey),
                    style: GoogleFonts.poppins(
                      fontSize: 22.sp,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.symmetric(horizontal: 8.w),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 1,
                    mainAxisSpacing: 1,
                    childAspectRatio: 1.0,
                  ),
                  itemCount: photosInGroup.length,
                  itemBuilder: (context, photoIndex) {
                    final photo = photosInGroup[photoIndex];
                    final globalIndex = _photos!.indexOf(photo);

                    // Load thumbnail if not cached
                    if (!_imageCache.containsKey(photo.id)) {
                      _loadAndCacheImage(photo);
                    }

                    return GestureDetector(
                      onTap: () {
                        if (_isSelectionMode) {
                          _togglePhotoSelection(photo.id);
                        } else {
                          _openPhoto(photo, index: globalIndex);
                        }
                      },
                      onLongPress: () {
                        if (!_isSelectionMode) {
                          _startSelection(photo.id);
                        }
                      },
                      onPanUpdate: (details) => _handlePanUpdate(details, photo.id),
                      child: Container(
                        color: Colors.white,
                        child: Stack(
                          children: [
                            _getCachedImage(photo.id) != null
                                ? Image.memory(
                              _getCachedImage(photo.id)!,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                            )
                                : Container(
                              color: Colors.grey.shade200,
                              child: Center(
                                child: Icon(
                                  photo.type == AssetType.video ? Icons.videocam : Icons.photo,
                                  color: Colors.grey.shade400,
                                  size: 24.sp,
                                ),
                              ),
                            ),
                            if (photo.type == AssetType.video)
                              Positioned(
                                bottom: 4.h,
                                right: 4.w,
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 6.w,
                                    vertical: 2.h,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.7),
                                    borderRadius: BorderRadius.circular(4.r),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.play_arrow,
                                        color: Colors.white,
                                        size: 12.sp,
                                      ),
                                      SizedBox(width: 2.w),
                                      Text(
                                        _formatDuration(photo.duration),
                                        style: GoogleFonts.inter(
                                          color: Colors.white,
                                          fontSize: 10.sp,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            if (photo.type == AssetType.video)
                              Center(
                                child: Container(
                                  width: 30.w,
                                  height: 30.h,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.6),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.play_arrow,
                                    color: Colors.white,
                                    size: 18.sp,
                                  ),
                                ),
                              ),
                            if (_selectedPhotos.contains(photo.id))
                              Positioned(
                                top: 4.h,
                                right: 4.w,
                                child: Container(
                                  width: 20.w,
                                  height: 20.h,
                                  decoration: BoxDecoration(
                                    color: Colors.blue,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2),
                                  ),
                                  child: Icon(
                                    Icons.check,
                                    color: Colors.white,
                                    size: 12.sp,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                SizedBox(height: 20.h),
              ],
            );
          },
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadPhotos,
      child: GridView.builder(
        padding: EdgeInsets.all(8.w),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 1,
          mainAxisSpacing: 1,
          childAspectRatio: 1.0,
        ),
        itemCount: 0,
        itemBuilder: (context, index) => const SizedBox.shrink(),
      ),
    );
  }
}
