// lib/services/storage_service.dart

import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Carica una firma su Firebase Storage e restituisce l'URL di download.
  ///
  /// [preventivoId] L'ID del preventivo, usato per creare una cartella dedicata.
  /// [signatureBytes] I dati dell'immagine della firma in formato Uint8List.
  /// [fileName] Il nome del file da salvare (es. 'firma_cliente.png').
  Future<String> uploadSignature(String preventivoId, Uint8List signatureBytes, String fileName) async {
    try {
      // Crea un riferimento al percorso dove salvare il file
      final storageRef = _storage
          .ref()
          .child('firme') // Cartella principale per tutte le firme
          .child(preventivoId) // Sottocartella per questo specifico preventivo
          .child(fileName);

      // Esegue l'upload dei dati
      final uploadTask = storageRef.putData(
        signatureBytes,
        SettableMetadata(contentType: 'image/png'), // Imposta il tipo di contenuto
      );

      // Attende il completamento dell'upload
      final snapshot = await uploadTask.whenComplete(() => {});

      // Ottiene e restituisce l'URL di download
      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      // In caso di errore, loggalo e lancia un'eccezione più specifica
      print('Errore durante il caricamento della firma: $e');
      throw Exception('Caricamento della firma fallito. Riprova.');
    }
  }
}