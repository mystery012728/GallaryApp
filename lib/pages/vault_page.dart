import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:math';

class VaultPage extends StatefulWidget {
  const VaultPage({super.key});

  @override
  State<VaultPage> createState() => _VaultPageState();
}

class _VaultPageState extends State<VaultPage> with TickerProviderStateMixin {
  final LocalAuthentication _localAuth = LocalAuthentication();
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  bool _isFirstTime = true;
  bool _isAuthenticated = false;
  bool _isBiometricAvailable = false;
  bool _isBiometricEnabled = false;
  String _authMethod = '';
  bool _isChangingAuth = false;

  // Setup controllers
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _confirmPinController = TextEditingController();

  // Authentication controllers
  final TextEditingController _authPinController = TextEditingController();
  final TextEditingController _currentPinController = TextEditingController();

  List<int> _pattern = [];
  List<int> _confirmPattern = [];
  List<int> _authPattern = [];
  List<int> _currentPattern = [];

  bool _isSettingUp = false;
  String _currentSetupStep = 'method'; // method, pin, pattern
  String _selectedMethod = '';

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _checkAuthStatus();
    _checkBiometricAvailability();
  }

  void _initializeAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic));

    _fadeController.forward();
    _slideController.forward();
  }

  Future<void> _checkAuthStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final hasAuth = prefs.getBool('vault_has_auth') ?? false;
    final authMethod = prefs.getString('vault_auth_method') ?? '';
    final biometricEnabled = prefs.getBool('vault_biometric_enabled') ?? false;

    setState(() {
      _isFirstTime = !hasAuth;
      _authMethod = authMethod;
      _isBiometricEnabled = biometricEnabled;
    });
  }

  Future<void> _checkBiometricAvailability() async {
    try {
      final isAvailable = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      final availableBiometrics = await _localAuth.getAvailableBiometrics();

      setState(() {
        _isBiometricAvailable = isAvailable &&
            isDeviceSupported &&
            availableBiometrics.isNotEmpty;
      });
    } catch (e) {
      setState(() {
        _isBiometricAvailable = false;
      });
    }
  }

  Future<void> _authenticateWithBiometric() async {
    try {
      final isAuthenticated = await _localAuth.authenticate(
        localizedReason: 'Authenticate to access your vault',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );

      if (isAuthenticated) {
        if (_isChangingAuth) {
          setState(() {
            _isChangingAuth = false;
            _currentSetupStep = 'method';
            _isSettingUp = true;
          });
        } else {
          setState(() {
            _isAuthenticated = true;
          });
          _showVaultContent();
        }
      }
    } catch (e) {
      _showErrorSnackBar('Biometric authentication failed');
    }
  }

  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<void> _saveAuthMethod() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool('vault_has_auth', true);
    await prefs.setString('vault_auth_method', _selectedMethod);

    if (_selectedMethod == 'pin') {
      await prefs.setString('vault_pin', _hashPassword(_pinController.text));
    }

    if (_selectedMethod == 'pattern') {
      await prefs.setString('vault_pattern', _pattern.join(','));
    }

    if (_isBiometricAvailable) {
      await prefs.setBool('vault_biometric_enabled', true);
    }
  }

  Future<bool> _verifyAuthentication() async {
    final prefs = await SharedPreferences.getInstance();

    if (_authMethod == 'pin') {
      final savedPin = prefs.getString('vault_pin') ?? '';
      if (_hashPassword(_authPinController.text) != savedPin) {
        return false;
      }
    }

    if (_authMethod == 'pattern') {
      final savedPattern = prefs.getString('vault_pattern') ?? '';
      if (_authPattern.join(',') != savedPattern) {
        return false;
      }
    }

    return true;
  }

  Future<bool> _verifyCurrentAuth() async {
    final prefs = await SharedPreferences.getInstance();

    if (_authMethod == 'pin') {
      final savedPin = prefs.getString('vault_pin') ?? '';
      if (_hashPassword(_currentPinController.text) != savedPin) {
        return false;
      }
    }

    if (_authMethod == 'pattern') {
      final savedPattern = prefs.getString('vault_pattern') ?? '';
      if (_currentPattern.join(',') != savedPattern) {
        return false;
      }
    }

    return true;
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.inter(fontSize: 14.sp),
        ),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.inter(fontSize: 14.sp),
        ),
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
      ),
    );
  }

  void _showVaultContent() {
    setState(() {
      _isAuthenticated = true;
    });
  }

  Widget _buildMethodSelection() {
    return Column(
      children: [
        Text(
          'Choose Security Method',
          style: GoogleFonts.poppins(
            fontSize: 24.sp,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
        SizedBox(height: 8.h),
        Text(
          'Select how you want to secure your vault',
          style: GoogleFonts.inter(
            fontSize: 16.sp,
            color: Colors.grey.shade600,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: 40.h),

        _buildMethodOption(
          'PIN',
          'Secure your vault with a numeric PIN',
          Icons.pin,
          'pin',
        ),
        SizedBox(height: 16.h),

        _buildMethodOption(
          'Pattern',
          'Use a pattern to unlock your vault',
          Icons.pattern,
          'pattern',
        ),
      ],
    );
  }

  Widget _buildMethodOption(String title, String subtitle, IconData icon, String method) {
    final isSelected = _selectedMethod == method;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedMethod = method;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.shade50 : Colors.white,
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(
            color: isSelected ? Colors.blue.shade300 : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(12.w),
              decoration: BoxDecoration(
                color: isSelected ? Colors.blue.shade100 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Icon(
                icon,
                color: isSelected ? Colors.blue.shade600 : Colors.grey.shade600,
                size: 24.sp,
              ),
            ),
            SizedBox(width: 16.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 14.sp,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle,
                color: Colors.blue.shade600,
                size: 24.sp,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPinSetup() {
    return Column(
      children: [
        Text(
          'Set Your PIN',
          style: GoogleFonts.poppins(
            fontSize: 24.sp,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
        SizedBox(height: 8.h),
        Text(
          'Enter a 4-6 digit PIN',
          style: GoogleFonts.inter(
            fontSize: 16.sp,
            color: Colors.grey.shade600,
          ),
        ),
        SizedBox(height: 40.h),

        TextField(
          controller: _pinController,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 24.sp,
            fontWeight: FontWeight.w600,
            letterSpacing: 8,
          ),
          decoration: InputDecoration(
            hintText: '••••',
            hintStyle: GoogleFonts.inter(
              fontSize: 24.sp,
              color: Colors.grey.shade400,
              letterSpacing: 8,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.r),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.r),
              borderSide: BorderSide(color: Colors.blue.shade400, width: 2),
            ),
            counterText: '',
          ),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        SizedBox(height: 20.h),

        TextField(
          controller: _confirmPinController,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 24.sp,
            fontWeight: FontWeight.w600,
            letterSpacing: 8,
          ),
          decoration: InputDecoration(
            hintText: 'Confirm PIN',
            hintStyle: GoogleFonts.inter(
              fontSize: 16.sp,
              color: Colors.grey.shade400,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.r),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.r),
              borderSide: BorderSide(color: Colors.blue.shade400, width: 2),
            ),
            counterText: '',
          ),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
      ],
    );
  }

  Widget _buildPatternSetup() {
    return Column(
      children: [
        Text(
          'Set Your Pattern',
          style: GoogleFonts.poppins(
            fontSize: 24.sp,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
        SizedBox(height: 8.h),
        Text(
          'Draw a pattern to unlock',
          style: GoogleFonts.inter(
            fontSize: 16.sp,
            color: Colors.grey.shade600,
          ),
        ),
        SizedBox(height: 40.h),

        PatternLockWidget(
          pattern: _pattern,
          onPatternChange: (pattern) {
            setState(() {
              _pattern = pattern;
            });
          },
        ),

        if (_pattern.isNotEmpty) ...[
          SizedBox(height: 30.h),
          Text(
            'Confirm your pattern',
            style: GoogleFonts.inter(
              fontSize: 16.sp,
              color: Colors.grey.shade600,
            ),
          ),
          SizedBox(height: 20.h),
          PatternLockWidget(
            pattern: _confirmPattern,
            onPatternChange: (pattern) {
              setState(() {
                _confirmPattern = pattern;
              });
            },
          ),
        ],
      ],
    );
  }

  Widget _buildVerifyCurrentAuth() {
    return Column(
      children: [
        Text(
          'Verify Current Security',
          style: GoogleFonts.poppins(
            fontSize: 24.sp,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
        SizedBox(height: 8.h),
        Text(
          'Enter your current ${_authMethod == 'pin' ? 'PIN' : 'pattern'} to continue',
          style: GoogleFonts.inter(
            fontSize: 16.sp,
            color: Colors.grey.shade600,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: 40.h),

        if (_authMethod == 'pin') ...[
          TextField(
            controller: _currentPinController,
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 24.sp,
              fontWeight: FontWeight.w600,
              letterSpacing: 8,
            ),
            decoration: InputDecoration(
              hintText: 'Current PIN',
              hintStyle: GoogleFonts.inter(
                fontSize: 16.sp,
                color: Colors.grey.shade400,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
                borderSide: BorderSide(color: Colors.blue.shade400, width: 2),
              ),
              counterText: '',
            ),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
        ],

        if (_authMethod == 'pattern') ...[
          Text(
            'Draw your current pattern',
            style: GoogleFonts.inter(
              fontSize: 16.sp,
              color: Colors.grey.shade600,
            ),
          ),
          SizedBox(height: 20.h),
          PatternLockWidget(
            pattern: _currentPattern,
            onPatternChange: (pattern) {
              setState(() {
                _currentPattern = pattern;
              });
            },
          ),
        ],

        SizedBox(height: 40.h),

        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  setState(() {
                    _isChangingAuth = false;
                  });
                },
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: 16.h),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                ),
                child: Text(
                  'Cancel',
                  style: GoogleFonts.inter(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            SizedBox(width: 16.w),
            Expanded(
              child: ElevatedButton(
                onPressed: () async {
                  final isValid = await _verifyCurrentAuth();
                  if (isValid) {
                    setState(() {
                      _currentSetupStep = 'method';
                      _isSettingUp = true;
                    });
                  } else {
                    _showErrorSnackBar('Invalid ${_authMethod == 'pin' ? 'PIN' : 'pattern'}');
                    _currentPinController.clear();
                    setState(() {
                      _currentPattern.clear();
                    });
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade600,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 16.h),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                ),
                child: Text(
                  'Verify',
                  style: GoogleFonts.inter(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),

        if (_isBiometricEnabled) ...[
          SizedBox(height: 20.h),
          Text(
            'or',
            style: GoogleFonts.inter(
              fontSize: 14.sp,
              color: Colors.grey.shade500,
            ),
          ),
          SizedBox(height: 20.h),
          GestureDetector(
            onTap: _authenticateWithBiometric,
            child: Container(
              padding: EdgeInsets.all(16.w),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.fingerprint,
                    color: Colors.blue.shade600,
                    size: 24.sp,
                  ),
                  SizedBox(width: 8.w),
                  Text(
                    'Use Biometric',
                    style: GoogleFonts.inter(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w600,
                      color: Colors.blue.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAuthenticationScreen() {
    return Column(
      children: [
        Icon(
          Icons.lock_outline,
          size: 80.sp,
          color: Colors.blue.shade400,
        ),
        SizedBox(height: 24.h),
        Text(
          'Unlock Vault',
          style: GoogleFonts.poppins(
            fontSize: 28.sp,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
        SizedBox(height: 8.h),
        Text(
          'Enter your ${_authMethod == 'pin' ? 'PIN' : 'pattern'} to access vault',
          style: GoogleFonts.inter(
            fontSize: 16.sp,
            color: Colors.grey.shade600,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: 40.h),

        if (_authMethod == 'pin') ...[
          TextField(
            controller: _authPinController,
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 24.sp,
              fontWeight: FontWeight.w600,
              letterSpacing: 8,
            ),
            decoration: InputDecoration(
              hintText: 'Enter PIN',
              hintStyle: GoogleFonts.inter(
                fontSize: 16.sp,
                color: Colors.grey.shade400,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
                borderSide: BorderSide(color: Colors.blue.shade400, width: 2),
              ),
              counterText: '',
            ),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
        ],

        if (_authMethod == 'pattern') ...[
          Text(
            'Draw your pattern',
            style: GoogleFonts.inter(
              fontSize: 16.sp,
              color: Colors.grey.shade600,
            ),
          ),
          SizedBox(height: 20.h),
          PatternLockWidget(
            pattern: _authPattern,
            onPatternChange: (pattern) {
              setState(() {
                _authPattern = pattern;
              });
            },
          ),
        ],

        SizedBox(height: 30.h),

        ElevatedButton(
          onPressed: () async {
            final isValid = await _verifyAuthentication();
            if (isValid) {
              setState(() {
                _isAuthenticated = true;
              });
              _showVaultContent();
            } else {
              _showErrorSnackBar('Invalid ${_authMethod == 'pin' ? 'PIN' : 'pattern'}');
              _authPinController.clear();
              setState(() {
                _authPattern.clear();
              });
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue.shade600,
            foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(horizontal: 40.w, vertical: 16.h),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.r),
            ),
          ),
          child: Text(
            'Unlock',
            style: GoogleFonts.inter(
              fontSize: 16.sp,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),

        if (_isBiometricEnabled) ...[
          SizedBox(height: 20.h),
          Text(
            'or',
            style: GoogleFonts.inter(
              fontSize: 14.sp,
              color: Colors.grey.shade500,
            ),
          ),
          SizedBox(height: 20.h),
          GestureDetector(
            onTap: _authenticateWithBiometric,
            child: Container(
              padding: EdgeInsets.all(16.w),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.fingerprint,
                    color: Colors.blue.shade600,
                    size: 24.sp,
                  ),
                  SizedBox(width: 8.w),
                  Text(
                    'Use Biometric',
                    style: GoogleFonts.inter(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w600,
                      color: Colors.blue.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildVaultContent() {
    return Column(
      children: [
        Icon(
          Icons.lock_open_outlined,
          size: 80.sp,
          color: Colors.green.shade400,
        ),
        SizedBox(height: 24.h),
        Text(
          'Coming Soon',
          style: GoogleFonts.poppins(
            fontSize: 28.sp,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
        SizedBox(height: 8.h),
        Text(
          'Secure storage for your private photos',
          style: GoogleFonts.inter(
            fontSize: 16.sp,
            color: Colors.grey.shade600,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: 40.h),

        // Change PIN or Pattern button
        GestureDetector(
          onTap: () {
            setState(() {
              _isAuthenticated = false;
              _isChangingAuth = true;
            });
          },
          child: Container(
            padding: EdgeInsets.all(16.w),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.security,
                  color: Colors.blue.shade600,
                  size: 24.sp,
                ),
                SizedBox(width: 12.w),
                Text(
                  'Change PIN or Pattern',
                  style: GoogleFonts.inter(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w600,
                    color: Colors.blue.shade600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSetupFlow() {
    return Column(
      children: [
        if (_currentSetupStep == 'method') _buildMethodSelection(),
        if (_currentSetupStep == 'pin') _buildPinSetup(),
        if (_currentSetupStep == 'pattern') _buildPatternSetup(),

        SizedBox(height: 40.h),

        Row(
          children: [
            if (_currentSetupStep != 'method')
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _currentSetupStep = 'method';
                    });
                  },
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 16.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                  ),
                  child: Text(
                    'Back',
                    style: GoogleFonts.inter(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            if (_currentSetupStep != 'method') SizedBox(width: 16.w),
            Expanded(
              child: ElevatedButton(
                onPressed: () async {
                  if (_currentSetupStep == 'method') {
                    if (_selectedMethod.isEmpty) {
                      _showErrorSnackBar('Please select a security method');
                      return;
                    }
                    setState(() {
                      _currentSetupStep = _selectedMethod;
                    });
                  } else if (_currentSetupStep == 'pin') {
                    if (_pinController.text.length < 4) {
                      _showErrorSnackBar('PIN must be at least 4 digits');
                      return;
                    }
                    if (_pinController.text != _confirmPinController.text) {
                      _showErrorSnackBar('PINs do not match');
                      return;
                    }

                    await _saveAuthMethod();
                    await _checkAuthStatus();
                    _showSuccessSnackBar('PIN set up successfully!');

                    if (_isChangingAuth) {
                      setState(() {
                        _isChangingAuth = false;
                        _isAuthenticated = true;
                        _isSettingUp = false;
                      });
                    }
                  } else if (_currentSetupStep == 'pattern') {
                    if (_pattern.length < 4) {
                      _showErrorSnackBar('Pattern must have at least 4 points');
                      return;
                    }
                    if (_pattern.toString() != _confirmPattern.toString()) {
                      _showErrorSnackBar('Patterns do not match');
                      return;
                    }

                    await _saveAuthMethod();
                    await _checkAuthStatus();
                    _showSuccessSnackBar('Pattern set up successfully!');

                    if (_isChangingAuth) {
                      setState(() {
                        _isChangingAuth = false;
                        _isAuthenticated = true;
                        _isSettingUp = false;
                      });
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade600,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 16.h),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                ),
                child: Text(
                  _currentSetupStep == 'method' ? 'Continue' : 'Complete Setup',
                  style: GoogleFonts.inter(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _pinController.dispose();
    _confirmPinController.dispose();
    _authPinController.dispose();
    _currentPinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Vault',
          style: GoogleFonts.poppins(
            fontSize: 24.sp,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
      ),
      body: AnimatedBuilder(
        animation: _fadeAnimation,
        builder: (context, child) {
          return Opacity(
            opacity: _fadeAnimation.value,
            child: SlideTransition(
              position: _slideAnimation,
              child: SingleChildScrollView(
                padding: EdgeInsets.all(24.w),
                child: _isAuthenticated
                    ? _buildVaultContent()
                    : _isChangingAuth && !_isSettingUp
                    ? _buildVerifyCurrentAuth()
                    : _isFirstTime || _isSettingUp
                    ? _buildSetupFlow()
                    : _buildAuthenticationScreen(),
              ),
            ),
          );
        },
      ),
    );
  }
}

// Custom Pattern Lock Widget with connected lines
class PatternLockWidget extends StatefulWidget {
  final List<int> pattern;
  final Function(List<int>) onPatternChange;

  const PatternLockWidget({
    Key? key,
    required this.pattern,
    required this.onPatternChange,
  }) : super(key: key);

  @override
  State<PatternLockWidget> createState() => _PatternLockWidgetState();
}

class _PatternLockWidgetState extends State<PatternLockWidget> {
  List<Offset> dotPositions = [];
  Offset? currentPanPosition;
  bool isPanning = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300.w,
      height: 300.h,
      child: GestureDetector(
        onPanStart: (details) {
          setState(() {
            isPanning = true;
            currentPanPosition = details.localPosition;
          });
          _checkDotHit(details.localPosition);
        },
        onPanUpdate: (details) {
          setState(() {
            currentPanPosition = details.localPosition;
          });
          _checkDotHit(details.localPosition);
        },
        onPanEnd: (details) {
          setState(() {
            isPanning = false;
            currentPanPosition = null;
          });
        },
        child: CustomPaint(
          painter: PatternPainter(
            pattern: widget.pattern,
            dotPositions: dotPositions,
            currentPanPosition: currentPanPosition,
            isPanning: isPanning,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Calculate dot positions
              if (dotPositions.isEmpty) {
                dotPositions = _calculateDotPositions(constraints.maxWidth, constraints.maxHeight);
              }
              return Container();
            },
          ),
        ),
      ),
    );
  }

  List<Offset> _calculateDotPositions(double width, double height) {
    List<Offset> positions = [];
    double spacing = width / 4;
    double startX = spacing;
    double startY = spacing;

    for (int i = 0; i < 9; i++) {
      int row = i ~/ 3;
      int col = i % 3;
      positions.add(Offset(startX + col * spacing, startY + row * spacing));
    }
    return positions;
  }

  void _checkDotHit(Offset position) {
    for (int i = 0; i < dotPositions.length; i++) {
      double distance = (position - dotPositions[i]).distance;
      if (distance < 30.w && !widget.pattern.contains(i)) {
        List<int> newPattern = List.from(widget.pattern);
        newPattern.add(i);
        widget.onPatternChange(newPattern);
        break;
      }
    }
  }
}

class PatternPainter extends CustomPainter {
  final List<int> pattern;
  final List<Offset> dotPositions;
  final Offset? currentPanPosition;
  final bool isPanning;

  PatternPainter({
    required this.pattern,
    required this.dotPositions,
    this.currentPanPosition,
    required this.isPanning,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final dotPaint = Paint()
      ..color = Colors.grey.shade300
      ..style = PaintingStyle.fill;

    final selectedDotPaint = Paint()
      ..color = Colors.blue.shade400
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = Colors.blue.shade400
      ..strokeWidth = 4.w
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Draw dots
    for (int i = 0; i < dotPositions.length; i++) {
      bool isSelected = pattern.contains(i);
      canvas.drawCircle(
        dotPositions[i],
        isSelected ? 12.w : 8.w,
        isSelected ? selectedDotPaint : dotPaint,
      );

      // Draw inner circle for selected dots
      if (isSelected) {
        canvas.drawCircle(
          dotPositions[i],
          6.w,
          Paint()..color = Colors.white,
        );
      }
    }

    // Draw lines between connected dots
    if (pattern.length > 1) {
      Path path = Path();
      path.moveTo(dotPositions[pattern[0]].dx, dotPositions[pattern[0]].dy);

      for (int i = 1; i < pattern.length; i++) {
        path.lineTo(dotPositions[pattern[i]].dx, dotPositions[pattern[i]].dy);
      }

      // Draw line to current pan position if panning
      if (isPanning && currentPanPosition != null && pattern.isNotEmpty) {
        path.lineTo(currentPanPosition!.dx, currentPanPosition!.dy);
      }

      canvas.drawPath(path, linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}