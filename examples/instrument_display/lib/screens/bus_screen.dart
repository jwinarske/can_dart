import 'package:flutter/material.dart';
import 'package:nmea2000_bus/nmea2000_bus.dart';

import '../services/n2k_service.dart';
import '../theme/maritime_theme.dart';

/// Bus status page — device list, device count, and rx frame count.
class BusScreen extends StatelessWidget {
  const BusScreen({super.key, required this.service});

  final N2kService service;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final devices = service.devices;
        final sortedAddresses = devices.keys.toList()..sort();

        return Container(
          color: MaritimePalette.deepHull,
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
                      color: MaritimePalette.brassBright,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                  Text(
                    'RX: ${service.rxFrameCount}',
                    style: TextStyle(
                      color: MaritimePalette.foam,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      fontFeatures: kTabular,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Divider(color: MaritimePalette.brass, height: 8),
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
                        color: MaritimePalette.foamDim,
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
                      color: MaritimePalette.consoleBorder,
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

  final DeviceInfo device;

  @override
  Widget build(BuildContext context) {
    final sa = device.address.toRadixString(16).padLeft(2, '0').toUpperCase();
    final modelId = device.productInfo?.modelId ?? '---';
    final isOnline = device.status == DeviceStatus.online;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          // Status indicator dot
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: isOnline
                  ? MaritimePalette.lampGreen
                  : MaritimePalette.lampOff,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          // SA address
          Text(
            '0x$sa',
            style: TextStyle(
              color: MaritimePalette.foam,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              fontFeatures: kTabular,
            ),
          ),
          const SizedBox(width: 16),
          // Model ID
          Expanded(
            child: Text(
              modelId,
              style: const TextStyle(color: MaritimePalette.foam, fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Status text
          Text(
            isOnline ? 'ONLINE' : 'OFFLINE',
            style: TextStyle(
              color: isOnline
                  ? MaritimePalette.lampGreen
                  : MaritimePalette.lampAmber,
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
