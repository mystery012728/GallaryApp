import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? buttonText;
  final VoidCallback? onButtonPressed;
  final String? lottieAsset;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.buttonText,
    this.onButtonPressed,
    this.lottieAsset,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: EdgeInsets.all(24.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (lottieAsset != null)
              Lottie.asset(
                lottieAsset!,
                width: 180.w,
                height: 180.w,
              )
            else
              Container(
                width: 120.w,
                height: 120.w,
                decoration: BoxDecoration(
                  color: isDarkMode ? const Color(0xFF2A2A2A) : const Color(0xFFF5F5F5),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 60.sp,
                  color: const Color(0xFF6C63FF),
                ),
              ),

            SizedBox(height: 24.h),

            Text(
              title,
              style: GoogleFonts.poppins(
                fontSize: 22.sp,
                fontWeight: FontWeight.w600,
                color: isDarkMode ? Colors.white : Colors.black,
              ),
              textAlign: TextAlign.center,
            ),

            SizedBox(height: 12.h),

            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 16.sp,
                color: isDarkMode ? Colors.white70 : Colors.black54,
              ),
            ),

            if (buttonText != null && onButtonPressed != null) ...[
              SizedBox(height: 32.h),

              ElevatedButton(
                onPressed: onButtonPressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C63FF),
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(
                    horizontal: 32.w,
                    vertical: 12.h,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                ),
                child: Text(
                  buttonText!,
                  style: GoogleFonts.poppins(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ).animate()
                  .fadeIn(
                duration: 600.ms,
                delay: 300.ms,
              )
                  .moveY(
                begin: 20,
                duration: 600.ms,
                curve: Curves.easeOutQuint,
                delay: 300.ms,
              ),
            ],
          ],
        ).animate()
            .fadeIn(
          duration: 800.ms,
          curve: Curves.easeOut,
        ),
      ),
    );
  }
}

