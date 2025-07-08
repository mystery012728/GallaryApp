import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../services/photo_service.dart';
import 'package:flutter/services.dart';

class ImageDetailPage extends StatefulWidget {
  final AssetEntity photo;
  final List<AssetEntity>? photoList;
  final String? folderPath;
  final int currentIndex;
  final Function(String)? onPhotoDeleted;
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
  bool _showInfo = false, _showControls = true;
  late AnimationController _infoController, _controlsController, _zoomController, _deleteController, _floatController;
  late Animation<double> _infoAnimation, _controlsAnimation, _deleteAnimation, _floatAnimation;
  late PageController _pageController;
  late TransformationController _transformationController;
  late Animation<Matrix4> _zoomAnimation;

  List<AssetEntity> _allPhotos = [];
  int _currentIndex = 0;

  // Enhanced caching system
  static final Map<String, Uint8List> _globalImageCache = {};
  static final Map<String, File> _fileCache = {};
  static const int _maxCacheSize = 50;

  // Preloading management
  final Set<String> _preloadingImages = {};
  static const int _preloadRange = 2;

  // Delete gesture tracking
  bool _isLongPressing = false, _isDragging = false;
  double _deleteProgress = 0.0;
  Offset? _longPressStart;
  bool _isFloating = false;

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
    _deleteController = AnimationController(duration: const Duration(milliseconds: 1200), vsync: this);
    _floatController = AnimationController(duration: const Duration(milliseconds: 300), vsync: this);

    _infoAnimation = CurvedAnimation(parent: _infoController, curve: Curves.easeInOut);
    _controlsAnimation = CurvedAnimation(parent: _controlsController, curve: Curves.easeInOut);
    _deleteAnimation = CurvedAnimation(parent: _deleteController, curve: Curves.easeInOut);
    _floatAnimation = CurvedAnimation(parent: _floatController, curve: Curves.easeOutBack);

    _transformationController = TransformationController();
    _currentIndex = widget.currentIndex;
    _pageController = PageController(initialPage: _currentIndex);
  }

  void _initializePhotos() {
    if (widget.photoList?.isNotEmpty == true) {
      _allPhotos = widget.photoList!;
      _preloadImages(_currentIndex);
    } else {
      _allPhotos = [widget.photo];
      _loadPhotosFromFolder();
    }

    if (widget.thumbnailCache != null) {
      _globalImageCache.addAll(widget.thumbnailCache!);
    }
  }

  void _preloadImages(int centerIndex) {
    final Set<int> indicesToLoad = {};
    indicesToLoad.add(centerIndex);

    for (int i = 1; i <= _preloadRange; i++) {
      if (centerIndex - i >= 0) indicesToLoad.add(centerIndex - i);
      if (centerIndex + i < _allPhotos.length) indicesToLoad.add(centerIndex + i);
    }

    for (final index in indicesToLoad) {
      if (index >= 0 && index < _allPhotos.length) {
        _loadImageWithPriority(_allPhotos[index], index == centerIndex);
      }
    }
  }

  Future<void> _loadImageWithPriority(AssetEntity asset, bool isHighPriority) async {
    if (_globalImageCache.containsKey(asset.id) || _preloadingImages.contains(asset.id)) {
      return;
    }

    _preloadingImages.add(asset.id);

    try {
      final file = await asset.file;
      if (file != null && await file.exists()) {
        _fileCache[asset.id] = file;
        if (mounted) setState(() {});
        return;
      }

      Uint8List? imageData;
      if (isHighPriority) {
        imageData = await asset.originBytes;
      } else {
        imageData = await asset.thumbnailDataWithSize(const ThumbnailSize(1024, 1024));
      }

      if (imageData != null && mounted) {
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

  void _cleanupCache() {
    if (_globalImageCache.length <= _maxCacheSize) return;

    final keysToRemove = _globalImageCache.keys.take(_globalImageCache.length - _maxCacheSize + 10);
    for (final key in keysToRemove) {
      _globalImageCache.remove(key);
    }
  }

  Future<void> _loadPhotosFromFolder() async {
    try {
      AssetPathEntity? folder = await _getFolderForPhoto(widget.photo);
      if (folder != null) {
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
    }
  }

  Future<AssetPathEntity?> _getFolderForPhoto(AssetEntity photo) async {
    try {
      List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
          type: photo.type == AssetType.video ? RequestType.video : RequestType.image
      );

      if (widget.folderPath != null) {
        for (var album in albums) {
          if (album.name == widget.folderPath) return album;
        }
      }

      for (var album in albums) {
        if (album.isAll) continue;

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
    _floatController.dispose();
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
      _isFloating = true;
    });

    _floatController.forward();
    HapticFeedback.mediumImpact();
  }

  void _handleLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    if (!_isLongPressing || _longPressStart == null) return;

    final deltaY = details.globalPosition.dy - _longPressStart!.dy;
    if (deltaY > 30) {
      if (!_isDragging) {
        setState(() {
          _isDragging = true;
        });
        _deleteController.forward();
        HapticFeedback.lightImpact();
      }

      setState(() {
        _deleteProgress = ((deltaY - 30) / 120).clamp(0.0, 1.0);
      });

      if (_deleteProgress >= 0.8 && _deleteProgress < 0.85) {
        HapticFeedback.heavyImpact();
      }
    } else {
      if (_isDragging) {
        setState(() {
          _isDragging = false;
          _deleteProgress = 0.0;
        });
        _deleteController.reverse();
      }
    }
  }

  void _handleLongPressEnd(LongPressEndDetails details) {
    if (_isDragging && _deleteProgress >= 0.8) {
      _performInstantDelete();
    } else {
      _resetDeleteState();
    }
  }

  void _resetDeleteState() {
    setState(() {
      _isLongPressing = false;
      _isDragging = false;
      _deleteProgress = 0.0;
      _longPressStart = null;
      _isFloating = false;
    });
    _deleteController.reverse();
    _floatController.reverse();
  }

  // Instant delete - no loading, no dialogs, immediate action
  Future<void> _performInstantDelete() async {
    final currentPhoto = _allPhotos[_currentIndex];

    // Immediate UI update
    setState(() {
      _allPhotos.removeAt(_currentIndex);
      if (_currentIndex >= _allPhotos.length) _currentIndex = _allPhotos.length - 1;
    });

    // Clean up cache immediately
    _globalImageCache.remove(currentPhoto.id);
    _fileCache.remove(currentPhoto.id);

    // Reset delete state
    _resetDeleteState();

    // Call callback immediately
    widget.onPhotoDeleted?.call(currentPhoto.id);

    // Handle navigation
    if (_allPhotos.isEmpty) {
      Navigator.of(context).pop(true);
    } else {
      _pageController.jumpToPage(_currentIndex);
      _preloadImages(_currentIndex);
    }

    // Background deletion (no await, no loading)
    PhotoService.moveToTrash(currentPhoto).catchError((e) {
      debugPrint('Background delete error: $e');
    });

    // Show instant success message
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 18.sp),
              SizedBox(width: 8.w),
              Text('Deleted', style: GoogleFonts.inter(fontSize: 14.sp)),
            ],
          ),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
        ),
      );
    }
  }

  Future<void> _shareImage() async {
    final currentPhoto = _allPhotos[_currentIndex];

    try {
      if (_fileCache.containsKey(currentPhoto.id)) {
        await Share.shareXFiles([XFile(_fileCache[currentPhoto.id]!.path)]);
        return;
      }

      if (_globalImageCache.containsKey(currentPhoto.id)) {
        final imageData = _globalImageCache[currentPhoto.id]!;
        final tempDir = Directory.systemTemp;
        final tempFile = File('${tempDir.path}/temp_image_${currentPhoto.id}.jpg');
        await tempFile.writeAsBytes(imageData);
        await Share.shareXFiles([XFile(tempFile.path)]);
        tempFile.deleteSync();
        return;
      }

      final file = await currentPhoto.file;
      if (file != null) await Share.shareXFiles([XFile(file.path)]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to share: $e')));
      }
    }
  }

  Future<void> _deleteImage() async {
    await _performInstantDelete();
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
            AnimatedBuilder(
              animation: Listenable.merge([_floatAnimation, _deleteController]),
              builder: (context, child) {
                final floatScale = _isFloating ? 0.88 + (0.12 * _floatAnimation.value) : 1.0;
                final deleteScale = _isDragging ? 1.0 - (_deleteProgress * 0.08) : 1.0;
                final combinedScale = floatScale * deleteScale;

                final floatOffset = _isFloating ? -25 * _floatAnimation.value : 0.0;
                final dragOffset = _isDragging ? _deleteProgress * 40 : 0.0;

                return Transform.scale(
                  scale: combinedScale,
                  child: Transform.translate(
                    offset: Offset(0, floatOffset + dragOffset),
                    child: Container(
                      decoration: BoxDecoration(
                        boxShadow: _isFloating ? [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.25 * _floatAnimation.value),
                            blurRadius: 15 * _floatAnimation.value,
                            spreadRadius: 3 * _floatAnimation.value,
                            offset: Offset(0, 8 * _floatAnimation.value),
                          ),
                        ] : null,
                      ),
                      child: Center(
                        child: InteractiveViewer(
                          transformationController: _transformationController,
                          minScale: 0.5, maxScale: 4.0,
                          child: _buildOptimizedImageWidget(photo),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            if (_isLongPressing) _buildCompactDeleteOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildOptimizedImageWidget(AssetEntity photo) {
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

    _loadImageWithPriority(photo, true);

    return Hero(
      tag: 'photo_${photo.id}',
      child: FutureBuilder<File?>(
        future: photo.file,
        builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data != null) {
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
            child: Icon(
              photo.type == AssetType.video ? Icons.videocam : Icons.photo,
              color: Colors.white54,
              size: 48.sp,
            ),
          ),
        );
      },
    );
  }

  // Compact delete overlay positioned at mid-bottom
  Widget _buildCompactDeleteOverlay() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: MediaQuery.of(context).size.height * 0.35, // Mid-bottom position
      child: Center(
        child: AnimatedBuilder(
          animation: _floatAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: 1.0 + (_deleteProgress * 0.15),
              child: Container(
                width: 70.w,
                height: 70.h,
                decoration: BoxDecoration(
                  color: _deleteProgress >= 0.8
                      ? Colors.red.shade600
                      : Colors.red.shade500.withOpacity(0.9),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withOpacity(0.3 + (_deleteProgress * 0.2)),
                      blurRadius: 15 * (1 + _deleteProgress),
                      spreadRadius: 4 * _deleteProgress,
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    Center(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 150),
                        child: Icon(
                          _deleteProgress >= 0.8 ? Icons.delete : Icons.delete_outline,
                          key: ValueKey(_deleteProgress >= 0.8),
                          color: Colors.white,
                          size: (24 + (4 * _deleteProgress)).sp,
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: CircularProgressIndicator(
                        value: _deleteProgress,
                        strokeWidth: 3.w,
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                        backgroundColor: Colors.white.withOpacity(0.2),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
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
            Text('Failed to load ${_allPhotos[_currentIndex].type == AssetType.video ? 'video' : 'image'}',
                style: GoogleFonts.inter(color: Colors.white, fontSize: 16.sp, fontWeight: FontWeight.w600)),
            SizedBox(height: 8.h),
            Text('The file may be corrupted or unavailable',
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
              onPressed: () => Navigator.of(context).pop(),
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
          if (_allPhotos.isNotEmpty)
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

                _preloadImages(index);
              },
              itemBuilder: (context, index) => _buildPhotoView(_allPhotos[index]),
            )
          else
            _buildEmptyState(),

          if (_allPhotos.length > 1) _buildNavigationButtons(),
          _buildInfoOverlay(),
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
        if (currentPhoto.type == AssetType.video) ...[
          SizedBox(height: 4.h),
          Text('Duration: ${_formatDuration(currentPhoto.duration)}',
              style: GoogleFonts.poppins(color: Colors.white70, fontSize: 14.sp)),
        ],
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

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }
}
