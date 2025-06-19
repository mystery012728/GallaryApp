import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class PermissionService {
  static Future<bool> requestPhotoPermissions(BuildContext context) async {
    try {
      // Request permission
      final PermissionState ps = await PhotoManager.requestPermissionExtend();

      // Check permission status based on the value property
      if (ps.hasAccess) {
        return true;
      }

      // If permission was denied
      final bool shouldRequestAgain = await _showPermissionDialog(context);

      if (shouldRequestAgain) {
        await PhotoManager.openSetting();
        // Check permission again after returning from settings
        final result = await PhotoManager.requestPermissionExtend();
        return result.hasAccess;
      }

      return false;
    } catch (e) {
      // Catch and log any unexpected errors
      debugPrint('Permission request error: $e');
      return false;
    }
  }

  // Dialog method for permission request
  static Future<bool> _showPermissionDialog(BuildContext context) async {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20.r),
          ),
          title: Text(
            'Photo Access Required',
            style: GoogleFonts.poppins(
              fontSize: 20.sp,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80.w,
                height: 80.w,
                decoration: BoxDecoration(
                  color: isDarkMode ? const Color(0xFF2A2A2A) : const Color(0xFFF5F5F5),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.photo_library,
                  size: 40.sp,
                  color: const Color(0xFF6C63FF),
                ),
              ),
              SizedBox(height: 16.h),
              Text(
                'This app needs access to your photos to display them. '
                    'Please grant permission in your device settings.',
                style: GoogleFonts.poppins(
                  fontSize: 14.sp,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              child: Text(
                'CANCEL',
                style: GoogleFonts.poppins(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey,
                ),
              ),
              onPressed: () {
                Navigator.of(context).pop(false);
              },
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C63FF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10.r),
                ),
                padding: EdgeInsets.symmetric(
                  horizontal: 16.w,
                  vertical: 8.h,
                ),
              ),
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              child: Text(
                'OPEN SETTINGS',
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
        );
      },
    ) ??
        false;
  }
}