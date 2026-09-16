import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/scheduler.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('zh_CN', null);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
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
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const LockScreen(),
    );
  }
}

class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // ---- time ----
  DateTime _now = DateTime.now();
  late final Ticker _ticker;

  // ---- battery ----
  final Battery _battery = Battery();
  BatteryState _batteryState = BatteryState.unknown;
  int _batteryLevel = 0;
  Stream<BatteryState>? _batteryStream;

  // ---- swipe ----
  double _dragOffset = 0; // how far finger has dragged up (positive up)
  double _screenHeight = 0;
  bool _isUnlocking = false;
  late final AnimationController _snapController;
  late final Animation<double> _snapAnim;

  // ---- charging edge shimmer ----
  late final AnimationController _chargeGlowController;

  bool get _isCharging =>
      _batteryState == BatteryState.charging ||
      _batteryState == BatteryState.full;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // clock ticker
    _ticker = createTicker((_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _ticker.start();

    // snap-back controller
    _snapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    )..addListener(() {
        setState(() => _dragOffset = _snapAnim.value);
      });
    _snapAnim = CurvedAnimation(parent: _snapController, curve: Curves.easeOut);

    // charging glow loop
    _chargeGlowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _initBattery();
  }

  Future<void> _initBattery() async {
    _batteryLevel = await _battery.batteryLevel ?? 0;
    _batteryState = await _battery.batteryState;
    _batteryStream = _battery.onBatteryStateChanged;
    _batteryStream?.listen((state) {
      _battery.batteryLevel.then((level) {
        if (mounted) {
          setState(() {
            _batteryState = state;
            _batteryLevel = level ?? 0;
          });
        }
      });
    });
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _snapController.dispose();
    _chargeGlowController.dispose();
    super.dispose();
  }

  // ---- swipe logic ----
  void _onVerticalDragUpdate(DragUpdateDetails d) {
    if (_isUnlocking) return;
    setState(() {
      _dragOffset -= d.delta.dy; // drag up => positive
      if (_dragOffset < 0) _dragOffset = 0;
      final max = _screenHeight * 0.5;
      if (_dragOffset > max) _dragOffset = max;
    });
  }

  void _onVerticalDragEnd(DragEndDetails d) {
    if (_isUnlocking) return;
    final threshold = _screenHeight * 0.18;
    if (_dragOffset >= threshold) {
      _unlock();
    } else {
      _snapBack();
    }
  }

  void _snapBack() {
    final start = _dragOffset;
    _snapController.reset();
    _snapAnim = Tween(begin: start, end: 0.0).animate(
      CurvedAnimation(parent: _snapController, curve: Curves.easeOutBack),
    );
    _snapController.forward();
  }

  void _unlock() {
    _isUnlocking = true;
    final start = _dragOffset;
    _snapController.duration = const Duration(milliseconds: 600);
    _snapAnim = Tween(begin: start, end: _screenHeight).animate(
      CurvedAnimation(parent: _snapController, curve: Curves.easeInOut),
    );
    _snapController.forward();
  }

  @override
  Widget build(BuildContext context) {
    _screenHeight = MediaQuery.of(context).size.height;
    final progress = (_dragOffset / (_screenHeight * 0.5)).clamp(0.0, 1.0);
    final fade = (_dragOffset / (_screenHeight * 0.3)).clamp(0.0, 1.0);

    final timeStr = DateFormat('HH:mm').format(_now);
    final dateStr = DateFormat('M月d日 EEEE', 'zh_CN').format(_now);

    return Scaffold(
      body: Container(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ---- wallpaper ----
            Positioned.fill(
              child: Image.asset(
                'assets/wallpaper.webp',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFF0D1B2A), Color(0xFF1B2838), Color(0xFF0D1B2A)],
                    ),
                  ),
                ),
              ),
            ),
            // subtle dark overlay for readability
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.15),
                      Colors.black.withOpacity(0.05),
                      Colors.black.withOpacity(0.25),
                    ],
                  ),
                ),
              ),
            ),

            // ---- charging particles ----
            if (_isCharging)
              Positioned.fill(
                child: CustomPaint(
                  painter: _ChargingParticlesPainter(
                    progress: _chargeGlowController.value,
                  ),
                ),
              ),

            // ---- swipe-up layer: the whole lock screen content ----
            Transform.translate(
              offset: Offset(0, -_dragOffset),
              child: Opacity(
                opacity: (1.0 - fade * 0.9).clamp(0.0, 1.0),
                child: Column(
                  children: [
                    const Spacer(flex: 2),
                    // ---- time + date liquid glass card ----
                    _buildTimeCard(timeStr, dateStr),
                    const Spacer(flex: 3),
                    // ---- bottom swipe hint ----
                    _buildSwipeHint(progress),
                    SizedBox(height: MediaQuery.of(context).padding.bottom + 24),
                  ],
                ),
              ),
            ),

            // ---- gesture detector on top ----
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onVerticalDragUpdate: _onVerticalDragUpdate,
                onVerticalDragEnd: _onVerticalDragEnd,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeCard(String timeStr, String dateStr) {
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 28),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.10),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(
                color: Colors.white.withOpacity(0.18),
                width: 1,
              ),
            ),
            child: CustomPaint(
              painter: _LiquidGlassEdgePainter(
                glowPhase: _isCharging ? _chargeGlowController.value : 0.0,
                isCharging: _isCharging,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // time
                  Text(
                    timeStr,
                    style: const TextStyle(
                      fontSize: 88,
                      fontWeight: FontWeight.w200,
                      color: Colors.white,
                      letterSpacing: 2,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // date
                  Text(
                    dateStr,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                      color: Colors.white.withOpacity(0.65),
                      letterSpacing: 1.5,
                    ),
                  ),
                  // battery percentage when charging
                  if (_isCharging) ...[
                    const SizedBox(height: 12),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          '⚡',
                          style: TextStyle(fontSize: 16, color: Colors.white),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$_batteryLevel%',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
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
          ),
        ),
      ),
    );
  }

  Widget _buildSwipeHint(double progress) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Transform.translate(
          offset: Offset(0, -10 * progress),
          child: Icon(
            Icons.keyboard_arrow_up_rounded,
            size: 36,
            color: Colors.white.withOpacity(0.7 - progress * 0.3),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '上滑解锁',
          style: TextStyle(
            fontSize: 14,
            color: Colors.white.withOpacity(0.55),
            letterSpacing: 4,
          ),
        ),
      ],
    );
  }
}

/// ---- Liquid glass edge painter: top highlight, bottom dark edge,
/// subtle inner shadow, and flowing charging glow.
class _LiquidGlassEdgePainter extends CustomPainter {
  final double glowPhase;
  final bool isCharging;

  _LiquidGlassEdgePainter({required this.glowPhase, required this.isCharging});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(32));

    // top highlight (1px gradient line)
    final topPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Color(0x00FFFFFF),
          Color(0x66FFFFFF),
          Color(0x00FFFFFF),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, 1.5));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, 1.5),
        const Radius.circular(32),
      ),
      topPaint,
    );

    // bottom dark edge
    final bottomPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.black.withOpacity(0.0),
          Colors.black.withOpacity(0.18),
          Colors.black.withOpacity(0.0),
        ],
      ).createShader(Rect.fromLTWH(0, size.height - 2, size.width, 2));
    canvas.drawRect(
      Rect.fromLTWH(0, size.height - 2, size.width, 2),
      bottomPaint,
    );

    // subtle inner shadow on left/right edges
    final innerShadowPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.black.withOpacity(0.12),
          Colors.transparent,
          Colors.transparent,
          Colors.black.withOpacity(0.12),
        ],
      ).createShader(rect);
    canvas.drawRRect(rrect, innerShadowPaint);

    // flowing charging glow along the border
    if (isCharging) {
      final glowPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 6);

      final path = Path()..addRRect(rrect);

      // moving highlight position along the path
      final totalLength = size.width * 2 + size.height * 2;
      final start = (glowPhase * totalLength) % totalLength;

      glowPaint.shader = SweepGradient(
        startAngle: 0,
        endAngle: math.pi * 2,
        colors: [
          Colors.cyanAccent.withOpacity(0.0),
          Colors.cyanAccent.withOpacity(0.8),
          Colors.cyanAccent.withOpacity(0.0),
        ],
        stops: const [0.0, 0.5, 1.0],
        transform: GradientRotation(glowPhase * math.pi * 2),
      ).createShader(rect);

      canvas.drawPath(path, glowPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _LiquidGlassEdgePainter old) =>
      old.glowPhase != glowPhase || old.isCharging != isCharging;
}

/// ---- Charging particles: bubbles/light dots floating upward.
class _ChargingParticlesPainter extends CustomPainter {
  final double progress;

  _ChargingParticlesPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(42); // fixed seed => stable particles
    const count = 40;

    for (var i = 0; i < count; i++) {
      // deterministic per-particle params
      final seedX = rng.nextDouble();
      final seedSize = rng.nextDouble();
      final seedSpeed = rng.nextDouble();
      final seedDelay = rng.nextDouble();

      // cycle 0..1
      final cycle = (progress + seedDelay) % 1.0;

      final x = seedX * size.width +
          math.sin(cycle * math.pi * 2 + i) * 12; // slight drift
      final y = size.height - cycle * (size.height + 100) + 50;

      final radius = 2.0 + seedSize * 6.0;
      final opacity =
          (math.sin(cycle * math.pi) * (0.4 + seedSpeed * 0.4)).clamp(0.0, 1.0);

      final paint = Paint()
        ..color = Colors.cyanAccent.withOpacity(opacity * 0.7)
        ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 3);

      canvas.drawCircle(Offset(x, y), radius, paint);

      // bright core
      final corePaint = Paint()..color = Colors.white.withOpacity(opacity * 0.9);
      canvas.drawCircle(Offset(x, y), radius * 0.4, corePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ChargingParticlesPainter old) =>
      old.progress != progress;
}
