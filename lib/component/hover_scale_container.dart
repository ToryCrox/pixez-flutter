import 'package:flutter/material.dart';

/// 鼠标悬浮时的微重力缩放卡片组件（带有 M3 物理反馈和主色调光晕晕染，提升桌面端体验）
class HoverScaleCard extends StatefulWidget {
  final Widget child;
  final double scale;
  final bool isSelected;
  final EdgeInsetsGeometry? margin;
  final Clip clipBehavior;
  final BorderRadiusGeometry? borderRadius;

  const HoverScaleCard({
    super.key,
    required this.child,
    this.scale = 1.03,
    this.isSelected = false,
    this.margin,
    this.clipBehavior = Clip.antiAlias,
    this.borderRadius,
  });

  @override
  State<HoverScaleCard> createState() => _HoverScaleCardState();
}

class _HoverScaleCardState extends State<HoverScaleCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 手动增强悬浮时的颜色以提高区分度（叠加 8% 主题色）
    final baseColor = theme.cardColor;
    final hoverColor = Color.lerp(baseColor, theme.colorScheme.primary, 0.08);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedScale(
        scale: _isHovered ? widget.scale : 1.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutBack, // 带有微弹簧效果
        child: Card(
          elevation: _isHovered ? 12.0 : 1.0, 
          color: _isHovered ? hoverColor : baseColor, // 强化的悬浮颜色
          margin: widget.margin,
          clipBehavior: widget.clipBehavior,
          shape: widget.isSelected
              ? RoundedRectangleBorder(
                  side: BorderSide(
                    color: theme.colorScheme.primary,
                    width: 3,
                  ),
                  borderRadius: BorderRadius.circular(12),
                )
              : null,
          child: widget.child,
        ),
      ),
    );
  }
}


