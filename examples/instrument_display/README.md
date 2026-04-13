# instrument_display

NMEA 2000 multi-function instrument display, similar in concept to a
Furuno FI70, Simrad IS35, or Furuno RD33. Connects to a CAN bus via the
`nmea2000` package, decodes sensor data from NMEA 2000 devices, and
renders live gauges and readouts across multiple display pages.

## Pages

| Page       | Data                                             |
|------------|--------------------------------------------------|
| Nav        | Lat/lon, COG, SOG, UTC time                      |
| Wind       | Apparent wind speed and angle, wind indicator     |
| Depth      | Water depth, boat speed                           |
| Engine     | RPM gauge, oil pressure, coolant temp, fuel rate  |
| Electrical | Battery voltage/current, fuel level               |
| Heading    | Compass indicator, rate of turn, rudder angle     |
| Bus        | Device list, online/offline status, frame count   |

## Dependencies

- `package:nmea2000` -- NMEA 2000 protocol layer (Fast Packet, PGN
  definitions, decoder, Nmea2000Ecu)
- `package:nmea2000_bus` -- bus topology tracker and device registry

## Setup

```bash
# 1. Create the vcan interface
sudo modprobe vcan
sudo ip link add dev vcan0 type vcan
sudo ip link set up vcan0

# 2. Start the marine traffic simulator (in a separate terminal)
cd packages/nmea2000
dart run nmea2000:marine_sim --iface=vcan0 --scenario=coastal_cruise

# 3. Generate the Flutter linux runner (first time only)
cd examples/instrument_display
flutter create --platforms=linux .

# 4. Run the display
flutter run -d linux
```

Select `vcan0` on the connection screen, or use **Demo Mode** to run
with synthetic data and no CAN hardware.

## Demo mode

The built-in demo mode generates sinusoidal synthetic values for all
display fields without requiring a CAN interface or the marine simulator.
Use it for UI development and layout iteration.

## Architecture

- **N2kService** (`lib/services/n2k_service.dart`) -- `ChangeNotifier`
  that owns the `Nmea2000Ecu` and `BusRegistry`. Decodes every received
  frame via the PGN registry and stores field values in a flat
  `Map<String, double>`. Widgets read values via `service.signal(name)`.

- **Maritime theme** (`lib/theme/maritime_theme.dart`) -- nautical bridge
  palette: deep hull navy background, foam cyan readouts, brass accents,
  red/amber/green status indicators. Tabular figures throughout.

- **Custom widgets** -- `ValueDisplay` (numeric readout), `LinearGauge`
  (horizontal bar with warning/danger thresholds), `CompassIndicator`
  (heading circle with N/S/E/W), `WindIndicator` (boat + wind arrow).

All unit conversions (radians to degrees, m/s to knots, Kelvin to
Celsius, Pascals to kPa) happen at display time. The service stores raw
NMEA 2000 values.
