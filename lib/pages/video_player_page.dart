import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';
import 'package:intl/intl.dart';
import '../services/photo_service.dart';
import 'package:flutter/services.dart';

class VideoPlayerPage extends StatefulWidget {
  final AssetEntity video;
  final List<AssetEntity>? videoList;
  final int currentIndex;
  final Function(String)? onVideoDeleted;

  const VideoPlayerPage({
    super.key,
    required this.video,
    this.videoList,
    this.currentIndex = 0,
    this.onVideoDeleted,
  });

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> with TickerProviderStateMixin {
  VideoPlayerController? _controller;
  bool _isPlaying = false;
  bool _showControls = true;
  bool _isLoading = true;
  bool _hasError = false;
  late AnimationController _controlsController;
  late Animation<double> _controlsAnimation;

  List<AssetEntity> _allVideos = [];
  int _currentIndex = 0;
  late PageController _pageController;

  // Delete gesture tracking
  bool _isLongPressing = false, _isDragging = false;
  double _deleteProgress = 0.0;
  Offset? _longPressStart;
  late AnimationController _deleteController, _floatController;
  late Animation<double> _deleteAnimation, _floatAnimation;

  @override
  void initState() {
    super.initState();
    _initControllers();
    _initializeVideos();
    _loadVideo();
  }

  void _initControllers() {
    _controlsController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
      value: 1.0,
    );
    _deleteController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _floatController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _controlsAnimation = CurvedAnimation(
      parent: _controlsController,
      curve: Curves.easeInOut,
    );
    _deleteAnimation = CurvedAnimation(
      parent: _deleteController,
      curve: Curves.easeInOut,
    );
    _floatAnimation = CurvedAnimation(
      parent: _floatController,
      curve: Curves.easeOutBack,
    );

    _currentIndex = widget.currentIndex;
    _pageController = PageController(initialPage: _currentIndex);
  }

  void _initializeVideos() {
    if (widget.videoList?.isNotEmpty == true) {
      _allVideos = widget.videoList!;
    } else {
      _allVideos = [widget.video];
    }
  }

  Future<void> _loadVideo() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final currentVideo = _allVideos[_currentIndex];
      final file = await currentVideo.file;

      if (file != null && await file.exists()) {
        _controller?.dispose();
        _controller = VideoPlayerController.file(file);

        await _controller!.initialize();

        if (mounted) {
          setState(() {
            _isLoading = false;
          });

          // Auto-play the video
          _controller!.play();
          setState(() {
            _isPlaying = true;
          });

          _controller!.addListener(_videoListener);
        }
      } else {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  void _videoListener() {
    if (_controller != null && mounted) {
      setState(() {
        _isPlaying = _controller!.value.isPlaying;
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _controlsController.dispose();
    _deleteController.dispose();
    _floatController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    if (_controller != null) {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
      } else {
        _controller!.play();
      }
    }
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
      if (_showControls) {
        _controlsController.forward();
      } else {
        _controlsController.reverse();
      }
    });
  }

  void _handleLongPressStart(LongPressStartDetails details) {
    setState(() {
      _isLongPressing = true;
      _longPressStart = details.globalPosition;
      _isDragging = false;
      _deleteProgress = 0.0;
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
    });
    _deleteController.reverse();
    _floatController.reverse();
  }

  Future<void> _performInstantDelete() async {
    final currentVideo = _allVideos[_currentIndex];

    // Immediate UI update
    setState(() {
      _allVideos.removeAt(_currentIndex);
      if (_currentIndex >= _allVideos.length) _currentIndex = _allVideos.length - 1;
    });

    _resetDeleteState();
    widget.onVideoDeleted?.call(currentVideo.id);

    // Handle navigation
    if (_allVideos.isEmpty) {
      Navigator.of(context).pop(true);
    } else {
      _pageController.jumpToPage(_currentIndex);
      _loadVideo();
    }

    // Background deletion
    PhotoService.moveToTrash(currentVideo).catchError((e) {
      debugPrint('Background delete error: $e');
    });

    // Show success message
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 18.sp),
              SizedBox(width: 8.w),
              Text('Video deleted', style: GoogleFonts.inter(fontSize: 14.sp)),
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

  Widget _buildVideoPlayer() {
    if (_isLoading) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.videocam, color: Colors.white54, size: 48.sp),
              SizedBox(height: 16.h),
              Text(
                'Loading video...',
                style: GoogleFonts.inter(color: Colors.white, fontSize: 16.sp),
              ),
            ],
          ),
        ),
      );
    }

    if (_hasError || _controller == null) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, color: Colors.red, size: 48.sp),
              SizedBox(height: 16.h),
              Text(
                'Failed to load video',
                style: GoogleFonts.inter(color: Colors.white, fontSize: 16.sp),
              ),
              SizedBox(height: 8.h),
              Text(
                'The video file may be corrupted',
                style: GoogleFonts.inter(color: Colors.white70, fontSize: 14.sp),
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: _toggleControls,
      onLongPressStart: _handleLongPressStart,
      onLongPressMoveUpdate: _handleLongPressMoveUpdate,
      onLongPressEnd: _handleLongPressEnd,
      child: Container(
        color: Colors.black,
        child: Stack(
          children: [
            AnimatedBuilder(
              animation: Listenable.merge([_floatAnimation, _deleteController]),
              builder: (context, child) {
                final floatScale = _isLongPressing ? 0.88 + (0.12 * _floatAnimation.value) : 1.0;
                final deleteScale = _isDragging ? 1.0 - (_deleteProgress * 0.08) : 1.0;
                final combinedScale = floatScale * deleteScale;

                return Transform.scale(
                  scale: combinedScale,
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: _controller!.value.aspectRatio,
                      child: VideoPlayer(_controller!),
                    ),
                  ),
                );
              },
            ),
            if (_isLongPressing) _buildCompactDeleteOverlay(),
            _buildVideoControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactDeleteOverlay() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: MediaQuery.of(context).size.height * 0.35,
      child: Center(
        child: Transform.scale(
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
        ),
      ),
    );
  }

  Widget _buildVideoControls() {
    if (_controller == null) return const SizedBox.shrink();

    return FadeTransition(
      opacity: _controlsAnimation,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withOpacity(0.7),
              Colors.transparent,
              Colors.transparent,
              Colors.black.withOpacity(0.7),
            ],
            stops: const [0.0, 0.3, 0.7, 1.0],
          ),
        ),
        child: Column(
          children: [
            // Top controls
            SafeArea(
              child: Padding(
                padding: EdgeInsets.all(16.w),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    Expanded(
                      child: Text(
                        '${_currentIndex + 1} / ${_allVideos.length}',
                        style: GoogleFonts.inter(color: Colors.white, fontSize: 16.sp),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.white),
                      onPressed: _performInstantDelete,
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            // Center play button
            Center(
              child: GestureDetector(
                onTap: _togglePlayPause,
                child: Container(
                  width: 80.w,
                  height: 80.h,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                    size: 40.sp,
                  ),
                ),
              ),
            ),
            const Spacer(),
            // Bottom controls
            Padding(
              padding: EdgeInsets.all(16.w),
              child: Column(
                children: [
                  // Progress bar
                  VideoProgressIndicator(
                    _controller!,
                    allowScrubbing: true,
                    colors: VideoProgressColors(
                      playedColor: Colors.white,
                      bufferedColor: Colors.white.withOpacity(0.3),
                      backgroundColor: Colors.white.withOpacity(0.1),
                    ),
                  ),
                  SizedBox(height: 8.h),
                  // Time and controls
                  Row(
                    children: [
                      Text(
                        _formatDuration(_controller!.value.position),
                        style: GoogleFonts.inter(color: Colors.white, fontSize: 14.sp),
                      ),
                      const Spacer(),
                      Text(
                        _formatDuration(_controller!.value.duration),
                        style: GoogleFonts.inter(color: Colors.white, fontSize: 14.sp),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _allVideos.isNotEmpty
          ? PageView.builder(
        controller: _pageController,
        itemCount: _allVideos.length,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
          _loadVideo();
        },
        itemBuilder: (context, index) => _buildVideoPlayer(),
      )
          : Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.videocam_off, color: Colors.white54, size: 64.sp),
              SizedBox(height: 16.h),
              Text(
                'No videos available',
                style: GoogleFonts.inter(color: Colors.white, fontSize: 18.sp),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
