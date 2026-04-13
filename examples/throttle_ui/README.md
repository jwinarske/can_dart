# throttle_ui

Flutter marine helm dashboard for a throttle control system. All signal
decoding is DBC-driven -- the UI references signals by name from
`ThrottleStandardIDs.dbc`, so schema changes (bit widths, factors, new
signals) require no code changes.

## Target hardware

Designed for a 4.3" Winstar WF43HSIAEDNNB display (480x272) mounted in
portrait orientation. The UI renders inside a fixed 272x480 logical
viewport; a `FittedBox` scales it to fill whatever window the host
provides.

## Screens

- **Connection screen** -- CAN interface picker with auto-detection,
  demo mode for development without hardware
- **Helm screen** -- compass rose, dual throttle quadrants, trim
  indicators, position/COG/SOG readouts, status lamps, fault indicators

## Custom widgets

Compass rose, throttle quadrant, trim indicator, status lamp, readout
tile, and console frame -- all painted with a nautical bridge palette
(deep hull navy, brass accents, foam cyan readouts).

## Dependencies

- `package:can_dbc` -- DBC file parsing
- `package:can_engine` -- zero-copy CAN snapshot pipeline
- `package:can_socket` -- raw frame TX/RX (simulator only)

## Setup

```bash
# 1. Create the vcan interface
sudo modprobe vcan
sudo ip link add dev vcan0 type vcan
sudo ip link set up vcan0

# 2. Start the CLI simulator (in a separate terminal)
dart run throttle_ui:throttle_sim --interface vcan0

# 3. Run the Flutter app
flutter run -d linux
```

Select `vcan0` on the connection screen, or use **Demo Mode**.

## Simulator

`bin/throttle_sim.dart` synthesises HELM_00, HELM_01, POS_RAPID, and
COG_SOG_RAPID traffic onto a vcan interface via `can_socket`. Listens
for HELM_CMD frames from the dashboard and reflects AUX_Relay_Cmd and
Boat_Mode state changes back into the simulated boat state.
