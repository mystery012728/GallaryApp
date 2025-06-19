import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:intl/intl.dart';
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

  // For pagination
  int _currentPage = 0;
  final int _pageSize = 100;
  bool _hasMorePhotos = true;
  bool _isLoadingMore = false;
  final ScrollController _scrollController = ScrollController();

  // Cache for loaded images
  final Map<String, Uint8List> _imageCache = {};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_scrollListener);
    _loadPhotos();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _imageCache.clear(); // Clear the cache when the page is disposed
    super.dispose();
  }

  void _scrollListener() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 500 &&
        !_isLoadingMore &&
        _hasMorePhotos) {
      _loadMorePhotos();
    }
  }

  // Preload images for smoother experience
  void _preloadImages(List<AssetEntity> photos, {int startIndex = 0, int count = 10}) {
    final endIndex = (startIndex + count) < photos.length
        ? startIndex + count
        : photos.length;

    for (int i = startIndex; i < endIndex; i++) {
      _loadAndCacheImage(photos[i]);
    }
  }

  Future<void> _loadAndCacheImage(AssetEntity asset) async {
    if (!_imageCache.containsKey(asset.id)) {
      // First try to get the thumbnail for faster loading
      final thumbnail = await asset.thumbnailDataWithSize(const ThumbnailSize(200, 200));
      if (thumbnail != null) {
        if (mounted) {
          setState(() {
            _imageCache[asset.id] = thumbnail;

            // Also update the thumbnail cache if it exists
            if (widget.thumbnailCache != null) {
              widget.thumbnailCache![asset.id] = thumbnail;
            }
          });
        }
      }

      // Then load a higher quality thumbnail in the background if needed
      try {
        final mediumQuality = await asset.thumbnailDataWithSize(const ThumbnailSize(500, 500));
        if (mediumQuality != null && mounted) {
          setState(() {
            _imageCache[asset.id] = mediumQuality;
          });
        }
      } catch (e) {
        // If higher quality thumbnail fails, we still have the basic thumbnail
        debugPrint('Failed to load higher quality thumbnail for ${asset.id}: $e');
      }
    }
  }

  Future<void> _loadMorePhotos() async {
    if (_isLoadingMore || !_hasMorePhotos) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final nextPage = _currentPage + 1;
      final start = nextPage * _pageSize;
      final end = start + _pageSize;

      final morePhotos = await widget.album.getAssetListRange(
        start: start,
        end: end,
      );

      if (morePhotos.isEmpty) {
        setState(() {
          _hasMorePhotos = false;
          _isLoadingMore = false;
        });
        return;
      }

      // Preload thumbnails for new photos
      _preloadImages(morePhotos);

      setState(() {
        _photos = [...?_photos, ...morePhotos];
        _currentPage = nextPage;
        _groupPhotos(_photos!);
      });
    } catch (e) {
      debugPrint('Error loading more photos: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    }
  }

  Future<void> _loadPhotos() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final photos = await widget.album.getAssetListRange(
        start: 0,
        end: _pageSize,
      );

      // Preload thumbnails for faster display
      _preloadImages(photos);

      // Group photos by date
      _groupPhotos(photos);

      setState(() {
        _photos = photos;
        _isLoading = false;
        _currentPage = 0;
        _hasMorePhotos = photos.length >= _pageSize;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load photos: $e';
        _isLoading = false;
      });
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
      return DateFormat('MMMM d').format(date); // e.g. "March 15"
    } else {
      return DateFormat('MMMM d, yyyy').format(date); // e.g. "March 15, 2023"
    }
  }

  void _openPhoto(AssetEntity photo, {int? index}) {
    // Always use the complete photo list for consistent sliding behavior
    final List<AssetEntity> allPhotos = _photos ?? [];

    // Find the index in the complete list if not provided
    final int effectiveIndex = index ?? allPhotos.indexOf(photo);

    // Pre-cache more images in both directions for smoother sliding
    final int preloadStart = (effectiveIndex - 5) < 0 ? 0 : effectiveIndex - 5;
    final int preloadCount = 10; // Preload 10 images (5 before, 5 after)
    _preloadImages(allPhotos, startIndex: preloadStart, count: preloadCount);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ImageDetailPage(
          photo: photo,
          photoList: allPhotos,
          currentIndex: effectiveIndex,
          thumbnailCache: _imageCache, // Pass the cache to reduce loading time
          onPhotoDeleted: () {
            setState(() {
              _hasChanges = true;
            });
            _loadPhotos(); // Reload photos when returning
          },
        ),
      ),
    );
  }

  Uint8List? _getCachedImage(String id) {
    // First try the internal cache
    if (_imageCache.containsKey(id)) {
      return _imageCache[id];
    }
    // Then try the provided thumbnail cache if available
    else if (widget.thumbnailCache != null && widget.thumbnailCache!.containsKey(id)) {
      return widget.thumbnailCache![id];
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, _hasChanges);
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.album.name,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.search),
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
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadPhotos,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_photos == null || _photos!.isEmpty) {
      return const Center(
        child: Text('No photos in this album'),
      );
    }

    // If we have grouped photos, show them in sections
    if (_groupedPhotos.isNotEmpty) {
      final dateKeys = _groupedPhotos.keys.toList()
        ..sort((a, b) => b.compareTo(a));

      return RefreshIndicator(
        onRefresh: _loadPhotos,
        child: ListView.builder(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount:
          dateKeys.length + (_isLoadingMore || _hasMorePhotos ? 1 : 0),
          itemBuilder: (context, index) {
            // Show loading indicator at the bottom
            if (index == dateKeys.length) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: Center(
                  child: _isLoadingMore
                      ? const CircularProgressIndicator()
                      : const SizedBox.shrink(),
                ),
              );
            }

            final dateKey = dateKeys[index];
            final photosInGroup = _groupedPhotos[dateKey]!;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    _formatDateHeader(dateKey),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 2,
                    mainAxisSpacing: 2,
                  ),
                  itemCount: photosInGroup.length,
                  itemBuilder: (context, photoIndex) {
                    final photo = photosInGroup[photoIndex];
                    // Find the index in the complete photos list for consistent navigation
                    final globalIndex = _photos!.indexOf(photo);

                    return PhotoGridItem(
                      photo: photo,
                      cachedImage: _getCachedImage(photo.id),
                      onTap: () => _openPhoto(
                        photo,
                        index: globalIndex,
                      ),
                    );
                  },
                ),
              ],
            );
          },
        ),
      );
    }

    // Fallback to simple grid if grouping failed
    return RefreshIndicator(
      onRefresh: _loadPhotos,
      child: GridView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(2.0),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 2.0,
          mainAxisSpacing: 2.0,
        ),
        itemCount: _photos!.length + (_isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _photos!.length) {
            return const Center(child: CircularProgressIndicator());
          }

          final photo = _photos![index];
          return PhotoGridItem(
            photo: photo,
            cachedImage: _getCachedImage(photo.id),
            onTap: () => _openPhoto(photo, index: index),
          );
        },
      ),
    );
  }
}