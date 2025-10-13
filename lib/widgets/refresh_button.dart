import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/preventivi_provider.dart';

class RefreshButton extends StatelessWidget {
  const RefreshButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<PreventiviProvider>(
      builder: (context, prov, _) {
        final busy = prov.isRefreshing || prov.isLoadingCache;

        return IconButton(
          tooltip: 'Aggiorna',
          onPressed: busy
              ? null
              : () async {
                  await prov.hardRefresh(ignoreEditingOpen: true);
                },
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (child, anim) =>
                FadeTransition(opacity: anim, child: ScaleTransition(scale: anim, child: child)),
            child: busy
                ? const SizedBox(
                    key: ValueKey('spinner'),
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh, key: ValueKey('icon')),
          ),
        );
      },
    );
  }
}
