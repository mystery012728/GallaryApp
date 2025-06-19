import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import '../services/photo_service.dart';

class ImageDetailPage extends StatefulWidget {
  final AssetEntity photo;
  final List<AssetEntity>? photoList;
  final String? folderPath;
  final int currentIndex;
  final VoidCallback? onPhotoDeleted;
  final Map<String, Uint8List>? thumbnailCache;

  const ImageDetailPage({
    super.key,
    required this.photo,
    this.photoList,
    this.folderPath,
    this.currentIndex = 0,
    this.onPhotoDeleted,
    this.thumbnailCache,
  });

  @override
  State<ImageDetailPage> createState() => _ImageDetailPageState();
}

class _ImageDetailPageState extends State<ImageDetailPage> with TickerProviderStateMixin {
  bool _showInfo = false, _isLoading = false, _showControls = true;
  late AnimationController _infoController, _controlsController, _zoomController, _deleteController;
  late Animation<double> _infoAnimation, _controlsAnimation, _deleteAnimation;
  late PageController _pageController;
  late TransformationController _transformationController;
  late Animation<Matrix4> _zoomAnimation;

  List<AssetEntity> _allPhotos = [];
  int _currentIndex = 0;
  bool _isLoadingPhotos = true;

  // Enhanced caching system
  static final Map<String, Uint8List> _globalImageCache = {};
  static final Map<String, File> _fileCache = {};
  static const int _maxCacheSize = 50; // Limit cache size

  // Preloading management
  final Set<String> _preloadingImages = {};
  static const int _preloadRange = 2; // Load 2 images ahead/behind

  // Delete gesture tracking
  bool _isLongPressing = false, _isDragging = false;
  double _deleteProgress = 0.0;
  Offset? _longPressStart;

  @override
  void initState() {
    super.initState();
    _initControllers();
    _initializePhotos();
  }

  void _initControllers() {
    _infoController = AnimationController(duration: const Duration(milliseconds: 300), vsync: this);
    _controlsController = AnimationController(duration: const Duration(milliseconds: 300), vsync: this, value: 1.0);
    _zoomController = AnimationController(duration: const Duration(milliseconds: 300), vsync: this);
    _deleteController = AnimationController(duration: const Duration(milliseconds: 2000), vsync: this);

    _infoAnimation = CurvedAnimation(parent: _infoController, curve: Curves.easeInOut);
    _controlsAnimation = CurvedAnimation(parent: _controlsController, curve: Curves.easeInOut);
    _deleteAnimation = CurvedAnimation(parent: _deleteController, curve: Curves.easeInOut);

    _transformationController = TransformationController();
    _currentIndex = widget.currentIndex;
    _pageController = PageController(initialPage: _currentIndex);
  }

  void _initializePhotos() {
    if (widget.photoList?.isNotEmpty == true) {
      _allPhotos = widget.photoList!;
      _isLoadingPhotos = false;
      _preloadImages(_currentIndex);
    } else {
      _allPhotos = [widget.photo];
      _loadPhotosFromFolder();
    }

    // Initialize cache with provided thumbnails
    if (widget.thumbnailCache != null) {
      _globalImageCache.addAll(widget.thumbnailCache!);
    }
  }

  // Enhanced preloading with better range management
  void _preloadImages(int centerIndex) {
    final Set<int> indicesToLoad = {};

    // Load current image first
    indicesToLoad.add(centerIndex);

    // Load surrounding images
    for (int i = 1; i <= _preloadRange; i++) {
      if (centerIndex - i >= 0) indicesToLoad.add(centerIndex - i);
      if (centerIndex + i < _allPhotos.length) indicesToLoad.add(centerIndex + i);
    }

    // Load in order of priority (current, next, prev, etc.)
    for (final index in indicesToLoad) {
      if (index >= 0 && index < _allPhotos.length) {
        _loadImageWithPriority(_allPhotos[index], index == centerIndex);
      }
    }
  }

  // Priority-based image loading
  Future<void> _loadImageWithPriority(AssetEntity asset, bool isHighPriority) async {
    if (_globalImageCache.containsKey(asset.id) || _preloadingImages.contains(asset.id)) {
      return;
    }

    _preloadingImages.add(asset.id);

    try {
      // Try to get file path first (fastest method)
      final file = await asset.file;
      if (file != null && await file.exists()) {
        _fileCache[asset.id] = file;
        if (mounted) setState(() {});
        return;
      }

      // Fallback to bytes with appropriate quality based on priority
      Uint8List? imageData;
      if (isHighPriority) {
        // High quality for current image
        imageData = await asset.originBytes;
      } else {
        // Medium quality for preloaded images
        imageData = await asset.thumbnailDataWithSize(const ThumbnailSize(1024, 1024));
      }

      if (imageData != null && mounted) {
        // Manage cache size
        if (_globalImageCache.length >= _maxCacheSize) {
          _cleanupCache();
        }

        setState(() {
          _globalImageCache[asset.id] = imageData!;
        });
      }
    } catch (e) {
      print('Failed to load image for ${asset.id}: $e');
    } finally {
      _preloadingImages.remove(asset.id);
    }
  }

  // Cache cleanup to prevent memory issues
  void _cleanupCache() {
    if (_globalImageCache.length <= _maxCacheSize) return;

    // Remove oldest entries (simple FIFO)
    final keysToRemove = _globalImageCache.keys.take(_globalImageCache.length - _maxCacheSize + 10);
    for (final key in keysToRemove) {
      _globalImageCache.remove(key);
    }
  }

  Future<void> _loadPhotosFromFolder() async {
    if (!mounted) return;
    setState(() => _isLoadingPhotos = true);

    try {
      AssetPathEntity? folder = await _getFolderForPhoto(widget.photo);
      if (folder != null) {
        // Load in batches for better performance
        const batchSize = 1000;
        List<AssetEntity> assets = await folder.getAssetListRange(start: 0, end: batchSize);

        int index = assets.indexWhere((asset) => asset.id == widget.photo.id);

        if (index >= 0 && mounted) {
          setState(() {
            _allPhotos = assets;
            _currentIndex = index;
            _pageController = PageController(initialPage: _currentIndex);
          });
          _preloadImages(_currentIndex);
        }
      }
    } catch (e) {
      print('Error loading photos: $e');
    } finally {
      if (mounted) setState(() => _isLoadingPhotos = false);
    }
  }

  Future<AssetPathEntity?> _getFolderForPhoto(AssetEntity photo) async {
    try {
      List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(type: RequestType.image);

      if (widget.folderPath != null) {
        for (var album in albums) {
          if (album.name == widget.folderPath) return album;
        }
      }

      // More efficient folder search
      for (var album in albums) {
        if (album.isAll) continue; // Skip "All Photos" for now

        List<AssetEntity> assets = await album.getAssetListRange(start: 0, end: 100);
        if (assets.any((asset) => asset.id == photo.id)) return album;
      }

      return albums.firstWhere((album) => album.isAll, orElse: () => albums.first);
    } catch (e) {
      print('Error finding folder: $e');
      return null;
    }
  }

  @override
  void dispose() {
    _infoController.dispose();
    _controlsController.dispose();
    _pageController.dispose();
    _transformationController.dispose();
    _zoomController.dispose();
    _deleteController.dispose();
    super.dispose();
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
      if (_showControls) {
        _controlsController.forward();
      } else {
        _controlsController.reverse();
        if (_showInfo) {
          _showInfo = false;
          _infoController.reverse();
        }
      }
    });
  }

  void _toggleInfo() {
    setState(() => _showInfo = !_showInfo);
    _showInfo ? _infoController.forward() : _infoController.reverse();
  }

  void _handleDoubleTap() {
    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    Matrix4 targetTransform;

    if (currentScale > 1.0) {
      targetTransform = Matrix4.identity();
    } else {
      final screenSize = MediaQuery.of(context).size;
      final center = Offset(screenSize.width / 2, screenSize.height / 2);
      targetTransform = Matrix4.identity()
        ..translate(center.dx, center.dy)
        ..scale(2.0)
        ..translate(-center.dx, -center.dy);
    }

    _zoomAnimation = Matrix4Tween(begin: _transformationController.value, end: targetTransform)
        .animate(_zoomController);

    _zoomController.reset();
    _zoomController.forward().then((_) => _transformationController.value = targetTransform);
    _zoomAnimation.addListener(() => _transformationController.value = _zoomAnimation.value);
  }

  void _handleLongPressStart(LongPressStartDetails details) {
    setState(() {
      _isLongPressing = true;
      _longPressStart = details.globalPosition;
      _isDragging = false;
      _deleteProgress = 0.0;
    });
    _deleteController.forward();
  }

  void _handleLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    if (!_isLongPressing || _longPressStart == null) return;

    final deltaY = details.globalPosition.dy - _longPressStart!.dy;
    if (deltaY > 20) {
      setState(() {
        _isDragging = true;
        _deleteProgress = (deltaY - 20).clamp(0.0, 100.0) / 100.0;
      });
    }
  }

  void _handleLongPressEnd(LongPressEndDetails details) {
    if (_isDragging && _deleteProgress >= 1.0) _deleteImage();

    setState(() {
      _isLongPressing = false;
      _isDragging = false;
      _deleteProgress = 0.0;
      _longPressStart = null;
    });
    _deleteController.reverse();
  }

  Future<void> _shareImage() async {
    try {
      setState(() => _isLoading = true);

      final currentPhoto = _allPhotos[_currentIndex];

      // Try file cache first
      if (_fileCache.containsKey(currentPhoto.id)) {
        await Share.shareXFiles([XFile(_fileCache[currentPhoto.id]!.path)]);
        return;
      }

      // Try memory cache
      if (_globalImageCache.containsKey(currentPhoto.id)) {
        final imageData = _globalImageCache[currentPhoto.id]!;
        final tempDir = Directory.systemTemp;
        final tempFile = File('${tempDir.path}/temp_image_${currentPhoto.id}.jpg');
        await tempFile.writeAsBytes(imageData);
        await Share.shareXFiles([XFile(tempFile.path)]);
        tempFile.deleteSync();
        return;
      }

      // Fallback to direct file access
      final file = await currentPhoto.file;
      if (file != null) await Share.shareXFiles([XFile(file.path)]);

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to share: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteImage() async {
    final confirmed = await _showDeleteDialog();
    if (confirmed != true) return;

    try {
      setState(() => _isLoading = true);

      final currentPhoto = _allPhotos[_currentIndex];
      await PhotoService.moveToTrash(currentPhoto);

      // Clean up caches
      _globalImageCache.remove(currentPhoto.id);
      _fileCache.remove(currentPhoto.id);

      if (mounted) {
        setState(() {
          _allPhotos.removeAt(_currentIndex);
          if (_currentIndex >= _allPhotos.length) _currentIndex = _allPhotos.length - 1;

          if (_allPhotos.isEmpty) {
            widget.onPhotoDeleted?.call();
            Navigator.of(context).pop(true);
          } else {
            _pageController.jumpToPage(_currentIndex);
            _preloadImages(_currentIndex);
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
      }
    }
  }

  Future<bool?> _showDeleteDialog() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        title: Text('Move to Bin', style: GoogleFonts.poppins(fontSize: 20.sp, fontWeight: FontWeight.w600)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60.w, height: 60.w,
              decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(Icons.delete_outline, size: 30.sp, color: Colors.red),
            ),
            SizedBox(height: 16.h),
            Text('Move this photo to the bin?',
                style: GoogleFonts.poppins(fontSize: 16.sp), textAlign: TextAlign.center),
            SizedBox(height: 8.h),
            Text('It will be automatically deleted after 30 days',
                style: GoogleFonts.poppins(fontSize: 14.sp, color: Colors.grey), textAlign: TextAlign.center),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('CANCEL', style: GoogleFonts.poppins(fontSize: 14.sp, fontWeight: FontWeight.w500)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('MOVE TO BIN', style: GoogleFonts.poppins(fontSize: 14.sp, fontWeight: FontWeight.w500)),
          ),
        ],
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actionsPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      ),
    );
  }

  Widget _buildPhotoView(AssetEntity photo) {
    return GestureDetector(
      onTap: _toggleControls,
      onDoubleTap: _handleDoubleTap,
      onLongPressStart: _handleLongPressStart,
      onLongPressMoveUpdate: _handleLongPressMoveUpdate,
      onLongPressEnd: _handleLongPressEnd,
      child: Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                transformationController: _transformationController,
                minScale: 0.5, maxScale: 4.0,
                child: _buildOptimizedImageWidget(photo),
              ),
            ),
            if (_isLongPressing) _buildDeleteOverlay(),
          ],
        ),
      ),
    );
  }

  // Optimized image widget with better caching strategy
  Widget _buildOptimizedImageWidget(AssetEntity photo) {
    // Priority 1: File cache (fastest)
    if (_fileCache.containsKey(photo.id)) {
      return Hero(
        tag: 'photo_${photo.id}',
        child: Image.file(
          _fileCache[photo.id]!,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          alignment: Alignment.center,
          errorBuilder: (_, __, ___) => _buildErrorWidget(),
        ),
      );
    }

    // Priority 2: Memory cache
    if (_globalImageCache.containsKey(photo.id)) {
      return Hero(
        tag: 'photo_${photo.id}',
        child: Image.memory(
          _globalImageCache[photo.id]!,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          alignment: Alignment.center,
          errorBuilder: (_, __, ___) => _buildErrorWidget(),
        ),
      );
    }

    // Priority 3: Load image and show placeholder
    _loadImageWithPriority(photo, true);

    return Hero(
      tag: 'photo_${photo.id}',
      child: FutureBuilder<File?>(
        future: photo.file,
        builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data != null) {
            // Cache the file for future use
            _fileCache[photo.id] = snapshot.data!;

            return Image.file(
              snapshot.data!,
              fit: BoxFit.contain,
              gaplessPlayback: true,
              alignment: Alignment.center,
              errorBuilder: (_, __, ___) => _buildThumbnailFallback(photo),
            );
          }

          return _buildThumbnailFallback(photo);
        },
      ),
    );
  }

  // Fallback to thumbnail if full image fails
  Widget _buildThumbnailFallback(AssetEntity photo) {
    return FutureBuilder<Uint8List?>(
      future: photo.thumbnailDataWithSize(const ThumbnailSize(512, 512)),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          return Image.memory(
            snapshot.data!,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            alignment: Alignment.center,
            errorBuilder: (_, __, ___) => _buildErrorWidget(),
          );
        }

        return Container(
          width: double.infinity,
          height: double.infinity,
          color: Colors.black,
          child: Center(
            child: CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 2.w,
            ),
          ),
        );
      },
    );
  }

  Widget _buildDeleteOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.3),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100.w, height: 100.h,
                decoration: BoxDecoration(color: Colors.red.withOpacity(0.8), shape: BoxShape.circle),
                child: Stack(
                  children: [
                    Center(child: Icon(Icons.delete_outline, color: Colors.white, size: 40.sp)),
                    Positioned.fill(
                      child: CircularProgressIndicator(
                        value: _deleteProgress, strokeWidth: 4.w,
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                        backgroundColor: Colors.white.withOpacity(0.3),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 16.h),
              Text(
                _isDragging ? 'Swipe down to delete' : 'Hold and swipe down',
                style: GoogleFonts.inter(color: Colors.white, fontSize: 16.sp, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Container(
      width: double.infinity, height: double.infinity,
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: Colors.red, size: 48.sp),
            SizedBox(height: 16.h),
            Text('Failed to load image',
                style: GoogleFonts.inter(color: Colors.white, fontSize: 16.sp, fontWeight: FontWeight.w600)),
            SizedBox(height: 8.h),
            Text('The image may be corrupted or unavailable',
                style: GoogleFonts.inter(color: Colors.white70, fontSize: 14.sp), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String label, Color color, VoidCallback onTap) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color, foregroundColor: Colors.white,
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: FadeTransition(
          opacity: _controlsAnimation,
          child: AppBar(
            backgroundColor: Colors.black.withOpacity(0.5),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () {
                widget.onPhotoDeleted?.call();
                Navigator.of(context).pop();
              },
            ),
            title: Text('${_currentIndex + 1} / ${_allPhotos.length}',
                style: GoogleFonts.poppins(fontSize: 16.sp, color: Colors.white)),
            centerTitle: true,
            actions: [
              IconButton(
                icon: Icon(_showInfo ? Icons.info : Icons.info_outline, color: Colors.white),
                onPressed: _toggleInfo,
              ),
              IconButton(icon: const Icon(Icons.share, color: Colors.white), onPressed: _shareImage),
              IconButton(icon: const Icon(Icons.delete_outline, color: Colors.white), onPressed: _deleteImage),
            ],
          ),
        ),
      ),
      body: Stack(
        children: [
          if (_isLoadingPhotos)
            Container(
              width: double.infinity, height: double.infinity,
              color: Colors.black,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Colors.white, strokeWidth: 3.w),
                    SizedBox(height: 16.h),
                    Text('Loading photos...',
                        style: GoogleFonts.poppins(color: Colors.white, fontSize: 18.sp, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            )
          else if (_allPhotos.isNotEmpty)
            PageView.builder(
              controller: _pageController,
              itemCount: _allPhotos.length,
              physics: const BouncingScrollPhysics(),
              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                  if (_showInfo) {
                    _showInfo = false;
                    _infoController.reverse();
                  }
                  _transformationController.value = Matrix4.identity();
                });

                // Preload surrounding images
                _preloadImages(index);
              },
              itemBuilder: (context, index) => _buildPhotoView(_allPhotos[index]),
            )
          else
            _buildEmptyState(),

          // Navigation buttons
          if (_allPhotos.length > 1) _buildNavigationButtons(),

          // Info overlay
          _buildInfoOverlay(),

          // Loading overlay
          if (_isLoading) _buildLoadingOverlay(),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity, height: double.infinity,
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.photo_library_outlined, color: Colors.white54, size: 64.sp),
            SizedBox(height: 16.h),
            Text('No photos available',
                style: GoogleFonts.poppins(color: Colors.white, fontSize: 18.sp, fontWeight: FontWeight.w600)),
            SizedBox(height: 8.h),
            Text('The photo gallery is empty', style: GoogleFonts.inter(color: Colors.white70, fontSize: 14.sp)),
          ],
        ),
      ),
    );
  }

  Widget _buildNavigationButtons() {
    return FadeTransition(
      opacity: _controlsAnimation,
      child: Positioned(
        left: 0, right: 0, bottom: 80.h,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            AnimatedOpacity(
              opacity: _currentIndex > 0 ? 0.7 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                margin: EdgeInsets.only(left: 16.w),
                decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), shape: BoxShape.circle),
                child: IconButton(
                  icon: Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20.sp),
                  onPressed: _currentIndex > 0
                      ? () => _pageController.animateToPage(_currentIndex - 1,
                      duration: const Duration(milliseconds: 300), curve: Curves.easeInOut)
                      : null,
                ),
              ),
            ),
            AnimatedOpacity(
              opacity: _currentIndex < _allPhotos.length - 1 ? 0.7 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                margin: EdgeInsets.only(right: 16.w),
                decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), shape: BoxShape.circle),
                child: IconButton(
                  icon: Icon(Icons.arrow_forward_ios, color: Colors.white, size: 20.sp),
                  onPressed: _currentIndex < _allPhotos.length - 1
                      ? () => _pageController.animateToPage(_currentIndex + 1,
                      duration: const Duration(milliseconds: 300), curve: Curves.easeInOut)
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoOverlay() {
    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(_infoAnimation),
        child: FadeTransition(
          opacity: _infoAnimation,
          child: Container(
            padding: EdgeInsets.all(16.w),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter, end: Alignment.topCenter,
                colors: [Colors.black.withOpacity(0.9), Colors.black.withOpacity(0.7), Colors.transparent],
                stops: const [0.4, 0.8, 1.0],
              ),
            ),
            child: _allPhotos.isNotEmpty && _currentIndex < _allPhotos.length
                ? _buildInfoContent()
                : const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoContent() {
    final currentPhoto = _allPhotos[_currentIndex];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(DateFormat('MMMM d, yyyy - h:mm a').format(currentPhoto.createDateTime),
            style: GoogleFonts.poppins(color: Colors.white, fontSize: 16.sp, fontWeight: FontWeight.w600)),
        SizedBox(height: 8.h),
        Text('${currentPhoto.width} × ${currentPhoto.height}',
            style: GoogleFonts.poppins(color: Colors.white70, fontSize: 14.sp)),
        SizedBox(height: 8.h),
        FutureBuilder<String?>(
          future: currentPhoto.titleAsync,
          builder: (context, snapshot) {
            if (!snapshot.hasData || snapshot.data == null) return const SizedBox.shrink();
            return Text(snapshot.data!, style: GoogleFonts.poppins(color: Colors.white70, fontSize: 14.sp));
          },
        ),
        SizedBox(height: 16.h),
        Container(
          padding: EdgeInsets.all(12.w),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(8.r)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Gestures:', style: GoogleFonts.poppins(color: Colors.white, fontSize: 14.sp, fontWeight: FontWeight.w600)),
              SizedBox(height: 4.h),
              ...[
                '• Double tap to zoom in/out',
                '• Hold and swipe down to delete',
                '• Swipe left/right to navigate',
              ].map((text) => Text(text, style: GoogleFonts.inter(color: Colors.white70, fontSize: 12.sp))),
            ],
          ),
        ),
        SizedBox(height: 24.h),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildActionButton(Icons.share, 'Share', Colors.blue, _shareImage),
            _buildActionButton(Icons.edit, 'Edit', Colors.green, () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Edit feature not implemented')));
            }),
            _buildActionButton(Icons.delete_outline, 'Delete', Colors.red, _deleteImage),
          ],
        ),
      ],
    );
  }

  Widget _buildLoadingOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.5),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white, strokeWidth: 3.w),
            SizedBox(height: 16.h),
            Text('Processing...', style: GoogleFonts.inter(color: Colors.white, fontSize: 14.sp)),
          ],
        ),
      ),
    );
  }
}