import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('zh_CN', null);
  // 完全隐藏状态栏和导航栏，沉浸式锁屏
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
  bool _isUnlocked = false;
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
    if (_isUnlocking || _isUnlocked) return;
    setState(() {
      _dragOffset -= d.delta.dy;
      if (_dragOffset < 0) _dragOffset = 0;
      final max = _screenHeight * 0.6;
      if (_dragOffset > max) _dragOffset = max;
    });
  }

  void _onDragEnd(DragEndDetails d) {
    if (_isUnlocking || _isUnlocked) return;
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
      if (mounted) setState(() => _isUnlocked = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    _screenHeight = MediaQuery.of(context).size.height;
    final fade = (_dragOffset / (_screenHeight * 0.25)).clamp(0.0, 1.0);
    final timeStr = DateFormat('HH:mm').format(_now);
    final dateStr = DateFormat('M月d日 EEEE', 'zh_CN').format(_now);

    if (_isUnlocked) {
      return _buildHomeScreen();
    }

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

            // 全局液态玻璃覆盖（不是卡片，是整屏微妙效果）
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

            // 充电粒子（全局，从底部飘起）
            if (_isCharging)
              Positioned.fill(
                child: CustomPaint(
                  painter: _ParticlesPainter(progress: _particleController.value),
                ),
              ),

            // 内容层（上滑跟随）
            Transform.translate(
              offset: Offset(0, -_dragOffset),
              child: Opacity(
                opacity: (1.0 - fade).clamp(0.0, 1.0),
                child: Stack(
                  children: [
                    // 时间居中偏上
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
                              shadows: [
                                Shadow(blurRadius: 20, color: Colors.black26),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            dateStr,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w400,
                              color: Colors.white.withOpacity(0.8),
                              letterSpacing: 2,
                            ),
                          ),
                          // 充电电量
                          if (_isCharging) ...[
                            const SizedBox(height: 16),
                            Text(
                              '⚡ $_batteryLevel%',
                              style: const TextStyle(
                                fontSize: 18,
                                color: Colors.white,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    // 底部电话图标（左下角，用文字不用矢量）
                    Positioned(
                      left: 30,
                      bottom: 40,
                      child: const Text('📞', style: TextStyle(fontSize: 36)),
                    ),

                    // 底部相机图标（右下角）
                    Positioned(
                      right: 30,
                      bottom: 40,
                      child: const Text('📷', style: TextStyle(fontSize: 36)),
                    ),

                    // 底部上滑提示
                    Positioned(
                      bottom: 20,
                      left: 0,
                      right: 0,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '⌃',
                            style: TextStyle(
                              fontSize: 28,
                              color: Colors.white.withOpacity(0.6),
                              height: 0.8,
                            ),
                          ),
                          const SizedBox(height: 2),
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

  Widget _buildHomeScreen() {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1a1a2e), Color(0xFF16213e)],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                '🔓',
                style: TextStyle(fontSize: 64),
              ),
              const SizedBox(height: 16),
              const Text(
                '已解锁',
                style: TextStyle(fontSize: 24, color: Colors.white),
              ),
              const SizedBox(height: 40),
              GestureDetector(
                onTap: () => setState(() {
                  _isUnlocked = false;
                  _isUnlocking = false;
                  _dragOffset = 0;
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Text(
                    '回到锁屏',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 充电粒子：从底部向上飘
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
