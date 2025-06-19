import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../services/photo_service.dart';

class BinImageDetailPage extends StatefulWidget {
  final Map<String, dynamic> photo;
  final List<Map<String, dynamic>>? photoList;
  final int currentIndex;
  final VoidCallback? onPhotoRestored;
  final VoidCallback? onPhotoDeleted;

  const BinImageDetailPage({
    super.key,
    required this.photo,
    this.photoList,
    this.currentIndex = 0,
    this.onPhotoRestored,
    this.onPhotoDeleted,
  });

  @override
  State<BinImageDetailPage> createState() => _BinImageDetailPageState();
}

class _BinImageDetailPageState extends State<BinImageDetailPage>
    with TickerProviderStateMixin {
  bool _showInfo = false;
  bool _isLoading = false;
  late AnimationController _infoAnimationController;
  late Animation<double> _infoAnimation;

  // Page view controller
  late PageController _pageController;
  List<Map<String, dynamic>> _allPhotos = [];
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();

    // Info animation controller
    _infoAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _infoAnimation = CurvedAnimation(
      parent: _infoAnimationController,
      curve: Curves.easeInOut,
    );

    // Initialize with provided photo
    _currentIndex = widget.currentIndex;

    // Initialize page controller with initial page
    _pageController = PageController(initialPage: _currentIndex);

    // Load photos
    if (widget.photoList != null) {
      _allPhotos = widget.photoList!;
    } else {
      _allPhotos = [widget.photo];
    }
  }

  @override
  void dispose() {
    _infoAnimationController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _toggleInfo() {
    setState(() {
      _showInfo = !_showInfo;
    });

    if (_showInfo) {
      _infoAnimationController.forward();
    } else {
      _infoAnimationController.reverse();
    }
  }

  Future<void> _shareImage() async {
    try {
      setState(() {
        _isLoading = true;
      });

      final currentPhoto = _allPhotos[_currentIndex];
      final file = File(currentPhoto['path']);
      if (await file.exists()) {
        await Share.shareXFiles([XFile(file.path)]);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to share: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _restorePhoto() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore Photo'),
        content:
            const Text('Do you want to restore this photo to your gallery?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('RESTORE'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        setState(() {
          _isLoading = true;
        });

        final currentPhoto = _allPhotos[_currentIndex];

        // Restore from bin
        await PhotoService.restoreFromBin(currentPhoto);

        if (mounted) {
          setState(() {
            _allPhotos.removeAt(_currentIndex);

            // If we restored the last photo, go to the previous one
            if (_currentIndex >= _allPhotos.length) {
              _currentIndex = _allPhotos.length - 1;
            }

            // If no photos left, go back
            if (_allPhotos.isEmpty) {
              if (widget.onPhotoRestored != null) {
                widget.onPhotoRestored!();
              }
              Navigator.of(context).pop(true);
            } else {
              // Jump to the new current index
              _pageController.jumpToPage(_currentIndex);
            }

            _isLoading = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to restore: $e')),
          );
        }
      }
    }
  }

  Future<void> _deletePhoto() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Photo'),
        content: const Text(
            'Are you sure you want to permanently delete this photo? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('DELETE', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        setState(() {
          _isLoading = true;
        });

        final currentPhoto = _allPhotos[_currentIndex];

        // Delete from bin
        await PhotoService.deleteFromBin(currentPhoto);

        if (mounted) {
          setState(() {
            _allPhotos.removeAt(_currentIndex);

            // If we deleted the last photo, go to the previous one
            if (_currentIndex >= _allPhotos.length) {
              _currentIndex = _allPhotos.length - 1;
            }

            // If no photos left, go back
            if (_allPhotos.isEmpty) {
              if (widget.onPhotoDeleted != null) {
                widget.onPhotoDeleted!();
              }
              Navigator.of(context).pop(true);
            } else {
              // Jump to the new current index
              _pageController.jumpToPage(_currentIndex);
            }

            _isLoading = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete: $e')),
          );
        }
      }
    }
  }

  Widget _buildPhotoView(Map<String, dynamic> photo) {
    return GestureDetector(
      onTap: _toggleInfo,
      child: InteractiveViewer(
        minScale: 0.5,
        maxScale: 4.0,
        child: Hero(
          tag: 'bin_photo_${photo['id']}',
          child: FutureBuilder<String>(
            future: () async {
              final appDir = await getApplicationDocumentsDirectory();
              final binDir = Directory('${appDir.path}/bin');
              final fileName = photo['path'].split('/').last;
              return '${binDir.path}/$fileName';
            }(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError || !snapshot.hasData) {
                return const Center(
                  child: Icon(
                    Icons.error,
                    color: Colors.red,
                    size: 48,
                  ),
                );
              }
              return Image.file(
                File(snapshot.data!),
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return const Center(
                    child: Icon(
                      Icons.error,
                      color: Colors.red,
                      size: 48,
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentPhoto =
        _allPhotos.isNotEmpty ? _allPhotos[_currentIndex] : widget.photo;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.5),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          '${_currentIndex + 1} / ${_allPhotos.length}',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, color: Colors.white),
            onPressed: _toggleInfo,
          ),
          IconButton(
            icon: const Icon(Icons.share, color: Colors.white),
            onPressed: _shareImage,
          ),
        ],
      ),
      body: Stack(
        children: [
          // Main image with PageView for swiping
          if (_allPhotos.isNotEmpty)
            PageView.builder(
              controller: _pageController,
              itemCount: _allPhotos.length,
              physics: const BouncingScrollPhysics(),
              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                  // Hide info when changing pages
                  if (_showInfo) {
                    _showInfo = false;
                    _infoAnimationController.reverse();
                  }
                });
              },
              itemBuilder: (context, index) {
                return _buildPhotoView(_allPhotos[index]);
              },
            )
          else
            const Center(
              child: CircularProgressIndicator(
                color: Colors.white,
              ),
            ),

          // Navigation indicators
          if (_allPhotos.length > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: 80,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Previous button (hidden for first image)
                  AnimatedOpacity(
                    opacity: _currentIndex > 0 ? 0.7 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      margin: const EdgeInsets.only(left: 16),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new,
                            color: Colors.white),
                        onPressed: _currentIndex > 0
                            ? () => _pageController.animateToPage(
                                  _currentIndex - 1,
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeInOut,
                                )
                            : null,
                      ),
                    ),
                  ),

                  // Next button (hidden for last image)
                  AnimatedOpacity(
                    opacity: _currentIndex < _allPhotos.length - 1 ? 0.7 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      margin: const EdgeInsets.only(right: 16),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.arrow_forward_ios,
                            color: Colors.white),
                        onPressed: _currentIndex < _allPhotos.length - 1
                            ? () => _pageController.animateToPage(
                                  _currentIndex + 1,
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeInOut,
                                )
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Photo info overlay with animation
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).animate(_infoAnimation),
              child: FadeTransition(
                opacity: _infoAnimation,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withOpacity(0.9),
                        Colors.black.withOpacity(0.7),
                        Colors.transparent,
                      ],
                      stops: const [0.4, 0.8, 1.0],
                    ),
                  ),
                  child: _allPhotos.isNotEmpty
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              DateFormat('MMMM d, yyyy - h:mm a').format(
                                DateTime.parse(_allPhotos[_currentIndex]
                                    ['createDateTime']),
                              ),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${_allPhotos[_currentIndex]['width']} × ${_allPhotos[_currentIndex]['height']}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Deleted: ${DateFormat('MMMM d, yyyy - h:mm a').format(
                                DateTime.parse(
                                    _allPhotos[_currentIndex]['deletedAt']),
                              )}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ),
          ),

          // Bottom action buttons
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: _restorePhoto,
                  icon: const Icon(Icons.restore),
                  label: const Text('Restore'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _deletePhoto,
                  icon: const Icon(Icons.delete_forever),
                  label: const Text('Delete'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),

          // Loading overlay
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(
                child: CircularProgressIndicator(
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
