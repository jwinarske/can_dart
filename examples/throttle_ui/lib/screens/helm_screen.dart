// Maritime helm dashboard. Laid out inside a fixed 272×480 portrait
// viewport — the physical target display is a Winstar WF43HSIAEDNNB
// (4.3", 480×272) mounted on its side. The parent of the root widget
// applies a FittedBox that scales this to whatever size the desktop
// window happens to be — so the layout numbers below are in *physical
// display pixels*, never DPs of the host monitor.
//
// Signals are looked up by DBC name (not C struct fields), so the file
// ThrottleStandardIDs.dbc can add or rename entries without us touching
// any code in this screen. Widgets that reference a missing signal just
// show an em-dash or a dark lamp.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/throttle_service.dart';
import '../theme/maritime_theme.dart';
import '../widgets/compass_rose.dart';
import '../widgets/console_frame.dart';
import '../widgets/readout_tile.dart';
import '../widgets/status_lamp.dart';
import '../widgets/throttle_quadrant.dart';
import '../widgets/trim_indicator.dart';

class HelmScreen extends StatelessWidget {
  const HelmScreen({super.key, required this.service});

  final ThrottleService service;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    // Portrait layout, stacked top-to-bottom:
    //   title bar          ~16 px
    //   nav panel          flex 7 (compass is the hero)
    //   propulsion panel   flex 6
    //   status panel       flex 8 (position + fault lamp grid)
    //   bottom bar         ~12 px
    return Container(
      color: MaritimePalette.deepHull,
      padding: const EdgeInsets.all(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _titleBar(),
          const SizedBox(height: 3),
          Expanded(flex: 7, child: _navPanel()),
          const SizedBox(height: 3),
          Expanded(flex: 6, child: _throttlePanel()),
          const SizedBox(height: 3),
          Expanded(flex: 8, child: _statusPanel()),
          const SizedBox(height: 3),
          _bottomBar(),
        ],
      ),
    );
  }

  // ── Top bar ──

  Widget _titleBar() {
    return SizedBox(
      height: 16,
      child: Row(
        children: [
          const Text(
            'HELM',
            style: TextStyle(
              color: MaritimePalette.brassBright,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 2.5,
            ),
          ),
          const SizedBox(width: 4),
          Container(width: 1, color: MaritimePalette.brass),
          const SizedBox(width: 4),
          Text(
            service.isDemoMode
                ? 'DEMO'
                : (service.interfaceName?.toUpperCase() ?? '—'),
            style: const TextStyle(
              color: MaritimePalette.foam,
              fontSize: 9,
              letterSpacing: 1,
            ),
          ),
          const Spacer(),
          _modeToggleRow(),
        ],
      ),
    );
  }

  Widget _modeToggleRow() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _miniToggle(
          label: 'AUX',
          on: service.auxRelayOn,
          onTap: () => service.setAuxRelay(!service.auxRelayOn),
        ),
        const SizedBox(width: 3),
        _miniToggle(
          label: service.boatMode == BoatModeCmd.driving ? 'DRIVE' : 'CHRG',
          on: service.boatMode == BoatModeCmd.driving,
          onTap: () => service.setBoatMode(
            service.boatMode == BoatModeCmd.driving
                ? BoatModeCmd.charging
                : BoatModeCmd.driving,
          ),
        ),
      ],
    );
  }

  Widget _miniToggle({
    required String label,
    required bool on,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 14,
        padding: const EdgeInsets.symmetric(horizontal: 5),
        decoration: BoxDecoration(
          color: on
              ? MaritimePalette.brassBright.withValues(alpha: 0.30)
              : Colors.transparent,
          border: Border.all(
            color: on ? MaritimePalette.brassBright : MaritimePalette.brass,
            width: 0.9,
          ),
          borderRadius: BorderRadius.circular(2),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
              color: on ? MaritimePalette.brassBright : MaritimePalette.brass,
            ),
          ),
        ),
      ),
    );
  }

  // ── Nav panel (compass + GPS-derived readouts) ──

  Widget _navPanel() {
    final cog = service.signalOr('COG', 0); // radians
    final sog = service.signalOr('SOG', 0); // m/s
    final sogKnots = sog * 1.9438444924; // m/s → knots
    final headingDeg = (cog * 180 / math.pi) % 360;

    return ConsoleFrame(
      label: 'Navigation',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Compass hero on the left, readouts stacked on the right —
          // portrait layout gives us the full 264 px width here.
          SizedBox(
            width: 110,
            child: Center(child: CompassRose(headingRad: cog, size: 100)),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ReadoutTile(
                    label: 'Heading',
                    value: headingDeg.toStringAsFixed(0).padLeft(3, '0'),
                    unit: '°',
                    accent: MaritimePalette.foam,
                    valueSize: 20,
                  ),
                ),
                const SizedBox(height: 3),
                Expanded(
                  child: ReadoutTile(
                    label: 'Speed (SOG)',
                    value: sogKnots.toStringAsFixed(1),
                    unit: 'kn',
                    accent: MaritimePalette.brassBright,
                    valueSize: 20,
                  ),
                ),
                const SizedBox(height: 3),
                Expanded(
                  child: ReadoutTile(
                    label: 'COG Ref',
                    value: service.valueLabel('COG_Reference') ?? '—',
                    valueSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Throttle + trim panel ──

  Widget _throttlePanel() {
    final throttle = service.signalOr('Throttle', 0);
    final def = service.signalDef('Throttle');
    final trimState = trimStateFromLabel(service.valueLabel('Tilt_Req'));

    return ConsoleFrame(
      label: 'Propulsion',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Brass lever on the left. Width budget: 13 px label gutter +
          // 38 px slider frame = 51, plus a little breathing room.
          SizedBox(
            width: 54,
            child: Center(
              child: ThrottleQuadrant(
                value: throttle,
                min: def?.minimum ?? -5.12,
                max: def?.maximum ?? 5.11,
                size: const Size(52, 150),
              ),
            ),
          ),
          const SizedBox(width: 3),
          // Engine-trim indicator — graphic up / hold / down arrows.
          // Marine "trim" and the DBC's Tilt_Req signal describe the
          // same axis on an outboard or stern-drive. Helmsmen read this
          // as trim, so we label it that way.
          SizedBox(
            width: 28,
            child: Center(
              child: TrimIndicator(state: trimState, width: 26, height: 150),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 3,
                  child: ReadoutTile(
                    label: 'Throttle',
                    value: throttle.toStringAsFixed(2),
                    unit: def?.unit.isNotEmpty == true ? def!.unit : '',
                    accent: throttle >= 0
                        ? MaritimePalette.starboardGreen
                        : MaritimePalette.portRed,
                    valueSize: 22,
                  ),
                ),
                const SizedBox(height: 3),
                Expanded(
                  flex: 2,
                  child: Row(
                    children: [
                      Expanded(
                        child: ReadoutTile(
                          label: 'Trim',
                          value: _trimShortLabel(trimState),
                          valueSize: 11,
                          accent: _trimAccent(trimState),
                        ),
                      ),
                      const SizedBox(width: 3),
                      Expanded(
                        child: ReadoutTile(
                          label: 'Start/Stop',
                          value: service.signalOr('StartStop', 0) > 0.5
                              ? 'RUN'
                              : 'STOP',
                          valueSize: 12,
                          accent: service.signalOr('StartStop', 0) > 0.5
                              ? MaritimePalette.lampGreen
                              : MaritimePalette.foamDim,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _trimShortLabel(TrimState state) {
    switch (state) {
      case TrimState.up:
        return 'UP';
      case TrimState.down:
        return 'DOWN';
      case TrimState.hold:
        return 'HOLD';
      case TrimState.fault:
        return 'FAULT';
      case TrimState.unknown:
        return '—';
    }
  }

  Color _trimAccent(TrimState state) {
    switch (state) {
      case TrimState.up:
      case TrimState.down:
        return MaritimePalette.lampAmber;
      case TrimState.fault:
        return MaritimePalette.lampRed;
      case TrimState.hold:
        return MaritimePalette.lampGreen;
      case TrimState.unknown:
        return MaritimePalette.foamDim;
    }
  }

  // ── Status panel (position, relays, faults) ──
  //
  // Portrait layout: position on the left, lamp grid on the right. The
  // position box is wider than in landscape because we have room — the
  // lamp grid shrinks to fit what's left.
  Widget _statusPanel() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 6,
          child: ConsoleFrame(label: 'Position', child: _positionBox()),
        ),
        const SizedBox(width: 3),
        Expanded(
          flex: 7,
          child: ConsoleFrame(label: 'Status', child: _faultGrid()),
        ),
      ],
    );
  }

  Widget _positionBox() {
    final lat = service.signal('Latitude');
    final lon = service.signal('Longitude');
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'LAT ${_fmtLatLon(lat, ns: true)}',
          style: const TextStyle(
            fontSize: 10,
            color: MaritimePalette.foam,
            fontWeight: FontWeight.bold,
            fontFeatures: kTabular,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          'LON ${_fmtLatLon(lon, ns: false)}',
          style: const TextStyle(
            fontSize: 10,
            color: MaritimePalette.foam,
            fontWeight: FontWeight.bold,
            fontFeatures: kTabular,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          _gpsQualityLabel(),
          style: const TextStyle(
            fontSize: 7,
            color: MaritimePalette.foamDim,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  String _fmtLatLon(double? value, {required bool ns}) {
    if (value == null) return '—';
    final hemi = ns ? (value >= 0 ? 'N' : 'S') : (value >= 0 ? 'E' : 'W');
    final abs = value.abs();
    final deg = abs.floor();
    final min = (abs - deg) * 60;
    return '$deg°${min.toStringAsFixed(3).padLeft(6, '0')}\' $hemi';
  }

  String _gpsQualityLabel() {
    if (service.signalOr('Flt_GPS', 0) > 0.5) return 'GPS FAULT';
    return 'GPS OK';
  }

  Widget _faultGrid() {
    // Group lamps: relays (green when active), faults (red when active).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _lampRow([
          _lamp('MAIN', 'MAIN_Relay_Status', active: MaritimePalette.lampGreen),
          _lamp('AUX', 'AUX_Relay_Status', active: MaritimePalette.lampGreen),
          _lamp('HVIL', 'HVIL_Relay_Status', active: MaritimePalette.lampGreen),
        ]),
        const SizedBox(height: 2),
        _lampRow([
          _lamp('KEY', 'Key', active: MaritimePalette.lampGreen),
          _lamp('BATT', 'Batt_Status', invert: true),
          _lamp('ESTOP', 'Estop'),
        ]),
        const SizedBox(height: 2),
        _lampRow([
          _lamp('F.CAN', 'Flt_CAN'),
          _lamp('F.GPS', 'Flt_GPS'),
          _lamp('F.SD', 'Flt_SDcard'),
        ]),
        const SizedBox(height: 2),
        _lampRow([
          _lamp('F.THR', 'Flt_ThrottleSensor'),
          _lamp('F.COM', 'Flt_InternalComm'),
          _lamp('F.ANR', 'Flt_ANR'),
        ]),
        const SizedBox(height: 2),
        _lampRow([_lamp('F.UPL', 'Flt_DataUpload')]),
      ],
    );
  }

  Widget _lampRow(List<Widget> lamps) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        for (var i = 0; i < lamps.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          lamps[i],
        ],
      ],
    );
  }

  StatusLamp _lamp(
    String label,
    String signalName, {
    Color active = MaritimePalette.lampRed,
    bool invert = false,
  }) {
    final raw = service.signal(signalName);
    final asserted = raw != null && raw > 0.5;
    return StatusLamp(
      label: label,
      on: invert ? !asserted && raw != null : asserted,
      activeColor: active,
    );
  }

  // ── Bottom bar ──

  Widget _bottomBar() {
    final sw = (service.signal('SW_Major') ?? 0).toInt();
    final swMin = (service.signal('SW_Minor') ?? 0).toInt();
    final serial = (service.signal('Serial_Number') ?? 0).toInt();
    final timer = (service.signal('Sys_Timer') ?? 0).toInt();
    return SizedBox(
      height: 12,
      child: Row(
        children: [
          _bottomItem(
            'SW ${sw.toString().padLeft(2, '0')}.${swMin.toString().padLeft(2, '0')}',
          ),
          const SizedBox(width: 8),
          _bottomItem('SN${serial.toString().padLeft(5, '0')}'),
          const SizedBox(width: 8),
          _bottomItem('t=${timer.toString().padLeft(5, '0')}'),
          const Spacer(),
          const Text(
            'THROTTLESTANDARDIDS.DBC',
            style: TextStyle(
              fontSize: 7,
              color: MaritimePalette.brass,
              letterSpacing: 0.5,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomItem(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 8,
        color: MaritimePalette.foamDim,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        fontFeatures: kTabular,
      ),
    );
  }
}
