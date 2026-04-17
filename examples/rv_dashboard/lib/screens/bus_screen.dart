import 'package:flutter/material.dart';
import 'package:rvc_bus/rvc_bus.dart';

import '../services/rvc_service.dart';
import '../theme/cabin_theme.dart';

/// Bus status page — device list, device count, and rx frame count.
class BusScreen extends StatelessWidget {
  const BusScreen({super.key, required this.service});

  final RvcService service;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final devices = service.devices;
        final sortedAddresses = devices.keys.toList()..sort();

        return Container(
          color: CabinPalette.darkWood,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with counts
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'DEVICES: ${devices.length}',
                    style: const TextStyle(
                      color: CabinPalette.copperBright,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                  Text(
                    'RX: ${service.rxFrameCount}',
                    style: TextStyle(
                      color: CabinPalette.warmWhite,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      fontFeatures: kTabular,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Divider(color: CabinPalette.copper, height: 8),
              const SizedBox(height: 8),
              // Device list
              if (devices.isEmpty)
                Expanded(
                  child: Center(
                    child: Text(
                      service.isDemoMode
                          ? 'Demo mode \u2014 no bus devices'
                          : 'No devices discovered yet',
                      style: const TextStyle(
                        color: CabinPalette.warmWhiteDim,
                        fontSize: 14,
                      ),
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    itemCount: sortedAddresses.length,
                    separatorBuilder: (_, _) => const Divider(
                      color: CabinPalette.woodBorder,
                      height: 1,
                    ),
                    itemBuilder: (context, index) {
                      final address = sortedAddresses[index];
                      final device = devices[address]!;
                      return _DeviceTile(device: device);
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.device});

  final RvcDeviceInfo device;

  @override
  Widget build(BuildContext context) {
    final sa = device.address.toRadixString(16).padLeft(2, '0').toUpperCase();
    final typeName = device.name.deviceTypeName;
    final isOnline = device.status == RvcDeviceStatus.online;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          // Status indicator dot
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: isOnline ? CabinPalette.lampGreen : CabinPalette.lampOff,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          // SA address
          Text(
            '0x$sa',
            style: TextStyle(
              color: CabinPalette.warmWhite,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              fontFeatures: kTabular,
            ),
          ),
          const SizedBox(width: 16),
          // Device type name
          Expanded(
            child: Text(
              typeName,
              style: const TextStyle(
                color: CabinPalette.warmWhite,
                fontSize: 14,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Status text
          Text(
            isOnline ? 'ONLINE' : 'OFFLINE',
            style: TextStyle(
              color: isOnline ? CabinPalette.lampGreen : CabinPalette.lampAmber,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}
