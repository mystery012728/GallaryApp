import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import '../services/photo_service.dart';
import '../widgets/empty_state.dart';
import 'bin_image_detail_page.dart';

class BinPage extends StatefulWidget {
  const BinPage({super.key});

  @override
  State<BinPage> createState() => _BinPageState();
}

class _BinPageState extends State<BinPage> {
  List<Map<String, dynamic>> _binPhotos = [];
  bool _isLoading = true;
  bool _hasChanges = false;
  bool _isGridView = true;
  Map<String, List<Map<String, dynamic>>> _groupedPhotos = {};
  bool _isSelectionMode = false;
  List<Map<String, dynamic>> _selectedPhotos = [];

  @override
  void initState() {
    super.initState();
    _loadBinPhotos();
  }

  Future<void> _loadBinPhotos() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final binPhotos = await PhotoService.getBinPhotos();

      // Group photos by date
      _groupPhotos(binPhotos);

      setState(() {
        _binPhotos = binPhotos;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error loading bin photos: $e',
              style: GoogleFonts.poppins(fontSize: 14.sp),
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8.r),
            ),
          ),
        );
      }
    }
  }

  void _groupPhotos(List<Map<String, dynamic>> photos) {
    _groupedPhotos = {};

    for (var photo in photos) {
      final date = DateTime.parse(photo['createDateTime']);
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

  Future<void> _emptyBin() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.r),
        ),
        title: Text(
          'Empty Bin',
          style: GoogleFonts.poppins(
            fontSize: 20.sp,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60.w,
              height: 60.w,
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.delete_forever,
                size: 30.sp,
                color: Colors.red,
              ),
            ),
            SizedBox(height: 16.h),
            Text(
              'Are you sure you want to permanently delete all photos in the bin?',
              style: GoogleFonts.poppins(
                fontSize: 16.sp,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8.h),
            Text(
              'This action cannot be undone',
              style: GoogleFonts.poppins(
                fontSize: 14.sp,
                color: Colors.red,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'CANCEL',
              style: GoogleFonts.poppins(
                fontSize: 14.sp,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.r),
              ),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'EMPTY BIN',
              style: GoogleFonts.poppins(
                fontSize: 14.sp,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actionsPadding: EdgeInsets.symmetric(
          horizontal: 16.w,
          vertical: 8.h,
        ),
      ),
    );

    if (confirmed == true) {
      setState(() {
        _isLoading = true;
      });

      try {
        await PhotoService.emptyBin();
        setState(() {
          _binPhotos = [];
          _groupedPhotos = {};
          _hasChanges = true;
          _isLoading = false;
          _isSelectionMode = false;
          _selectedPhotos.clear();
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Bin emptied successfully',
                style: GoogleFonts.poppins(fontSize: 14.sp),
              ),
              backgroundColor: const Color(0xFF6C63FF),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.r),
              ),
            ),
          );
        }
      } catch (e) {
        setState(() {
          _isLoading = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Error emptying bin: $e',
                style: GoogleFonts.poppins(fontSize: 14.sp),
              ),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.r),
              ),
            ),
          );
        }
      }
    }
  }

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedPhotos.clear();
      }
    });
  }

  void _togglePhotoSelection(Map<String, dynamic> photo) {
    setState(() {
      if (_selectedPhotos.contains(photo)) {
        _selectedPhotos.remove(photo);
        if (_selectedPhotos.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedPhotos.add(photo);
      }
    });
  }

  Future<void> _restoreSelectedPhotos() async {
    if (_selectedPhotos.isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    try {
      for (var photo in _selectedPhotos) {
        await PhotoService.restoreFromBin(photo);
      }

      // Refresh the bin
      final remainingPhotos = _binPhotos
          .where((photo) => !_selectedPhotos.contains(photo))
          .toList();

      setState(() {
        _binPhotos = remainingPhotos;
        _groupPhotos(remainingPhotos);
        _hasChanges = true;
        _isSelectionMode = false;
        _selectedPhotos.clear();
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_selectedPhotos.length} ${_selectedPhotos.length == 1 ? 'photo' : 'photos'} restored',
              style: GoogleFonts.poppins(fontSize: 14.sp),
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8.r),
            ),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error restoring photos: $e',
              style: GoogleFonts.poppins(fontSize: 14.sp),
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8.r),
            ),
          ),
        );
      }
    }
  }

  Future<void> _deleteSelectedPhotos() async {
    if (_selectedPhotos.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.r),
        ),
        title: Text(
          'Delete Forever',
          style: GoogleFonts.poppins(
            fontSize: 20.sp,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60.w,
              height: 60.w,
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.delete_forever,
                size: 30.sp,
                color: Colors.red,
              ),
            ),
            SizedBox(height: 16.h),
            Text(
              'Permanently delete ${_selectedPhotos.length} selected ${_selectedPhotos.length == 1 ? 'photo' : 'photos'}?',
              style: GoogleFonts.poppins(
                fontSize: 16.sp,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8.h),
            Text(
              'This action cannot be undone',
              style: GoogleFonts.poppins(
                fontSize: 14.sp,
                color: Colors.red,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'CANCEL',
              style: GoogleFonts.poppins(
                fontSize: 14.sp,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.r),
              ),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'DELETE FOREVER',
              style: GoogleFonts.poppins(
                fontSize: 14.sp,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actionsPadding: EdgeInsets.symmetric(
          horizontal: 16.w,
          vertical: 8.h,
        ),
      ),
    );

    if (confirmed == true) {
      setState(() {
        _isLoading = true;
      });

      try {
        for (var photo in _selectedPhotos) {
          await PhotoService.deleteFromBin(photo);
        }

        // Refresh the bin
        final remainingPhotos = _binPhotos
            .where((photo) => !_selectedPhotos.contains(photo))
            .toList();

        setState(() {
          _binPhotos = remainingPhotos;
          _groupPhotos(remainingPhotos);
          _hasChanges = true;
          _isSelectionMode = false;
          _selectedPhotos.clear();
          _isLoading = false;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${_selectedPhotos.length} ${_selectedPhotos.length == 1 ? 'photo' : 'photos'} deleted permanently',
                style: GoogleFonts.poppins(fontSize: 14.sp),
              ),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.r),
              ),
            ),
          );
        }
      } catch (e) {
        setState(() {
          _isLoading = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Error deleting photos: $e',
                style: GoogleFonts.poppins(fontSize: 14.sp),
              ),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.r),
              ),
            ),
          );
        }
      }
    }
  }

  void _openPhoto(Map<String, dynamic> photo,
      {List<Map<String, dynamic>>? photoList, int? index}) {
    if (_isSelectionMode) {
      _togglePhotoSelection(photo);
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BinImageDetailPage(
          photo: photo,
          photoList: photoList ?? _binPhotos,
          currentIndex: index ?? _binPhotos.indexOf(photo),
          onPhotoRestored: () {
            setState(() {
              _hasChanges = true;
            });
            _loadBinPhotos();
          },
          onPhotoDeleted: () {
            setState(() {
              _hasChanges = true;
            });
            _loadBinPhotos();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, _hasChanges);
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: _isSelectionMode
              ? Text(
            '${_selectedPhotos.length} selected',
            style: GoogleFonts.poppins(
              fontSize: 20.sp,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF6C63FF),
            ),
          )
              : Text(
            'Bin',
            style: GoogleFonts.poppins(
              fontSize: 22.sp,
              fontWeight: FontWeight.w600,
            ),
          ),
          leading: _isSelectionMode
              ? IconButton(
            icon: const Icon(Icons.close),
            onPressed: _toggleSelectionMode,
          )
              : IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context, _hasChanges),
          ),
          actions: _isSelectionMode
              ? [
            IconButton(
              icon: const Icon(Icons.restore),
              onPressed: _restoreSelectedPhotos,
              tooltip: 'Restore',
            ),
            IconButton(
              icon: const Icon(Icons.delete_forever),
              onPressed: _deleteSelectedPhotos,
              tooltip: 'Delete Forever',
            ),
          ]
              : [
            if (_binPhotos.isNotEmpty) ...[
              IconButton(
                icon:
                Icon(_isGridView ? Icons.view_list : Icons.grid_view),
                onPressed: () {
                  setState(() {
                    _isGridView = !_isGridView;
                  });
                },
                tooltip: _isGridView ? 'List View' : 'Grid View',
              ),
              IconButton(
                icon: const Icon(Icons.delete_forever),
                onPressed: _emptyBin,
                tooltip: 'Empty Bin',
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (value) {
                  if (value == 'select') {
                    _toggleSelectionMode();
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'select',
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_outline),
                        SizedBox(width: 8.w),
                        const Text('Select'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        body: _isLoading
            ? SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 8.h),
                child: Container(
                  width: 100.w,
                  height: 24.h,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4.r),
                  ),
                ),
              ),
              _isGridView ? _buildShimmerGrid() : _buildShimmerList(),
            ],
          ),
        )
            : _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_binPhotos.isEmpty) {
      return const EmptyState(
        icon: Icons.delete_outline,
        title: 'Bin is Empty',
        message:
        'Photos you delete will appear here for 30 days before being permanently removed.',
      );
    }

    return _isGridView ? _buildGridView() : _buildListView();
  }

  Widget _buildGridView() {
    // If we have grouped photos, show them in sections
    if (_groupedPhotos.isNotEmpty) {
      final dateKeys = _groupedPhotos.keys.toList()
        ..sort((a, b) => b.compareTo(a));

      return ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: dateKeys.length,
        itemBuilder: (context, index) {
          final dateKey = dateKeys[index];
          final photosInGroup = _groupedPhotos[dateKey]!;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 8.h),
                child: Text(
                  _formatDateHeader(dateKey),
                  style: GoogleFonts.poppins(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.all(2.w),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 2.w,
                  mainAxisSpacing: 2.h,
                ),
                itemCount: photosInGroup.length,
                itemBuilder: (context, index) {
                  final photo = photosInGroup[index];
                  return GestureDetector(
                    onTap: () => _openPhoto(
                      photo,
                      photoList: photosInGroup,
                      index: photosInGroup.indexOf(photo),
                    ),
                    onLongPress: _isSelectionMode
                        ? null
                        : () {
                      setState(() {
                        _isSelectionMode = true;
                        _selectedPhotos.add(photo);
                      });
                    },
                    child: Hero(
                      tag: 'bin_photo_${photo['id']}',
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(8.r),
                          border: _selectedPhotos.contains(photo)
                              ? Border.all(
                              color: const Color(0xFF6C63FF), width: 3.w)
                              : null,
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8.r),
                              child: _buildBinPhotoThumbnail(photo),
                            ),
                            if (_selectedPhotos.contains(photo))
                              Positioned(
                                top: 8.w,
                                right: 8.w,
                                child: Container(
                                  width: 24.w,
                                  height: 24.w,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF6C63FF),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.check,
                                    color: Colors.white,
                                    size: 16.sp,
                                  ),
                                ),
                              ),
                            Positioned(
                              bottom: 8.h,
                              right: 8.w,
                              child: FutureBuilder<int>(
                                future: PhotoService.getRemainingDays(photo),
                                builder: (context, snapshot) {
                                  final days = snapshot.data ?? 0;
                                  return Container(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 6.w, vertical: 4.h),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.7),
                                      borderRadius: BorderRadius.circular(12.r),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.timer_outlined,
                                          color: Colors.white,
                                          size: 12.sp,
                                        ),
                                        SizedBox(width: 4.w),
                                        Text(
                                          '$days days',
                                          style: GoogleFonts.poppins(
                                            color: Colors.white,
                                            fontSize: 10.sp,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          );
        },
      );
    }

    // Fallback to simple grid if grouping failed
    return GridView.builder(
      padding: EdgeInsets.all(2.w),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2.w,
        mainAxisSpacing: 2.h,
      ),
      itemCount: _binPhotos.length,
      itemBuilder: (context, index) {
        final photo = _binPhotos[index];
        return GestureDetector(
          onTap: () => _openPhoto(photo),
          onLongPress: () {
            setState(() {
              _isSelectionMode = true;
              _selectedPhotos.add(photo);
            });
          },
          child: Hero(
            tag: 'bin_photo_${photo['id']}',
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8.r),
                border: _selectedPhotos.contains(photo)
                    ? Border.all(color: const Color(0xFF6C63FF), width: 3.w)
                    : null,
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8.r),
                    child: _buildBinPhotoThumbnail(photo),
                  ),

                  // Selection indicator
                  if (_selectedPhotos.contains(photo))
                    Positioned(
                      top: 8.w,
                      right: 8.w,
                      child: Container(
                        width: 24.w,
                        height: 24.w,
                        decoration: const BoxDecoration(
                          color: Color(0xFF6C63FF),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 16.sp,
                        ),
                      ),
                    ),

                  // Expiration indicator
                  Positioned(
                    bottom: 8.h,
                    right: 8.w,
                    child: FutureBuilder<int>(
                      future: PhotoService.getRemainingDays(photo),
                      builder: (context, snapshot) {
                        final days = snapshot.data ?? 0;
                        return Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: 6.w, vertical: 4.h),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.timer_outlined,
                                color: Colors.white,
                                size: 12.sp,
                              ),
                              SizedBox(width: 4.w),
                              Text(
                                '$days days',
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 10.sp,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
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

  Widget _buildBinPhotoThumbnail(Map<String, dynamic> photo) {
    // First try to load from bin directory
    final appDir = Directory.systemTemp; // Use temp for demo, replace with proper app dir
    final fileName = photo['path'].split('/').last;
    final binFilePath = '${appDir.path}/bin/$fileName';
    final binFile = File(binFilePath);

    return FutureBuilder<bool>(
      future: binFile.exists(),
      builder: (context, snapshot) {
        if (snapshot.data == true) {
          return Image.file(
            binFile,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return _buildThumbnailFallback(photo);
            },
          );
        }
        return _buildThumbnailFallback(photo);
      },
    );
  }

  Widget _buildThumbnailFallback(Map<String, dynamic> photo) {
    // Try to load original photo as fallback
    final originalFile = File(photo['path']);

    return FutureBuilder<bool>(
      future: originalFile.exists(),
      builder: (context, snapshot) {
        if (snapshot.data == true) {
          return Image.file(
            originalFile,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                color: Colors.grey.shade300,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      photo['type'] == 'video' ? Icons.videocam : Icons.photo,
                      color: Colors.grey.shade600,
                      size: 24.sp,
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      photo['type'] == 'video' ? 'Video' : 'Photo',
                      style: GoogleFonts.inter(
                        fontSize: 10.sp,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        }

        // Show placeholder with proper icon
        return Container(
          color: Colors.grey.shade300,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                photo['type'] == 'video' ? Icons.videocam : Icons.photo,
                color: Colors.grey.shade600,
                size: 24.sp,
              ),
              SizedBox(height: 4.h),
              Text(
                photo['type'] == 'video' ? 'Video' : 'Photo',
                style: GoogleFonts.inter(
                  fontSize: 10.sp,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildListView() {
    return ListView.builder(
      padding: EdgeInsets.all(8.w),
      itemCount: _binPhotos.length,
      itemBuilder: (context, index) {
        final photo = _binPhotos[index];

        return Slidable(
          key: ValueKey(photo['id']),
          endActionPane: ActionPane(
            motion: const ScrollMotion(),
            children: [
              SlidableAction(
                onPressed: (_) async {
                  await PhotoService.restoreFromBin(photo);
                  setState(() {
                    _binPhotos.remove(photo);
                    _groupPhotos(_binPhotos);
                    _hasChanges = true;
                  });
                },
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                icon: Icons.restore,
                label: 'Restore',
                borderRadius: BorderRadius.circular(12.r),
              ),
              SlidableAction(
                onPressed: (_) async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text('Delete Forever'),
                      content: Text('This action cannot be undone.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text('CANCEL'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: Text('DELETE',
                              style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  );

                  if (confirmed == true) {
                    await PhotoService.deleteFromBin(photo);
                    setState(() {
                      _binPhotos.remove(photo);
                      _groupPhotos(_binPhotos);
                      _hasChanges = true;
                    });
                  }
                },
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                icon: Icons.delete_forever,
                label: 'Delete',
                borderRadius: BorderRadius.circular(12.r),
              ),
            ],
          ),
          child: Card(
            margin: EdgeInsets.only(bottom: 8.h),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12.r),
              onTap: () => _openPhoto(photo),
              onLongPress: () {
                setState(() {
                  _isSelectionMode = true;
                  _selectedPhotos.add(photo);
                });
              },
              child: Container(
                height: 100.h,
                padding: EdgeInsets.all(8.w),
                child: Row(
                  children: [
                    Container(
                      width: 80.w,
                      height: 80.w,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8.r),
                        border: _selectedPhotos.contains(photo)
                            ? Border.all(
                            color: const Color(0xFF6C63FF), width: 2.w)
                            : null,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8.r),
                        child: Image.file(
                          File(photo['path']),
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: Colors.grey.withOpacity(0.2),
                              child: Icon(
                                Icons.error_outline,
                                color: Colors.red,
                                size: 24.sp,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            DateFormat('MMMM d, yyyy - h:mm a').format(
                              DateTime.parse(photo['createDateTime']),
                            ),
                            style: GoogleFonts.poppins(
                              fontSize: 14.sp,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(height: 4.h),
                          FutureBuilder<int>(
                            future: PhotoService.getRemainingDays(photo),
                            builder: (context, snapshot) {
                              final days = snapshot.data ?? 0;
                              return Text(
                                'Expires in $days days',
                                style: GoogleFonts.poppins(
                                  fontSize: 12.sp,
                                  color: days <= 7 ? Colors.red : Colors.grey,
                                ),
                              );
                            },
                          ),
                          SizedBox(height: 4.h),
                          Text(
                            '${photo['width']} × ${photo['height']}',
                            style: GoogleFonts.poppins(
                              fontSize: 12.sp,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_selectedPhotos.contains(photo))
                      Container(
                        width: 24.w,
                        height: 24.w,
                        decoration: const BoxDecoration(
                          color: Color(0xFF6C63FF),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 16.sp,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildShimmerGrid() {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.all(2.w),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 2.w,
          mainAxisSpacing: 2.h,
        ),
        itemCount: 9,
        itemBuilder: (context, index) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8.r),
            ),
          );
        },
      ),
    );
  }

  Widget _buildShimmerList() {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: ListView.builder(
        padding: EdgeInsets.all(8.w),
        itemCount: 5,
        itemBuilder: (context, index) {
          return Card(
            margin: EdgeInsets.only(bottom: 8.h),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Container(
              height: 100.h,
              padding: EdgeInsets.all(8.w),
              child: Row(
                children: [
                  Container(
                    width: 80.w,
                    height: 80.w,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: double.infinity,
                          height: 16.h,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4.r),
                          ),
                        ),
                        SizedBox(height: 8.h),
                        Container(
                          width: 100.w,
                          height: 12.h,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4.r),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
