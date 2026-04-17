import 'package:flutter/material.dart';

import '../services/rvc_service.dart';
import '../theme/cabin_theme.dart';
import '../widgets/tank_bar.dart';

/// Tank levels page — 4 vertical bar indicators for Fresh, Gray, Black,
/// and Propane tanks with compact grouped layout. Read-only.
class TanksScreen extends StatelessWidget {
  const TanksScreen({super.key, required this.service});

  final RvcService service;

  static const int _tankDgn = 0x1FFB7; // 130999

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final freshLevel = service.signal(_tankDgn, 0, 'level');
        final grayLevel = service.signal(_tankDgn, 1, 'level');
        final blackLevel = service.signal(_tankDgn, 2, 'level');
        final propaneLevel = service.signal(_tankDgn, 3, 'level');

        final warnings = <String>[];
        if (freshLevel != null && freshLevel < 5) {
          warnings.add('FRESH WATER CRITICALLY LOW');
        } else if (freshLevel != null && freshLevel < 15) {
          warnings.add('Fresh water low');
        }
        if (propaneLevel != null && propaneLevel < 5) {
          warnings.add('PROPANE CRITICALLY LOW');
        } else if (propaneLevel != null && propaneLevel < 15) {
          warnings.add('Propane low');
        }

        return Container(
          color: CabinPalette.darkWood,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'TANK LEVELS',
                    style: TextStyle(
                      color: CabinPalette.copperBright,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Divider(color: CabinPalette.copper, height: 8),
              const SizedBox(height: 8),

              // Summary row
              _SummaryRow(
                freshLevel: freshLevel,
                grayLevel: grayLevel,
                blackLevel: blackLevel,
                propaneLevel: propaneLevel,
              ),
              const SizedBox(height: 12),

              // Tank bars — constrained width, clustered together
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 500),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: TankBar(
                            level: freshLevel,
                            label: 'FRESH',
                            fillColor: const Color(0xFF4488CC),
                            tankType: 'fresh',
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TankBar(
                            level: grayLevel,
                            label: 'GRAY',
                            fillColor: const Color(0xFF8899AA),
                            tankType: 'gray',
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TankBar(
                            level: blackLevel,
                            label: 'BLACK',
                            fillColor: const Color(0xFF556666),
                            tankType: 'black',
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TankBar(
                            level: propaneLevel,
                            label: 'LPG',
                            fillColor: CabinPalette.lampAmber,
                            tankType: 'lpg',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Warning text at the bottom
              if (warnings.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (final warning in warnings)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: warning.contains('CRITICALLY')
                                ? CabinPalette.lampRed
                                : CabinPalette.lampAmber,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color:
                                    (warning.contains('CRITICALLY')
                                            ? CabinPalette.lampRed
                                            : CabinPalette.lampAmber)
                                        .withValues(alpha: 0.6),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          warning.toUpperCase(),
                          style: TextStyle(
                            color: warning.contains('CRITICALLY')
                                ? CabinPalette.lampRed
                                : CabinPalette.lampAmber,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Compact summary row showing all 4 tank values.
class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.freshLevel,
    required this.grayLevel,
    required this.blackLevel,
    required this.propaneLevel,
  });

  final double? freshLevel;
  final double? grayLevel;
  final double? blackLevel;
  final double? propaneLevel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1A1008), Color(0xFF221610)],
        ),
        border: Border.all(color: CabinPalette.woodBorder, width: 0.8),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _SummaryItem(
            label: 'FW',
            level: freshLevel,
            color: const Color(0xFF4488CC),
          ),
          _divider(),
          _SummaryItem(
            label: 'GW',
            level: grayLevel,
            color: const Color(0xFF8899AA),
          ),
          _divider(),
          _SummaryItem(
            label: 'BW',
            level: blackLevel,
            color: const Color(0xFF556666),
          ),
          _divider(),
          _SummaryItem(
            label: 'LP',
            level: propaneLevel,
            color: CabinPalette.lampAmber,
          ),
        ],
      ),
    );
  }

  Widget _divider() {
    return Container(width: 1, height: 20, color: CabinPalette.woodBorder);
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({
    required this.label,
    required this.level,
    required this.color,
  });

  final String label;
  final double? level;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final pct = level?.clamp(0.0, 100.0);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.8),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '$label ',
          style: const TextStyle(
            color: CabinPalette.copper,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        Text(
          pct != null ? '${pct.toStringAsFixed(0)}%' : '---',
          style: TextStyle(
            color: CabinPalette.warmWhite,
            fontSize: 13,
            fontWeight: FontWeight.bold,
            fontFeatures: kTabular,
            shadows: pct != null
                ? [
                    Shadow(
                      color: CabinPalette.warmWhite.withValues(alpha: 0.3),
                      blurRadius: 4,
                    ),
                  ]
                : null,
          ),
        ),
      ],
    );
  }
}
