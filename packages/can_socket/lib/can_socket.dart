/// Pure Dart FFI bindings for Linux SocketCAN.
///
/// Provides raw CAN, CAN FD, BCM, ISO-TP, and J1939 socket access
/// via direct libc FFI calls. Intended for CLI tools — Flutter apps
/// should use `can_engine` instead.
library;

export 'src/can_frame.dart';
export 'src/can_filter.dart';
export 'src/can_socket.dart';
export 'src/can_bcm_socket.dart';
export 'src/can_isotp_socket.dart';
export 'src/can_j1939_socket.dart';
export 'src/ffi/constants.dart';
