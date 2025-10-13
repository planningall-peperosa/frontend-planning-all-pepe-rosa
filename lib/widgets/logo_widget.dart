import 'package:flutter/material.dart';

class LogoWidget extends StatefulWidget {
  final double height;

  const LogoWidget({super.key, this.height = 150.0});

  @override
  State<LogoWidget> createState() => _LogoWidgetState();
}

class _LogoWidgetState extends State<LogoWidget> {
  double _opacity = 0.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _opacity = 1.0;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _opacity,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeIn,
      child: Container(
        height: widget.height,
        child: Image.asset(
          "assets/images/logo_pepe_rosa.png",
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            // CORREZIONE: La variabile 'theme' viene definita qui,
            // usando il 'context' fornito dall'errorBuilder.
            final theme = Theme.of(context);
            
            return SizedBox(
              height: widget.height,
              child: Center(
                child: Text(
                  "Logo non trovato",
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}