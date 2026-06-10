import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lightning/core/app_visibility_provider.dart';

class AnimatedLogo extends ConsumerStatefulWidget {
  final double size;
  final bool animate;

  const AnimatedLogo({
    super.key,
    this.size = 52,
    this.animate = false, // 🚀 默认关闭动画，极致降低 GPU 占用
  });

  @override
  ConsumerState<AnimatedLogo> createState() => _AnimatedLogoState();
}

class _AnimatedLogoState extends ConsumerState<AnimatedLogo>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8), // 🚀 更长的动画周期，减少重绘频率
    );
    if (widget.animate) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(AnimatedLogo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate != oldWidget.animate) {
      if (widget.animate) {
        _controller.repeat();
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isVisible = ref.watch(appVisibilityProvider);
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;

    // 🧊 P0级休眠优化：后台时不运行动画
    if (mounted) {
      if (isVisible && widget.animate && !_controller.isAnimating) {
        _controller.repeat();
      } else if ((!isVisible || !widget.animate) && _controller.isAnimating) {
        _controller.stop();
      }
    }

    if (!isVisible || !widget.animate) {
      return _buildStaticLogo(color);
    }

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final animationValue = _controller.value;
          return SizedBox(
            width: widget.size * 2.0,
            height: widget.size * 2.0,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 🚀 【性能极致优化】
                // 1. 移除 Opacity Widget，改用 Color.withOpacity 减少渲染层级
                // 2. 预计算颜色值，避免每帧重复计算
                Container(
                  width: widget.size * 1.3,
                  height: widget.size * 1.3,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: color.withOpacity(0.15 + (0.02 * animationValue)), // 🚀 更小的变化幅度
                        blurRadius: 20 + (2 * animationValue),
                        spreadRadius: 1 + (0.5 * animationValue),
                      ),
                    ],
                    gradient: RadialGradient(
                      colors: [
                        color.withOpacity(0.25 + (0.03 * animationValue)),
                        color.withOpacity(0.05 + (0.02 * animationValue)),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
                // Logo Image
                child!,
              ],
            ),
          );
        },
        child: _buildStaticLogo(color, useWrapper: false),
      ),
    );
  }

  Widget _buildStaticLogo(Color color, {bool useWrapper = true}) {
    Widget image = Image.asset(
      'assets/icon.png',
      width: widget.size,
      height: widget.size,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        return Icon(Icons.flash_on_rounded, color: color, size: widget.size);
      },
    );

    if (!useWrapper) return image;

    return SizedBox(
      width: widget.size * 1.5,
      height: widget.size * 1.5,
      child: Center(child: image),
    );
  }
}
