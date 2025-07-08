import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:intl/intl.dart';
import '../services/photo_service.dart';
import 'video_player_page.dart';

class VideosPage extends StatefulWidget {
  const VideosPage({super.key});

  @override
  State<VideosPage> createState() => _VideosPageState();
}

class _VideosPageState extends State<VideosPage> {
  List<AssetEntity>? _videos;
  bool _isLoading = true;
  String? _error;
  Map<String, List<AssetEntity>> _groupedVideos = {};
  final Map<String, Uint8List?> _thumbnailCache = {};

  @override
  void initState() {
    super.initState();
    _loadVideos();
  }

  Future<void> _loadVideos() async {
    try {
      setState(() {
        _error = null;
        _isLoading = true;
      });

      // Try main method first, then fallback
      List<AssetEntity> videos = await PhotoService.getAllVideos();
      if (videos.isEmpty) {
        debugPrint('No videos found with main method, trying fallback...');
        videos = await PhotoService.getAllVideosWithFallback();
      }

      debugPrint('Loaded ${videos.length} videos');

      // Load thumbnails for videos
      for (var video in videos) {
        if (!_thumbnailCache.containsKey(video.id)) {
          _loadVideoThumbnail(video);
        }
      }

      _groupVideos(videos);

      setState(() {
        _videos = videos;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading videos: $e');
      setState(() {
        _error = 'Failed to load videos: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadVideoThumbnail(AssetEntity video) async {
    try {
      final data = await video.thumbnailDataWithSize(const ThumbnailSize(200, 200));
      if (data != null && mounted) {
        setState(() {
          _thumbnailCache[video.id] = data;
        });
      }
    } catch (e) {
      debugPrint('Error loading thumbnail for video ${video.id}: $e');
    }
  }

  void _groupVideos(List<AssetEntity> videos) {
    _groupedVideos = {};
    for (var video in videos) {
      final date = video.createDateTime;
      final dateString = DateFormat('yyyy-MM-dd').format(date);
      if (!_groupedVideos.containsKey(dateString)) {
        _groupedVideos[dateString] = [];
      }
      _groupedVideos[dateString]!.add(video);
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

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  void _openVideo(AssetEntity video, {List<AssetEntity>? videoList, int? index}) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            VideoPlayerPage(
              video: video,
              videoList: videoList ?? _videos,
              currentIndex: index ?? _videos?.indexOf(video) ?? 0,
              onVideoDeleted: (videoId) {
                _loadVideos();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Videos',
          style: GoogleFonts.poppins(
            fontSize: 24.sp,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16.h),
            Text(
              'Loading videos...',
              style: GoogleFonts.inter(fontSize: 16.sp, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48.sp, color: Colors.grey.shade600),
            SizedBox(height: 16.h),
            Text(
              'Failed to load videos',
              style: GoogleFonts.inter(fontSize: 18.sp, fontWeight: FontWeight.w600, color: Colors.black87),
            ),
            SizedBox(height: 8.h),
            Text(
              'Check storage permissions',
              style: GoogleFonts.inter(fontSize: 14.sp, color: Colors.grey.shade600),
            ),
            SizedBox(height: 16.h),
            ElevatedButton(
              onPressed: _loadVideos,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
              ),
              child: Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_videos == null || _videos!.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.videocam_outlined, size: 64.sp, color: Colors.grey.shade400),
            SizedBox(height: 16.h),
            Text(
              'No videos found',
              style: GoogleFonts.inter(
                fontSize: 18.sp,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade600,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              'Videos will appear here when available',
              style: GoogleFonts.inter(
                fontSize: 14.sp,
                color: Colors.grey.shade500,
              ),
            ),
            SizedBox(height: 16.h),
            ElevatedButton(
              onPressed: _loadVideos,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
              ),
              child: Text('Refresh'),
            ),
          ],
        ),
      );
    }

    final dateKeys = _groupedVideos.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    return RefreshIndicator(
      onRefresh: _loadVideos,
      child: ListView.builder(
        physics: const BouncingScrollPhysics(),
        itemCount: dateKeys.length,
        itemBuilder: (context, index) {
          final dateKey = dateKeys[index];
          final videosInGroup = _groupedVideos[dateKey]!;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 12.h),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDateHeader(dateKey),
                      style: GoogleFonts.poppins(
                        fontSize: 22.sp,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                        letterSpacing: -0.5,
                      ),
                    ),
                    Text(
                      '${videosInGroup.length} videos',
                      style: GoogleFonts.inter(
                        fontSize: 14.sp,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
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
                itemCount: videosInGroup.length,
                itemBuilder: (context, index) {
                  final video = videosInGroup[index];
                  return _buildVideoTile(video, videosInGroup, index);
                },
              ),
              SizedBox(height: 20.h),
            ],
          );
        },
      ),
    );
  }

  Widget _buildVideoTile(AssetEntity video, List<AssetEntity> videoList, int index) {
    return GestureDetector(
      onTap: () => _openVideo(video, videoList: videoList, index: index),
      child: Container(
        color: Colors.white,
        child: Stack(
          children: [
            // Video thumbnail
            _thumbnailCache[video.id] != null
                ? Image.memory(
              _thumbnailCache[video.id]!,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            )
                : Container(
              color: Colors.grey.shade200,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.videocam,
                      color: Colors.grey.shade400,
                      size: 24.sp,
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      'Loading...',
                      style: GoogleFonts.inter(
                        fontSize: 10.sp,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Video duration overlay
            Positioned(
              bottom: 4.h,
              right: 4.w,
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: 6.w,
                  vertical: 2.h,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.8),
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
                      _formatDuration(video.duration),
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

            // Play button overlay
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.3),
                    ],
                  ),
                ),
                child: Center(
                  child: Container(
                    width: 50.w,
                    height: 50.h,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.play_arrow,
                      color: Colors.white,
                      size: 28.sp,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
