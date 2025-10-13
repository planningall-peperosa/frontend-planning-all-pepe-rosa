import 'dart:io';
import 'package:flutter/material.dart';

class FullScreenImageViewer extends StatelessWidget {
  final String imagePathOrUrl;
  final bool isNetworkImage;
  final String tag;
  final String appBarTitle;

  const FullScreenImageViewer({
    Key? key,
    required this.imagePathOrUrl,
    required this.isNetworkImage,
    required this.tag,
    this.appBarTitle = 'Immagine',
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // MODIFICA: Otteniamo il tema per usare i colori.
    final theme = Theme.of(context);

    return Scaffold(
      // Lo sfondo nero è una scelta stilistica per un visualizzatore di immagini,
      // quindi è corretto mantenerlo hardcoded qui.
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(appBarTitle),
        // Anche l'AppBar semi-trasparente è una scelta stilistica specifica.
        backgroundColor: Colors.black54,
        elevation: 0,
      ),
      body: Center(
        child: Hero(
          tag: tag,
          child: InteractiveViewer(
            panEnabled: true,
            minScale: 0.5,
            maxScale: 4.0,
            child: isNetworkImage
                ? Image.network(
                    imagePathOrUrl,
                    fit: BoxFit.contain,
                    loadingBuilder: (BuildContext context, Widget child, ImageChunkEvent? loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Center(
                        child: CircularProgressIndicator(
                          value: loadingProgress.expectedTotalBytes != null
                              ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                              : null,
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      print("[ERROR] FullScreenImageViewer: Errore caricamento Image.network: $error");
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // MODIFICA: Colore icona preso dal tema.
                            Icon(Icons.broken_image, color: theme.colorScheme.onBackground.withOpacity(0.54), size: 60),
                            SizedBox(height: 10),
                            // MODIFICA: Colore testo preso dal tema.
                            Text("Impossibile caricare l'immagine", style: TextStyle(color: theme.colorScheme.onBackground.withOpacity(0.70))),
                          ],
                        ),
                      );
                    },
                  )
                : Image.file(
                    File(imagePathOrUrl),
                    fit: BoxFit.contain,
                     errorBuilder: (context, error, stackTrace) {
                      print("[ERROR] FullScreenImageViewer: Errore caricamento Image.file: $error");
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // MODIFICA: Colore icona preso dal tema.
                            Icon(Icons.broken_image, color: theme.colorScheme.onBackground.withOpacity(0.54), size: 60),
                            SizedBox(height: 10),
                            // MODIFICA: Colore testo preso dal tema.
                            Text("Impossibile caricare l'immagine locale", style: TextStyle(color: theme.colorScheme.onBackground.withOpacity(0.70))),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }
}