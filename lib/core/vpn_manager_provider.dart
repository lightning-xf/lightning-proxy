import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lightning/core/vpn_manager_interface.dart';
import 'package:lightning/core/windows_vpn_manager.dart';

final vpnManagerProvider = Provider<IVpnManager>((ref) {
  return WindowsVpnManager();
});
