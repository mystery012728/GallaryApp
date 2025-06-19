import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:intl/intl.dart';
import '../services/photo_service.dart';
import '../widgets/photo_grid_item.dart';
import 'image_detail_page.dart';
import 'album_detail_page.dart';
import 'bin_page.dart';
import 'vault_page.dart';

// Custom AppBar that implements PreferredSizeWidget
class AnimatedAppBarWithTabs extends StatelessWidget implements PreferredSizeWidget {
  final Animation<double> animation;
  final TabController tabController;
  final String title;

  const AnimatedAppBarWithTabs({
    Key? key,
    required this.animation,
    required this.tabController,
    required this.title,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, -100 * (1 - animation.value)),
          child: Opacity(
            opacity: animation.value,
            child: AppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              shadowColor: Colors.black.withOpacity(0.1),
              title: Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 28.sp,
                  fontWeight: FontWeight.w800,
                  color: Colors.black87,
                  letterSpacing: -1,
                ),
              ),
              bottom: TabBar(
                controller: tabController,
                labelColor: Colors.black87,
                unselectedLabelColor: Colors.grey.shade500,
                indicatorColor: Colors.black87,
                indicatorWeight: 3,
                indicatorSize: TabBarIndicatorSize.label,
                labelStyle: GoogleFonts.inter(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
                unselectedLabelStyle: GoogleFonts.inter(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w500,
                ),
                tabs: const [
                  Tab(text: 'Photos'),
                  Tab(text: 'Albums'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Size get preferredSize => Size.fromHeight(kToolbarHeight + kTextTabBarHeight);
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with TickerProviderStateMixin {
  int _currentIndex = 0;
  List<AssetEntity>? _photos;
  List<AssetPathEntity> _albums = [];
  List<AssetPathEntity> _recentAlbums = [];
  List<AssetPathEntity> _otherAlbums = [];
  bool _isLoading = true;
  String? _error;
  Map<String, List<AssetEntity>> _groupedPhotos = {};
  final Map<String, Uint8List?> _thumbnailCache = {};
  int _swipeCount = 0;
  DateTime? _lastSwipeTime;
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey = GlobalKey<RefreshIndicatorState>();
  late PageController _pageController;
  late TabController _tabController;

  // Animation controllers for vault opening effect
  late AnimationController _vaultOpenController;
  late AnimationController _appBarController;
  late Animation<double> _vaultOpenAnimation;
  late Animation<double> _appBarAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _scaleAnimation;

  bool _isVaultOpening = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_handleTabChange);

    // Initialize animation controllers
    _vaultOpenController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _appBarController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _vaultOpenAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _vaultOpenController,
      curve: Curves.easeOutCubic,
    ));

    _appBarAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _appBarController,
      curve: Curves.easeInOut,
    ));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _vaultOpenController,
      curve: Curves.easeOutCubic,
    ));

    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _vaultOpenController,
      curve: Curves.easeOutCubic,
    ));

    _appBarController.reset();
    _appBarController.reverse();

    _loadData();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _tabController.dispose();
    _vaultOpenController.dispose();
    _appBarController.dispose();
    super.dispose();
  }

  void _handleTabChange() {
    if (_tabController.indexIsChanging) {
      setState(() {
        _currentIndex = _tabController.index;
      });
      _pageController.animateToPage(
        _tabController.index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      _loadData();
    }
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification) {
      if (notification.metrics.pixels < -120 && !_isVaultOpening) {
        _triggerVaultOpenEffect();
      }
    }
    return false;
  }

  void _triggerVaultOpenEffect() async {
    setState(() {
      _isVaultOpening = true;
    });

    await _appBarController.forward();
    await _vaultOpenController.forward();
    await Future.delayed(const Duration(milliseconds: 300));

    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const VaultPage(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 500),
      ),
    ).then((_) {
      _resetVaultAnimation();
    });
  }

  void _resetVaultAnimation() async {
    await _vaultOpenController.reverse();
    await _appBarController.reverse();

    setState(() {
      _isVaultOpening = false;
    });
  }

  Future<void> _loadData() async {
    if (_currentIndex == 0) {
      await _loadCameraPhotos();
    } else {
      await _loadAlbums();
    }
  }

  Future<void> _loadCameraPhotos() async {
    try {
      setState(() {
        _error = null;
      });

      final cameraAlbum = await PhotoService.getCameraAlbum();
      List<AssetEntity> cameraPhotos = [];

      if (cameraAlbum != null) {
        final totalCount = await cameraAlbum.assetCountAsync;
        cameraPhotos = await cameraAlbum.getAssetListRange(
          start: 0,
          end: totalCount,
        );

        for (var photo in cameraPhotos) {
          if (!_thumbnailCache.containsKey(photo.id)) {
            photo
                .thumbnailDataWithSize(const ThumbnailSize(200, 200))
                .then((data) {
              if (data != null && mounted) {
                setState(() {
                  _thumbnailCache[photo.id] = data;
                });
              }
            });
          }
        }
      }

      _groupPhotos(cameraPhotos);

      setState(() {
        _photos = cameraPhotos;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load camera photos: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadAlbums() async {
    try {
      final List<AssetPathEntity> albums = await PhotoService.getAlbums();

      // Filter albums with photos and separate recent vs other
      List<AssetPathEntity> validAlbums = [];
      List<Map<String, dynamic>> albumsWithDates = [];

      for (var album in albums) {
        final count = await album.assetCountAsync;
        if (count > 0) {
          validAlbums.add(album);
          _loadThumbnail(album);

          // Get recent photos from album to determine if it's recent
          final recentPhotos = await album.getAssetListRange(start: 0, end: 1);
          DateTime? lastPhotoDate;

          if (recentPhotos.isNotEmpty) {
            lastPhotoDate = recentPhotos.first.createDateTime;
          }

          albumsWithDates.add({
            'album': album,
            'lastPhotoDate': lastPhotoDate,
            'daysSinceLastPhoto': lastPhotoDate != null
                ? DateTime.now().difference(lastPhotoDate).inDays
                : 999,
          });
        }
      }

      // Sort albums by most recent activity first
      albumsWithDates.sort((a, b) {
        final aDays = a['daysSinceLastPhoto'] as int;
        final bDays = b['daysSinceLastPhoto'] as int;
        return aDays.compareTo(bDays);
      });

      // Separate recent and other albums
      List<AssetPathEntity> recentAlbums = [];
      List<AssetPathEntity> otherAlbums = [];

      for (var albumData in albumsWithDates) {
        final album = albumData['album'] as AssetPathEntity;
        final daysSinceLastPhoto = albumData['daysSinceLastPhoto'] as int;

        // Consider album recent if it has photos from last 30 days
        if (daysSinceLastPhoto <= 30) {
          recentAlbums.add(album);
        } else {
          otherAlbums.add(album);
        }
      }

      if (mounted) {
        setState(() {
          _albums = validAlbums;
          _recentAlbums = recentAlbums.take(2).toList(); // Show max 2 recent albums
          _otherAlbums = otherAlbums;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load albums: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadThumbnail(AssetPathEntity album) async {
    try {
      final assets = await album.getAssetListRange(start: 0, end: 1);
      if (assets.isNotEmpty) {
        final asset = assets.first;
        if (!_thumbnailCache.containsKey('album_${album.id}')) {
          final data = await asset.thumbnailDataWithSize(const ThumbnailSize(200, 200));
          if (data != null && mounted) {
            setState(() {
              _thumbnailCache['album_${album.id}'] = data;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading thumbnail for album ${album.id}: $e');
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

  void _openPhoto(AssetEntity photo, {List<AssetEntity>? photoList, int? index}) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            ImageDetailPage(
              photo: photo,
              folderPath: 'Camera',
              currentIndex: index ??
                  photoList?.indexOf(photo) ??
                  _photos?.indexOf(photo) ??
                  0,
              onPhotoDeleted: () {
                _loadCameraPhotos();
              },
            ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            )),
            child: child,
          );
        },
      ),
    );
  }

  void _openAlbum(AssetPathEntity album) async {
    final result = await Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => AlbumDetailPage(
          album: album,
          thumbnailCache: _thumbnailCache,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            )),
            child: child,
          );
        },
      ),
    );

    if (result == true) {
      _loadAlbums();
    }
  }

  void _openBin() async {
    final result = await Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const BinPage(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            )),
            child: child,
          );
        },
      ),
    );

    if (result == true) {
      _loadAlbums();
    }
  }

  void _handleSwipe(DragEndDetails details) {
    if (details.velocity.pixelsPerSecond.dx < -300) {
      final now = DateTime.now();
      if (_lastSwipeTime == null ||
          now.difference(_lastSwipeTime!) > const Duration(seconds: 1)) {
        _swipeCount = 0;
      }
      _lastSwipeTime = now;
      _swipeCount++;

      if (_swipeCount == 2) {
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => const VaultPage(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.8, end: 1.0).animate(
                    CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
                  ),
                  child: child,
                ),
              );
            },
          ),
        );
        _swipeCount = 0;
      }
    }
  }

  void _slidePhotoToAlbum(AssetEntity photo) async {
    if (_albums.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No albums available',
            style: GoogleFonts.inter(fontSize: 14.sp),
          ),
          backgroundColor: Colors.black87,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
        ),
      );
      return;
    }

    final selectedAlbum = await showModalBottomSheet<AssetPathEntity>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        padding: EdgeInsets.all(20.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40.w,
                height: 4.h,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2.r),
                ),
              ),
            ),
            SizedBox(height: 20.h),
            Text(
              'Move to Album',
              style: GoogleFonts.poppins(
                fontSize: 24.sp,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
            SizedBox(height: 16.h),
            Expanded(
              child: ListView.builder(
                itemCount: _albums.length,
                itemBuilder: (context, index) {
                  final album = _albums[index];
                  return Container(
                    margin: EdgeInsets.only(bottom: 12.h),
                    child: ListTile(
                      contentPadding: EdgeInsets.all(12.w),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                        side: BorderSide(color: Colors.grey.shade200),
                      ),
                      leading: Container(
                        width: 60.w,
                        height: 60.h,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12.r),
                          child: _thumbnailCache['album_${album.id}'] != null
                              ? Image.memory(
                            _thumbnailCache['album_${album.id}']!,
                            fit: BoxFit.cover,
                          )
                              : Icon(Icons.photo_album,
                              color: Colors.grey.shade400, size: 24.sp),
                        ),
                      ),
                      title: Text(
                        album.name,
                        style: GoogleFonts.inter(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      trailing: Icon(
                        Icons.arrow_forward_ios,
                        size: 16.sp,
                        color: Colors.grey.shade400,
                      ),
                      onTap: () => Navigator.pop(context, album),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    if (selectedAlbum != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Photo moved to ${selectedAlbum.name}',
            style: GoogleFonts.inter(fontSize: 14.sp),
          ),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
        ),
      );
    }
  }

  Widget _buildCameraPhotosView() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48.sp, color: Colors.grey.shade600),
            SizedBox(height: 16.h),
            Text(
              _error!,
              style: GoogleFonts.inter(
                fontSize: 16.sp,
                color: Colors.grey.shade700,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (_photos == null || _photos!.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.photo_library_outlined, size: 64.sp, color: Colors.grey.shade400),
            SizedBox(height: 16.h),
            Text(
              'No photos found',
              style: GoogleFonts.inter(
                fontSize: 18.sp,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade600,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              'Pull down to open vault',
              style: GoogleFonts.inter(
                fontSize: 14.sp,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      );
    }

    final dateKeys = _groupedPhotos.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: ListView.builder(
        physics: const BouncingScrollPhysics(),
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
                  crossAxisSpacing: 6.w,
                  mainAxisSpacing: 6.h,
                ),
                itemCount: photosInGroup.length,
                itemBuilder: (context, index) {
                  final photo = photosInGroup[index];
                  return GestureDetector(
                    onTap: () => _openPhoto(photo,
                        photoList: photosInGroup, index: index),
                    onLongPress: () => _slidePhotoToAlbum(photo),
                    child: Hero(
                      tag: 'photo_${photo.id}',
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12.r),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12.r),
                          child: Stack(
                            children: [
                              _thumbnailCache[photo.id] != null
                                  ? Image.memory(
                                _thumbnailCache[photo.id]!,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: double.infinity,
                              )
                                  : Container(
                                color: Colors.grey.shade200,
                                child: Center(
                                  child: Icon(
                                    Icons.photo,
                                    color: Colors.grey.shade400,
                                    size: 24.sp,
                                  ),
                                ),
                              ),
                              if (photo.type == AssetType.video)
                                Positioned(
                                  bottom: 8.h,
                                  right: 8.w,
                                  child: Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 8.w,
                                      vertical: 4.h,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.7),
                                      borderRadius: BorderRadius.circular(6.r),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.play_arrow,
                                          color: Colors.white,
                                          size: 14.sp,
                                        ),
                                        SizedBox(width: 2.w),
                                        Text(
                                          _formatDuration(photo.duration),
                                          style: GoogleFonts.inter(
                                            color: Colors.white,
                                            fontSize: 11.sp,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
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

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  Widget _buildAlbumCard(AssetPathEntity album, {bool isLarge = false}) {
    return FutureBuilder<int>(
      future: album.assetCountAsync,
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;

        return Container(
          width: isLarge ? double.infinity : 160.w,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16.r),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16.r),
            onTap: () => _openAlbum(album),
            child: Padding(
              padding: EdgeInsets.all(12.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12.r),
                        color: Colors.grey.shade100,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12.r),
                        child: _buildAlbumThumbnail(album),
                      ),
                    ),
                  ),
                  SizedBox(height: 12.h),
                  Text(
                    album.name,
                    style: GoogleFonts.inter(
                      fontSize: isLarge ? 18.sp : 14.sp,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    '$count items',
                    style: GoogleFonts.inter(
                      fontSize: isLarge ? 14.sp : 12.sp,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBinSection() {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16.w),
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16.r),
        onTap: _openBin,
        child: Row(
          children: [
            Container(
              width: 60.w,
              height: 60.h,
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Center(
                child: Icon(
                  Icons.delete_outline,
                  size: 28.sp,
                  color: Colors.red.shade400,
                ),
              ),
            ),
            SizedBox(width: 16.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bin',
                    style: GoogleFonts.inter(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: PhotoService.getBinPhotos(),
                    builder: (context, snapshot) {
                      final count = snapshot.data?.length ?? 0;
                      return Text(
                        '$count deleted items',
                        style: GoogleFonts.inter(
                          fontSize: 14.sp,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 16.sp,
              color: Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlbumThumbnail(AssetPathEntity album) {
    final cachedThumbnail = _thumbnailCache['album_${album.id}'];

    if (cachedThumbnail != null) {
      return Image.memory(
        cachedThumbnail,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    }

    return FutureBuilder<List<AssetEntity>>(
      future: album.getAssetListRange(start: 0, end: 1),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            snapshot.hasData &&
            snapshot.data!.isNotEmpty) {
          final asset = snapshot.data!.first;

          return FutureBuilder<Uint8List?>(
            future: asset.thumbnailDataWithSize(const ThumbnailSize(200, 200)),
            builder: (context, thumbSnapshot) {
              if (thumbSnapshot.connectionState == ConnectionState.done &&
                  thumbSnapshot.hasData) {
                _thumbnailCache['album_${album.id}'] = thumbSnapshot.data;
                return Image.memory(
                  thumbSnapshot.data!,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                );
              }
              return Container(
                color: Colors.grey.shade100,
                child: Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.grey.shade400),
                  ),
                ),
              );
            },
          );
        }
        return Container(
          color: Colors.grey.shade100,
          child: Center(
            child: Icon(
              Icons.photo,
              color: Colors.grey.shade400,
              size: 24.sp,
            ),
          ),
        );
      },
    );
  }

  Widget _buildAlbumsView() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 48.sp,
              color: Colors.grey.shade600,
            ),
            SizedBox(height: 16.h),
            Text(
              'Failed to load albums',
              style: GoogleFonts.inter(
                fontSize: 18.sp,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            SizedBox(height: 8.h),
            ElevatedButton(
              onPressed: _loadAlbums,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black87,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
                padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
              ),
              child: Text(
                'Retry',
                style: GoogleFonts.inter(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Recent Albums Section
            if (_recentAlbums.isNotEmpty) ...[
              Padding(
                padding: EdgeInsets.fromLTRB(16.w, 20.h, 16.w, 16.h),
                child: Text(
                  'Recent',
                  style: GoogleFonts.poppins(
                    fontSize: 22.sp,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              Container(
                height: 200.h,
                child: GridView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: 16.w),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 1,
                    mainAxisSpacing: 12.w,
                    childAspectRatio: 0.85,
                  ),
                  itemCount: _recentAlbums.length,
                  itemBuilder: (context, index) {
                    return _buildAlbumCard(_recentAlbums[index], isLarge: true);
                  },
                ),
              ),
              SizedBox(height: 24.h),
            ],

            // Other Albums Section
            if (_otherAlbums.isNotEmpty) ...[
              Padding(
                padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'All Albums',
                      style: GoogleFonts.poppins(
                        fontSize: 22.sp,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                        letterSpacing: -0.5,
                      ),
                    ),
                    if (_otherAlbums.length > 4)
                      Text(
                        'Swipe to see more',
                        style: GoogleFonts.inter(
                          fontSize: 12.sp,
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                height: 180.h,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: 16.w),
                  itemCount: _otherAlbums.length,
                  itemBuilder: (context, index) {
                    return Container(
                      margin: EdgeInsets.only(right: 12.w),
                      child: _buildAlbumCard(_otherAlbums[index]),
                    );
                  },
                ),
              ),
              SizedBox(height: 24.h),
            ],

            // Bin Section
            Padding(
              padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
              child: Text(
                'Bin',
                style: GoogleFonts.poppins(
                  fontSize: 22.sp,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                  letterSpacing: -0.5,
                ),
              ),
            ),
            _buildBinSection(),
            SizedBox(height: 24.h),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AnimatedAppBarWithTabs(
        animation: _appBarAnimation,
        tabController: _tabController,
        title: 'Gallery',
      ),
      body: Stack(
        children: [
          GestureDetector(
            onHorizontalDragEnd: _handleSwipe,
            child: PageView(
              controller: _pageController,
              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                  _tabController.animateTo(index);
                });
                _loadData();
              },
              children: [
                _isLoading ?
                const Center(child: CircularProgressIndicator()) :
                _buildCameraPhotosView(),
                _isLoading ?
                const Center(child: CircularProgressIndicator()) :
                _buildAlbumsView(),
              ],
            ),
          ),
          // Vault opening overlay effect
          if (_isVaultOpening)
            AnimatedBuilder(
              animation: _vaultOpenAnimation,
              builder: (context, child) {
                return Container(
                  color: Colors.black.withOpacity(_vaultOpenAnimation.value * 0.8),
                  child: Center(
                    child: SlideTransition(
                      position: _slideAnimation,
                      child: ScaleTransition(
                        scale: _scaleAnimation,
                        child: Container(
                          width: 140.w,
                          height: 140.h,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24.r),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 30,
                                offset: const Offset(0, 15),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.lock_open,
                                color: Colors.black87,
                                size: 40.sp,
                              ),
                              SizedBox(height: 12.h),
                              Text(
                                'Opening Vault',
                                style: GoogleFonts.poppins(
                                  color: Colors.black87,
                                  fontSize: 16.sp,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(height: 4.h),
                              Text(
                                'Secure Access',
                                style: GoogleFonts.inter(
                                  color: Colors.grey.shade600,
                                  fontSize: 12.sp,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}