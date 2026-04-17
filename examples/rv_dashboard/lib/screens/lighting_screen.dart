import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/rvc_service.dart';
import '../theme/cabin_theme.dart';

/// Lighting control page — 6 zones displayed as vertical channel strips
/// with glowing bulb indicators and vertical brightness sliders. Compact
/// layout fits all channels on screen at once. Bidirectional: sends
/// DC Dimmer Command 2 (DGN 0x1FEDB) when user adjusts.
class LightingScreen extends StatelessWidget {
  const LightingScreen({super.key, required this.service});

  final RvcService service;

  static const _zoneNames = [
    'Living',
    'Kitchen',
    'Bedroom',
    'Bath',
    'Exterior',
    'Awning',
  ];

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        return Container(
          color: CabinPalette.darkWood,
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'LIGHTING CONTROL',
                style: TextStyle(
                  color: CabinPalette.copperBright,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 4),
              const Divider(color: CabinPalette.copper, height: 8),
              const SizedBox(height: 8),
              // All 6 channels in a single row of vertical strips
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: List.generate(6, (i) {
                    if (i > 0) {
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: _LightChannel(
                            service: service,
                            zone: i,
                            zoneName: _zoneNames[i],
                          ),
                        ),
                      );
                    }
                    return Expanded(
                      child: _LightChannel(
                        service: service,
                        zone: i,
                        zoneName: _zoneNames[i],
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A single vertical lighting channel strip: bulb indicator at top,
/// vertical slider in the middle, zone name at bottom.
class _LightChannel extends StatelessWidget {
  const _LightChannel({
    required this.service,
    required this.zone,
    required this.zoneName,
  });

  final RvcService service;
  final int zone;
  final String zoneName;

  static const int _dimmerStatus = 0x1FEDE;
  static const int _dimmerCmd = 0x1FEDB;

  @override
  Widget build(BuildContext context) {
    final brightness = service.signal(_dimmerStatus, zone, 'brightness');
    final enable = service.signal(_dimmerStatus, zone, 'enable');

    final isOn = enable != null && enable == 1;
    final pct = brightness?.clamp(0.0, 100.0) ?? 0.0;

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF221610), Color(0xFF1A1008)],
        ),
        border: Border.all(color: CabinPalette.woodBorder, width: 1),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Column(
        children: [
          // Bulb indicator — tap to toggle
          GestureDetector(
            onTap: () => _sendCommand(
              command: isOn ? 0 : 1,
              brightness: isOn ? 0 : (pct > 0 ? pct : 100),
            ),
            child: SizedBox(
              width: 48,
              height: 48,
              child: CustomPaint(
                painter: _BulbPainter(isOn: isOn, brightness: pct / 100.0),
              ),
            ),
          ),
          const SizedBox(height: 4),

          // Brightness percentage
          Text(
            isOn ? '${pct.toStringAsFixed(0)}%' : 'OFF',
            style: TextStyle(
              color: isOn ? CabinPalette.warmWhite : CabinPalette.warmWhiteDim,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              fontFeatures: kTabular,
              shadows: isOn
                  ? [
                      Shadow(
                        color: CabinPalette.lampAmber.withValues(alpha: 0.4),
                        blurRadius: 4,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(height: 4),

          // Vertical brightness slider — fills remaining space
          Expanded(
            child: RotatedBox(
              quarterTurns:
                  3, // rotate slider to be vertical (bottom=0, top=100)
              child: SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: CabinPalette.lampAmber,
                  inactiveTrackColor: CabinPalette.lampOff,
                  thumbColor: CabinPalette.copperBright,
                  overlayColor: CabinPalette.copper.withValues(alpha: 0.2),
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 8,
                  ),
                ),
                child: Slider(
                  value: pct,
                  min: 0,
                  max: 100,
                  onChanged: (_) {},
                  onChangeEnd: (v) =>
                      _sendCommand(command: v > 0 ? 1 : 0, brightness: v),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),

          // Zone name
          Text(
            zoneName.toUpperCase(),
            style: const TextStyle(
              color: CabinPalette.copperBright,
              fontSize: 9,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  void _sendCommand({required int command, required double brightness}) {
    final data = _encodeDimmerCommand(
      instance: zone,
      group: 0,
      brightness: brightness,
      command: command,
    );
    service.sendCommand(_dimmerCmd, dest: 0xFF, data: data);
  }
}

/// Compact glowing bulb indicator for the channel strip.
class _BulbPainter extends CustomPainter {
  _BulbPainter({required this.isOn, required this.brightness});

  final bool isOn;
  final double brightness; // 0.0 - 1.0

  static const Color _warmAmber = Color(0xFFFFB93B);
  static const Color _warmBright = Color(0xFFFFD080);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) * 0.38;

    if (isOn && brightness > 0) {
      // Outer glow
      final glowR = r + 4 + brightness * 6;
      canvas.drawCircle(
        center,
        glowR,
        Paint()
          ..shader = ui.Gradient.radial(center, glowR, [
            _warmAmber.withValues(alpha: brightness * 0.3),
            _warmAmber.withValues(alpha: 0),
          ])
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 + brightness * 6),
      );

      // Lit bulb
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..shader = ui.Gradient.radial(
            center,
            r,
            [
              Color.lerp(
                _warmBright,
                Colors.white,
                brightness * 0.3,
              )!.withValues(alpha: 0.7 + brightness * 0.3),
              _warmAmber.withValues(alpha: 0.3 + brightness * 0.4),
              _warmAmber.withValues(alpha: 0.05),
            ],
            [0.0, 0.6, 1.0],
          ),
      );

      // Center hot spot
      canvas.drawCircle(
        center,
        r * 0.3,
        Paint()
          ..shader = ui.Gradient.radial(center, r * 0.3, [
            Colors.white.withValues(alpha: brightness * 0.5),
            Colors.white.withValues(alpha: 0),
          ]),
      );

      // Brightness ring arc
      final ringR = r + 2;
      final sweep = 2 * math.pi * brightness;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: ringR),
        -math.pi / 2,
        sweep,
        false,
        Paint()
          ..color = _warmAmber.withValues(alpha: 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    } else {
      // Off state
      canvas.drawCircle(center, r, Paint()..color = const Color(0xFF1A1008));
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..color = CabinPalette.woodBorder.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(_BulbPainter old) =>
      old.isOn != isOn || old.brightness != brightness;
}

/// Encode DC Dimmer Command 2 (DGN 0x1FEDB) payload.
Uint8List _encodeDimmerCommand({
  required int instance,
  required int group,
  required double brightness,
  required int command,
}) {
  final data = Uint8List(8)..fillRange(0, 8, 0xFF);
  data[0] = instance & 0xFF;
  data[1] = group & 0xFF;
  data[2] = (brightness / 0.5).round().clamp(0, 200);
  data[3] = (command & 0x03);
  return data;
}
