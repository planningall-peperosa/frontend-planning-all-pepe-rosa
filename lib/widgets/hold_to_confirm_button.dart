import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../services/haptics_service.dart';

class HoldToConfirmButton extends StatefulWidget {
  const HoldToConfirmButton({
    super.key,
    required this.onConfirmed,
    this.child,
    this.label,
    this.height = 48,
    this.borderRadius = 12,
    this.backgroundColor,
    this.progressColor,
  }) : assert(child != null || label != null, 'Fornisci child o label');

  final VoidCallback onConfirmed;
  final Widget? child;
  final String? label;

  final double height;
  final double borderRadius;
  final Color? backgroundColor;
  final Color? progressColor;

  @override
  State<HoldToConfirmButton> createState() => _HoldToConfirmButtonState();
}

class _HoldToConfirmButtonState extends State<HoldToConfirmButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _confirmTimer;
  bool _holding = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, value: 0);
  }

  @override
  void dispose() {
    _cancelHold(reset: false);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _startHold() async {
    if (_holding) return;
    final settings = context.read<SettingsProvider>();
    final ms = settings.holdConfirmMs;
    final strength = settings.vibrationStrength;

    setState(() => _holding = true);
    _controller
      ..duration = Duration(milliseconds: ms)
      ..forward(from: 0);

    await HapticsService().startHoldingFeedback(strength);

    _confirmTimer?.cancel();
    _confirmTimer = Timer(Duration(milliseconds: ms), () async {
      if (!mounted) return;
      await HapticsService().stopHoldingFeedback();
      await HapticsService().success();
      setState(() => _holding = false);
      widget.onConfirmed();
    });
  }

  Future<void> _cancelHold({bool reset = true}) async {
    _confirmTimer?.cancel();
    await HapticsService().stopHoldingFeedback();
    if (_holding) {
      await HapticsService().cancelTap();
    }
    if (reset) {
      if (mounted) {
        setState(() => _holding = false);
        _controller.value = 0;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = widget.backgroundColor ?? theme.colorScheme.primary;
    final fg = theme.colorScheme.onPrimary;
    final pg = widget.progressColor ?? theme.colorScheme.primaryContainer;

    final child = widget.child ??
        Text(
          widget.label!,
          style: theme.textTheme.labelLarge?.copyWith(color: fg, fontWeight: FontWeight.w600),
        );

    return Semantics(
      button: true,
      label: widget.label ?? 'Tieni premuto per confermare',
      child: GestureDetector(
        onTapDown: (_) => _startHold(),
        onTapUp: (_) => _cancelHold(),
        onTapCancel: () => _cancelHold(),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Container(
              height: widget.height,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(widget.borderRadius),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // progress
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: _controller.value.clamp(0.0, 1.0),
                    child: Container(color: pg),
                  ),
                  // label
                  Center(child: child),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
