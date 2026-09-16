import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('zh_CN', null);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const LiquidLockApp());
}

class LiquidLockApp extends StatelessWidget {
  const LiquidLockApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Liquid Lock',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
      home: const LockScreen(),
    );
  }
}

class LockScreen extends StatefulWidget {
  const LockScreen({super.key});
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> with TickerProviderStateMixin {
  DateTime _now = DateTime.now();
  Timer? _timer;

  final Battery _battery = Battery();
  BatteryState _batteryState = BatteryState.unknown;
  int _batteryLevel = 0;

  double _dragOffset = 0;
  double _screenHeight = 0;
  bool _isUnlocking = false;
  late AnimationController _snapController;
  Animation<double> _snapAnim = const AlwaysStoppedAnimation(0);

  late AnimationController _particleController;

  bool get _isCharging =>
      _batteryState == BatteryState.charging ||
      _batteryState == BatteryState.full;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });

    _snapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..addListener(() {
        if (mounted) setState(() => _dragOffset = _snapAnim.value);
      });

    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    _initBattery();
  }

  Future<void> _initBattery() async {
    _batteryLevel = await _battery.batteryLevel ?? 0;
    _batteryState = await _battery.batteryState;
    _battery.onBatteryStateChanged.listen((state) async {
      final lvl = await _battery.batteryLevel ?? 0;
      if (mounted) {
        setState(() {
          _batteryState = state;
          _batteryLevel = lvl;
        });
      }
    });
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    _snapController.dispose();
    _particleController.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (_isUnlocking) return;
    setState(() {
      _dragOffset -= d.delta.dy;
      if (_dragOffset < 0) _dragOffset = 0;
      final max = _screenHeight * 0.6;
      if (_dragOffset > max) _dragOffset = max;
    });
  }

  void _onDragEnd(DragEndDetails d) {
    if (_isUnlocking) return;
    final threshold = _screenHeight * 0.15;
    if (_dragOffset >= threshold) {
      _unlock();
    } else {
      _snapBack();
    }
  }

  void _snapBack() {
    final start = _dragOffset;
    _snapController.duration = const Duration(milliseconds: 300);
    _snapAnim = Tween(begin: start, end: 0.0).animate(
      CurvedAnimation(parent: _snapController, curve: Curves.easeOut),
    );
    _snapController.forward(from: 0);
  }

  void _unlock() {
    _isUnlocking = true;
    final start = _dragOffset;
    _snapController.duration = const Duration(milliseconds: 500);
    _snapAnim = Tween(begin: start, end: _screenHeight).animate(
      CurvedAnimation(parent: _snapController, curve: Curves.easeInOut),
    );
    _snapController.forward(from: 0).whenComplete(() {
      // 解锁后直接退出回桌面
      SystemNavigator.pop();
    });
  }

  Future<void> _openPhone() async {
    final Uri phoneUri = Uri(scheme: 'tel');
    if (await canLaunchUrl(phoneUri)) {
      await launchUrl(phoneUri);
    }
  }

  Future<void> _openCamera() async {
    final Uri cameraUri = Uri(scheme: 'googlecamera');
    final Uri fallbackUri = Uri.parse('geo:0,0?q=0,0');
    // Try camera intent
    try {
      await launchUrl(cameraUri);
    } catch (_) {
      // Fallback: try opening camera via intent
      final Uri camera2 = Uri.parse('intent://camera#Intent;action=android.media.action.IMAGE_CAPTURE;end');
      if (await canLaunchUrl(camera2)) {
        await launchUrl(camera2);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    _screenHeight = MediaQuery.of(context).size.height;
    final fade = (_dragOffset / (_screenHeight * 0.25)).clamp(0.0, 1.0);
    final timeStr = DateFormat('HH:mm').format(_now);
    final dateStr = DateFormat('M月d日 EEEE', 'zh_CN').format(_now);

    return Scaffold(
      body: Container(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 壁纸
            Positioned.fill(
              child: Image.asset('assets/wallpaper.webp', fit: BoxFit.cover),
            ),

            // 全局液态玻璃微妙覆盖
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 0.5, sigmaY: 0.5),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withOpacity(0.04),
                        Colors.white.withOpacity(0.01),
                        Colors.black.withOpacity(0.15),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // 充电粒子
            if (_isCharging)
              Positioned.fill(
                child: CustomPaint(
                  painter: _ParticlesPainter(progress: _particleController.value),
                ),
              ),

            // 内容层
            Transform.translate(
              offset: Offset(0, -_dragOffset),
              child: Opacity(
                opacity: (1.0 - fade).clamp(0.0, 1.0),
                child: Stack(
                  children: [
                    // 时间
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 80,
                      left: 0,
                      right: 0,
                      child: Column(
                        children: [
                          Text(
                            timeStr,
                            style: const TextStyle(
                              fontSize: 80,
                              fontWeight: FontWeight.w200,
                              color: Colors.white,
                              letterSpacing: 3,
                              height: 1.0,
                              shadows: [Shadow(blurRadius: 20, color: Colors.black26)],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            dateStr,
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.white.withOpacity(0.8),
                              letterSpacing: 2,
                            ),
                          ),
                          if (_isCharging) ...[
                            const SizedBox(height: 16),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _LightningIcon(size: 18, color: Colors.white),
                                const SizedBox(width: 6),
                                Text(
                                  '$_batteryLevel%',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    color: Colors.white,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),

                    // 电话按钮（左下角）
                    Positioned(
                      left: 30,
                      bottom: 40,
                      child: _LockIconButton(
                        icon: _PhoneIcon(size: 28, color: Colors.white),
                        onTap: _openPhone,
                      ),
                    ),

                    // 相机按钮（右下角）
                    Positioned(
                      right: 30,
                      bottom: 40,
                      child: _LockIconButton(
                        icon: _CameraIcon(size: 28, color: Colors.white),
                        onTap: _openCamera,
                      ),
                    ),

                    // 上滑提示
                    Positioned(
                      bottom: 20,
                      left: 0,
                      right: 0,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ArrowUpIcon(size: 24, color: Colors.white.withOpacity(0.6)),
                          const SizedBox(height: 4),
                          Text(
                            '上滑解锁',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withOpacity(0.5),
                              letterSpacing: 4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 手势
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onVerticalDragUpdate: _onDragUpdate,
                onVerticalDragEnd: _onDragEnd,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 可点击图标按钮
class _LockIconButton extends StatelessWidget {
  final Widget icon;
  final VoidCallback onTap;
  const _LockIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.12),
        ),
        child: Center(child: icon),
      ),
    );
  }
}

/// 电话图标（手绘，非emoji非Material字体）
class _PhoneIcon extends StatelessWidget {
  final double size;
  final Color color;
  const _PhoneIcon({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _PhoneIconPainter(color: color),
    );
  }
}

class _PhoneIconPainter extends CustomPainter {
  final Color color;
  _PhoneIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;

    final path = Path();
    // Simplified phone handset shape
    path.moveTo(size.width * 0.25, size.height * 0.2);
    path.quadraticBezierTo(
      size.width * 0.15, size.height * 0.3,
      size.width * 0.2, size.height * 0.5,
    );
    path.quadraticBezierTo(
      size.width * 0.25, size.height * 0.7,
      size.width * 0.4, size.height * 0.8,
    );
    path.quadraticBezierTo(
      size.width * 0.6, size.height * 0.95,
      size.width * 0.8, size.height * 0.85,
    );
    path.quadraticBezierTo(
      size.width * 0.9, size.height * 0.8,
      size.width * 0.85, size.height * 0.7,
    );
    canvas.drawPath(path, paint);

    // Receiver
    canvas.drawCircle(
      Offset(size.width * 0.25, size.height * 0.25),
      size.width * 0.06,
      Paint()..color = color,
    );
    // Mic
    canvas.drawCircle(
      Offset(size.width * 0.75, size.height * 0.78),
      size.width * 0.06,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _PhoneIconPainter old) => old.color != color;
}

/// 相机图标
class _CameraIcon extends StatelessWidget {
  final double size;
  final Color color;
  const _CameraIcon({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _CameraIconPainter(color: color),
    );
  }
}

class _CameraIconPainter extends CustomPainter {
  final Color color;
  _CameraIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;

    // Camera body
    final bodyRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.1, size.height * 0.25,
        size.width * 0.8, size.height * 0.6,
      ),
      const Radius.circular(4),
    );
    canvas.drawRRect(bodyRect, paint);

    // Top bump
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.35, size.height * 0.15,
          size.width * 0.3, size.height * 0.15,
        ),
        const Radius.circular(3),
      ),
      paint,
    );

    // Lens
    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * 0.55),
      size.width * 0.18,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _CameraIconPainter old) => old.color != color;
}

/// 上箭头
class _ArrowUpIcon extends StatelessWidget {
  final double size;
  final Color color;
  const _ArrowUpIcon({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _ArrowUpPainter(color: color),
    );
  }
}

class _ArrowUpPainter extends CustomPainter {
  final Color color;
  _ArrowUpPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final path = Path();
    path.moveTo(size.width * 0.5, size.height * 0.15);
    path.lineTo(size.width * 0.2, size.height * 0.55);
    path.moveTo(size.width * 0.5, size.height * 0.15);
    path.lineTo(size.width * 0.8, size.height * 0.55);
    canvas.drawPath(path, paint);

    // Line down
    final linePaint = Paint()
      ..color = color.withOpacity(0.5)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width * 0.5, size.height * 0.2),
      Offset(size.width * 0.5, size.height * 0.85),
      linePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ArrowUpPainter old) => old.color != color;
}

/// 闪电图标（充电）
class _LightningIcon extends StatelessWidget {
  final double size;
  final Color color;
  const _LightningIcon({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _LightningPainter(color: color),
    );
  }
}

class _LightningPainter extends CustomPainter {
  final Color color;
  _LightningPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path();
    path.moveTo(size.width * 0.55, 0);
    path.lineTo(size.width * 0.2, size.height * 0.6);
    path.lineTo(size.width * 0.42, size.height * 0.6);
    path.lineTo(size.width * 0.35, size.height);
    path.lineTo(size.width * 0.8, size.height * 0.4);
    path.lineTo(size.width * 0.55, size.height * 0.4);
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _LightningPainter old) => old.color != color;
}

/// 充电粒子
class _ParticlesPainter extends CustomPainter {
  final double progress;
  _ParticlesPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(42);
    const count = 35;
    for (var i = 0; i < count; i++) {
      final seedX = rng.nextDouble();
      final seedSize = rng.nextDouble();
      final seedSpeed = rng.nextDouble();
      final seedDelay = rng.nextDouble();

      final cycle = (progress + seedDelay) % 1.0;
      final x = seedX * size.width + math.sin(cycle * math.pi * 2 + i) * 10;
      final y = size.height - cycle * (size.height + 80) + 40;
      final radius = 2.0 + seedSize * 5.0;
      final opacity = (math.sin(cycle * math.pi) * (0.3 + seedSpeed * 0.4))
          .clamp(0.0, 1.0);

      final paint = Paint()
        ..color = Colors.cyanAccent.withOpacity(opacity * 0.6)
        ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 3);
      canvas.drawCircle(Offset(x, y), radius, paint);

      final core = Paint()..color = Colors.white.withOpacity(opacity * 0.8);
      canvas.drawCircle(Offset(x, y), radius * 0.4, core);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlesPainter old) => old.progress != progress;
}
