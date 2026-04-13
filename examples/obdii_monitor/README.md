# obdii_monitor

Flutter OBD-II vehicle diagnostics app. Connects to a vehicle via
SocketCAN and the `can_engine` ISO-TP pipeline to poll live sensor data,
read/clear diagnostic trouble codes, and retrieve the VIN.

## Screens

- **Dashboard** -- animated gauges for RPM, vehicle speed, coolant temp,
  throttle position, engine load, and fuel level
- **DTCs** -- read and clear stored diagnostic trouble codes (Mode 03/04)
- **PID browser** -- browse all standard Mode 01 PIDs with live values

## Features

- Auto-detects CAN interfaces via `/sys/class/net` (ARPHRD_CAN type 280)
- Built-in demo mode with a realistic driving simulator (warmup, idle,
  acceleration, cruise, deceleration phases) for development without
  hardware
- 16 standard OBD-II PIDs decoded: RPM, speed, coolant temp, engine
  load, throttle, MAF, timing advance, intake temp/pressure, fuel trim,
  fuel level, ambient temp, oil temp, barometric pressure, run time
- DTC decoding (P/C/B/U prefix + 4-digit code)
- VIN retrieval via Mode 09 PID 02
- Material 3 dark theme

## Dependencies

- `package:can_engine` -- zero-copy CAN snapshot pipeline with ISO-TP
- `package:can_dbc` -- DBC file parsing (transitive)

## Setup

```bash
# With real hardware (CAN adapter connected to vehicle OBD-II port):
flutter run -d linux
# Select your CAN interface (e.g., can0) on the connection screen.

# Without hardware:
flutter run -d linux
# Use Demo Mode on the connection screen.
```

## Demo mode

The built-in simulator generates realistic OBD-II data by cycling
through driving phases (warmup, idle, acceleration, cruise, deceleration)
with coupled engine dynamics. All PID values update at ~10 Hz with
smooth transitions and realistic noise.
