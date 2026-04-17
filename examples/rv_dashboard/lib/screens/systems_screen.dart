import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/rvc_service.dart';
import '../theme/cabin_theme.dart';

/// Systems page — Generator, Inverter, and Charger displayed as three
/// side-by-side panels with status indicators and control buttons.
/// Fits on screen without scrolling.
class SystemsScreen extends StatelessWidget {
  const SystemsScreen({super.key, required this.service});

  final RvcService service;

  static const int _genStatus = 0x1FFDC;
  static const int _genCmd = 0x1FE97;
  static const int _invStatus = 0x1FFC4;
  static const int _invCmd = 0x1FE9D;
  static const int _chgStatus = 0x1FFC7;
  static const int _chgCmd = 0x1FEA0;

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
                'SYSTEMS',
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
              // Three panels side by side — fills available space
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _buildGeneratorPanel()),
                    const SizedBox(width: 8),
                    Expanded(child: _buildInverterPanel()),
                    const SizedBox(width: 8),
                    Expanded(child: _buildChargerPanel()),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Generator panel ────────────────────────────────────────────────────

  Widget _buildGeneratorPanel() {
    final opStatus = service.signal(_genStatus, 0, 'operatingStatus');
    final rpm = service.signal(_genStatus, 0, 'engineSpeed');
    final hours = service.signal(_genStatus, 0, 'engineHours');

    final running = opStatus != null && opStatus == 1;
    final statusLabel = opStatus != null
        ? _genStatusText(opStatus.toInt())
        : 'NO DATA';

    return _SystemPanel(
      title: 'GENERATOR',
      icon: Icons.power,
      isActive: running,
      isFault: false,
      statusLabel: statusLabel,
      readouts: [
        _Readout('RPM', rpm != null ? rpm.toStringAsFixed(0) : '---'),
        _Readout(
          'HOURS',
          hours != null ? hours.toStringAsFixed(1) : '---',
          unit: 'h',
        ),
      ],
      buttons: [
        _CmdButton(
          'START',
          CabinPalette.lampGreen,
          () => _sendGeneratorCommand(1),
        ),
        _CmdButton(
          'STOP',
          CabinPalette.lampRed,
          () => _sendGeneratorCommand(0),
        ),
      ],
    );
  }

  // ── Inverter panel ─────────────────────────────────────────────────────

  Widget _buildInverterPanel() {
    final opStatus = service.signal(_invStatus, 0, 'operatingStatus');
    final dcVoltage = service.signal(_invStatus, 0, 'dcVoltage');

    final enabled = opStatus != null && opStatus == 1;
    final fault = opStatus != null && opStatus == 2;
    String statusLabel;
    if (opStatus == null) {
      statusLabel = 'NO DATA';
    } else if (fault) {
      statusLabel = 'FAULT';
    } else if (enabled) {
      statusLabel = 'ENABLED';
    } else {
      statusLabel = 'DISABLED';
    }

    return _SystemPanel(
      title: 'INVERTER',
      icon: Icons.electrical_services,
      isActive: enabled,
      isFault: fault,
      statusLabel: statusLabel,
      readouts: [
        _Readout(
          'DC VOLTS',
          dcVoltage != null ? dcVoltage.toStringAsFixed(1) : '---',
          unit: 'V',
        ),
      ],
      buttons: [
        _CmdButton(
          'ENABLE',
          CabinPalette.lampGreen,
          () => _sendInverterCommand(1),
        ),
        _CmdButton(
          'DISABLE',
          CabinPalette.lampAmber,
          () => _sendInverterCommand(0),
        ),
      ],
    );
  }

  // ── Charger panel ──────────────────────────────────────────────────────

  Widget _buildChargerPanel() {
    final opState = service.signal(_chgStatus, 0, 'operatingState');
    final chgV = service.signal(_chgStatus, 0, 'chargeVoltage');
    final chgA = service.signal(_chgStatus, 0, 'chargeCurrent');

    String statusLabel;
    bool active = false;
    bool fault = false;
    if (opState == null) {
      statusLabel = 'NO DATA';
    } else {
      final s = opState.toInt();
      statusLabel = _chargerStateText(s);
      active = s >= 1 && s != 2;
      fault = s == 2;
    }

    return _SystemPanel(
      title: 'CHARGER',
      icon: Icons.battery_charging_full,
      isActive: active,
      isFault: fault,
      statusLabel: statusLabel,
      readouts: [
        _Readout(
          'VOLTS',
          chgV != null ? chgV.toStringAsFixed(1) : '---',
          unit: 'V',
        ),
        _Readout(
          'AMPS',
          chgA != null ? chgA.toStringAsFixed(1) : '---',
          unit: 'A',
        ),
      ],
      buttons: [
        _CmdButton(
          'ENABLE',
          CabinPalette.lampGreen,
          () => _sendChargerCommand(1),
        ),
        _CmdButton(
          'DISABLE',
          CabinPalette.lampAmber,
          () => _sendChargerCommand(0),
        ),
      ],
    );
  }

  // ── Command senders ────────────────────────────────────────────────────

  void _sendGeneratorCommand(int command) {
    final data = Uint8List(8)..fillRange(0, 8, 0xFF);
    data[0] = 0;
    data[1] = command & 0x0F;
    service.sendCommand(_genCmd, dest: 0xFF, data: data);
  }

  void _sendInverterCommand(int enable) {
    final data = Uint8List(8)..fillRange(0, 8, 0xFF);
    data[0] = 0;
    data[1] = (enable & 0x03) << 4;
    service.sendCommand(_invCmd, dest: 0xFF, data: data);
  }

  void _sendChargerCommand(int enable) {
    final data = Uint8List(8)..fillRange(0, 8, 0xFF);
    data[0] = 0;
    data[1] = (enable & 0x03) << 4;
    service.sendCommand(_chgCmd, dest: 0xFF, data: data);
  }

  // ── Label helpers ──────────────────────────────────────────────────────

  String _genStatusText(int s) =>
      const {
        0: 'STOPPED',
        1: 'RUNNING',
        2: 'WARMUP',
        3: 'COOLDOWN',
        4: 'PRIMING',
      }[s] ??
      '---';

  String _chargerStateText(int s) =>
      const {
        0: 'DISABLED',
        1: 'ENABLED',
        2: 'FAULT',
        3: 'BULK',
        4: 'ABSORB',
        5: 'FLOAT',
        6: 'EQUALIZE',
      }[s] ??
      '---';
}

// ── Data classes ──────────────────────────────────────────────────────────────

class _Readout {
  const _Readout(this.label, this.value, {this.unit = ''});
  final String label;
  final String value;
  final String unit;
}

class _CmdButton {
  const _CmdButton(this.label, this.color, this.onTap);
  final String label;
  final Color color;
  final VoidCallback onTap;
}

// ── System panel widget ──────────────────────────────────────────────────────

class _SystemPanel extends StatelessWidget {
  const _SystemPanel({
    required this.title,
    required this.icon,
    required this.isActive,
    required this.isFault,
    required this.statusLabel,
    required this.readouts,
    required this.buttons,
  });

  final String title;
  final IconData icon;
  final bool isActive;
  final bool isFault;
  final String statusLabel;
  final List<_Readout> readouts;
  final List<_CmdButton> buttons;

  Color get _lampColor => isFault
      ? CabinPalette.lampRed
      : isActive
      ? CabinPalette.lampGreen
      : CabinPalette.lampOff;

  @override
  Widget build(BuildContext context) {
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
          // ── Header with icon + title ────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: CabinPalette.woodBorder),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: CabinPalette.copper, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: CabinPalette.copperBright,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // ── Status indicator — the hero element ─────────────────────
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Glowing status lamp
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _lampColor.withValues(alpha: 0.2),
                      border: Border.all(
                        color: _lampColor.withValues(alpha: 0.6),
                        width: 2,
                      ),
                      boxShadow: _lampColor != CabinPalette.lampOff
                          ? [
                              BoxShadow(
                                color: _lampColor.withValues(alpha: 0.4),
                                blurRadius: 12,
                                spreadRadius: 2,
                              ),
                            ]
                          : null,
                    ),
                    child: Center(
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _lampColor,
                          boxShadow: _lampColor != CabinPalette.lampOff
                              ? [
                                  BoxShadow(
                                    color: _lampColor.withValues(alpha: 0.6),
                                    blurRadius: 6,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Status label
                  Text(
                    statusLabel,
                    style: TextStyle(
                      color: _lampColor == CabinPalette.lampOff
                          ? CabinPalette.warmWhiteDim
                          : _lampColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                      shadows: _lampColor != CabinPalette.lampOff
                          ? [
                              Shadow(
                                color: _lampColor.withValues(alpha: 0.4),
                                blurRadius: 6,
                              ),
                            ]
                          : null,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Readouts
                  for (final r in readouts)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: _ReadoutRow(readout: r),
                    ),
                ],
              ),
            ),
          ),

          // ── Command buttons ─────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: CabinPalette.woodBorder)),
            ),
            child: Row(
              children: [
                for (var i = 0; i < buttons.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(child: _CommandBtn(btn: buttons[i])),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Readout row ──────────────────────────────────────────────────────────────

class _ReadoutRow extends StatelessWidget {
  const _ReadoutRow({required this.readout});
  final _Readout readout;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${readout.label}  ',
          style: const TextStyle(
            color: CabinPalette.warmWhiteDim,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        Text(
          readout.value,
          style: TextStyle(
            color: CabinPalette.warmWhite,
            fontSize: 26,
            fontWeight: FontWeight.bold,
            fontFeatures: kTabular,
            shadows: readout.value != '---'
                ? [
                    Shadow(
                      color: CabinPalette.warmWhite.withValues(alpha: 0.3),
                      blurRadius: 4,
                    ),
                  ]
                : null,
          ),
        ),
        if (readout.unit.isNotEmpty)
          Text(
            ' ${readout.unit}',
            style: const TextStyle(
              color: CabinPalette.warmWhiteDim,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
      ],
    );
  }
}

// ── Command button ───────────────────────────────────────────────────────────

class _CommandBtn extends StatelessWidget {
  const _CommandBtn({required this.btn});
  final _CmdButton btn;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: btn.onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              btn.color.withValues(alpha: 0.2),
              btn.color.withValues(alpha: 0.08),
            ],
          ),
          border: Border.all(color: btn.color.withValues(alpha: 0.7), width: 1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: Text(
            btn.label,
            style: TextStyle(
              color: btn.color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}
