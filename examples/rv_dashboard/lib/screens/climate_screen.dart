import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/rvc_service.dart';
import '../theme/cabin_theme.dart';

/// HVAC control page — 2 thermostat zone cards side by side with large,
/// touch-friendly controls. Sends Thermostat Command 1 (DGN 0x1FEF9).
class ClimateScreen extends StatelessWidget {
  const ClimateScreen({super.key, required this.service});

  final RvcService service;

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
                'CLIMATE CONTROL',
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
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _ZonePanel(
                        service: service,
                        zone: 0,
                        zoneName: 'ZONE 1 — MAIN',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ZonePanel(
                        service: service,
                        zone: 1,
                        zoneName: 'ZONE 2 — BEDROOM',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ZonePanel extends StatelessWidget {
  const _ZonePanel({
    required this.service,
    required this.zone,
    required this.zoneName,
  });

  final RvcService service;
  final int zone;
  final String zoneName;

  static const int _thermStatus = 0x1FFE2;
  static const int _thermCmd = 0x1FEF9;

  static const _modeLabels = ['OFF', 'COOL', 'HEAT', 'AUTO', 'FAN'];
  static const _modeIcons = [
    Icons.power_settings_new,
    Icons.ac_unit,
    Icons.whatshot,
    Icons.autorenew,
    Icons.air,
  ];

  @override
  Widget build(BuildContext context) {
    final mode = service.signal(_thermStatus, zone, 'operatingMode');
    final fanSpeed = service.signal(_thermStatus, zone, 'fanSpeed');
    final setHeat = service.signal(_thermStatus, zone, 'setpointHeat');
    final setCool = service.signal(_thermStatus, zone, 'setpointCool');
    final currentTemp = service.signal(_thermStatus, zone, 'ambientTemp');

    final modeIdx = mode?.toInt() ?? -1;
    final fanIdx = fanSpeed?.toInt() ?? -1;

    final modeColor = _colorForMode(modeIdx);

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF241812), Color(0xFF1A1008)],
        ),
        border: Border.all(color: CabinPalette.woodBorder, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              border: const Border(
                bottom: BorderSide(color: CabinPalette.woodBorder),
              ),
              color: modeColor.withValues(alpha: 0.05),
            ),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: modeColor,
                    boxShadow: modeColor != CabinPalette.lampOff
                        ? [
                            BoxShadow(
                              color: modeColor.withValues(alpha: 0.5),
                              blurRadius: 6,
                            ),
                          ]
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    zoneName,
                    style: const TextStyle(
                      color: CabinPalette.copperBright,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // Body — fills available space
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                children: [
                  // Current temperature — hero element
                  Expanded(
                    flex: 3,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'CURRENT',
                            style: TextStyle(
                              color: CabinPalette.warmWhiteDim,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                          Text(
                            currentTemp != null
                                ? '${currentTemp.toStringAsFixed(1)}\u00B0'
                                : '---',
                            style: TextStyle(
                              color: CabinPalette.warmWhite,
                              fontSize: 44,
                              fontWeight: FontWeight.bold,
                              fontFeatures: kTabular,
                              shadows: currentTemp != null
                                  ? [
                                      Shadow(
                                        color: modeColor.withValues(alpha: 0.4),
                                        blurRadius: 10,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                          Text(
                            modeIdx >= 0 && modeIdx < _modeLabels.length
                                ? _modeLabels[modeIdx]
                                : '---',
                            style: TextStyle(
                              color: modeColor,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Mode selector — large touch targets
                  Expanded(
                    flex: 2,
                    child: Row(
                      children: List.generate(5, (i) {
                        final selected = modeIdx == i;
                        final c = _colorForMode(i);
                        return Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(left: i > 0 ? 4 : 0),
                            child: _ModeTile(
                              icon: _modeIcons[i],
                              label: _modeLabels[i],
                              color: c,
                              selected: selected,
                              onTap: () => _sendCmd(
                                mode: i,
                                fanIdx: fanIdx,
                                setHeat: setHeat,
                                setCool: setCool,
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Setpoints — two rows with large +/- buttons
                  _SetpointControl(
                    label: 'HEAT',
                    color: CabinPalette.lampRed,
                    value: setHeat,
                    onChanged: (v) => _sendCmd(
                      mode: modeIdx,
                      fanIdx: fanIdx,
                      setHeat: v,
                      setCool: setCool,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _SetpointControl(
                    label: 'COOL',
                    color: const Color(0xFF4488CC),
                    value: setCool,
                    onChanged: (v) => _sendCmd(
                      mode: modeIdx,
                      fanIdx: fanIdx,
                      setHeat: setHeat,
                      setCool: v,
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Fan speed
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.air,
                        color: CabinPalette.warmWhiteDim,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'FAN: ${fanIdx >= 0 ? const ['AUTO', 'LOW', 'MED', 'HIGH'][fanIdx.clamp(0, 3)] : '---'}',
                        style: const TextStyle(
                          color: CabinPalette.warmWhiteDim,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _sendCmd({
    required int mode,
    required int fanIdx,
    required double? setHeat,
    required double? setCool,
  }) {
    final data = _encodeThermostatCommand(
      instance: zone,
      operatingMode: mode >= 0 ? mode : 0,
      fanMode: service.signal(_thermStatus, zone, 'fanMode')?.toInt() ?? 0,
      fanSpeed: fanIdx >= 0 ? fanIdx : 0,
      setpointHeatC: setHeat ?? 20.0,
      setpointCoolC: setCool ?? 24.0,
    );
    service.sendCommand(_thermCmd, dest: 0xFF, data: data);
  }

  Color _colorForMode(int mode) {
    return switch (mode) {
      0 => CabinPalette.lampOff,
      1 => const Color(0xFF4488CC),
      2 => CabinPalette.lampRed,
      3 => CabinPalette.lampGreen,
      4 => CabinPalette.lampAmber,
      _ => CabinPalette.lampOff,
    };
  }
}

// ── Mode tile — large touch target with icon ─────────────────────────────────

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.2) : Colors.transparent,
          border: Border.all(
            color: selected ? color : CabinPalette.woodBorder,
            width: selected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: selected ? color : CabinPalette.warmWhiteDim,
              size: 22,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: selected ? color : CabinPalette.warmWhiteDim,
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Setpoint control — label + large -/+ buttons + value ─────────────────────

class _SetpointControl extends StatelessWidget {
  const _SetpointControl({
    required this.label,
    required this.color,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final Color color;
  final double? value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final v = value ?? 20.0;
    return Row(
      children: [
        // Label
        SizedBox(
          width: 42,
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ),
        // Minus button
        _RoundButton(
          icon: Icons.remove,
          color: color,
          onTap: () => onChanged((v - 0.5).clamp(15.0, 30.0)),
        ),
        // Value
        Expanded(
          child: Center(
            child: Text(
              value != null ? '${v.toStringAsFixed(1)}\u00B0C' : '---',
              style: const TextStyle(
                color: CabinPalette.warmWhite,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFeatures: kTabular,
              ),
            ),
          ),
        ),
        // Plus button
        _RoundButton(
          icon: Icons.add,
          color: color,
          onTap: () => onChanged((v + 0.5).clamp(15.0, 30.0)),
        ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.15),
          border: Border.all(color: color.withValues(alpha: 0.6), width: 1.5),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }
}

// ── Encoder ──────────────────────────────────────────────────────────────────

Uint8List _encodeThermostatCommand({
  required int instance,
  required int operatingMode,
  required int fanMode,
  required int fanSpeed,
  required double setpointHeatC,
  required double setpointCoolC,
}) {
  final data = Uint8List(8)..fillRange(0, 8, 0xFF);
  final view = ByteData.sublistView(data);
  data[0] = instance & 0xFF;
  data[1] = (operatingMode & 0x0F) | ((fanMode & 0x0F) << 4);
  data[2] = 0x00 | ((fanSpeed & 0x0F) << 4);
  view.setUint16(
    3,
    ((setpointHeatC + 273.0) / 0.03125).round().clamp(0, 0xFFFF),
    Endian.little,
  );
  view.setUint16(
    5,
    ((setpointCoolC + 273.0) / 0.03125).round().clamp(0, 0xFFFF),
    Endian.little,
  );
  data[7] = 0xFF;
  return data;
}
