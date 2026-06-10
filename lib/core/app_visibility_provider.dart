import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 全局可见性状态 Provider
/// 用于追踪窗口是否处于可见状态（非最小化、非隐藏到托盘）
final appVisibilityProvider = StateProvider<bool>((ref) => true);
