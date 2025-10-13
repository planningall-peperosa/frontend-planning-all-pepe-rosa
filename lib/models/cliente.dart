// lib/models/cliente.dart
class Cliente {
  final String idCliente;
  final String tipo;
  final String? ruolo;
  final String? ragioneSociale;
  final String? referente;
  final String? telefono01;
  final String? telefono02;
  final String? telefono03;
  final String? indirizzo;
  final String? mail;
  final String? note;
  final int conteggioPreventivi;

  Cliente({
    required this.idCliente,
    required this.tipo,
    this.ruolo,
    this.ragioneSociale,
    this.referente,
    this.telefono01,
    this.telefono02,
    this.telefono03,
    this.indirizzo,
    this.mail,
    this.note,
    this.conteggioPreventivi = 0,
  });

  factory Cliente.fromJson(Map<String, dynamic> json) {
    int conteggio = 0;
    if (json['conteggio_preventivi'] is int) {
      conteggio = json['conteggio_preventivi'];
    } else if (json['conteggio_preventivi'] is String) {
      conteggio = int.tryParse(json['conteggio_preventivi']) ?? 0;
    }

    return Cliente(
      idCliente: json['id_contatto'] ?? json['id_cliente'] ?? '',
      tipo: json['tipo'] ?? 'sconosciuto',
      ruolo: json['ruolo']?.toString(),
      ragioneSociale: json['ragione_sociale']?.toString(),
      referente: json['referente']?.toString(),
      telefono01: json['telefono_01']?.toString(),
      telefono02: json['telefono_02']?.toString(),
      telefono03: json['telefono_03']?.toString(),
      indirizzo: json['indirizzo']?.toString(),
      mail: json['mail']?.toString(),
      note: json['note']?.toString(),
      conteggioPreventivi: conteggio,
    );
  }

  factory Cliente.empty() {
    return Cliente(
      idCliente: '',
      tipo: '',
      ruolo: null,
      ragioneSociale: '',
      referente: '',
      telefono01: '',
      telefono02: null,
      telefono03: null,
      indirizzo: null,
      mail: '',
      note: null,
      conteggioPreventivi: 0,
    );
  }

  // --- METODO AGGIUNTO ---
  Map<String, dynamic> toJson() {
    return {
      'id_cliente': idCliente,
      'tipo': tipo,
      'ruolo': ruolo,
      'ragione_sociale': ragioneSociale,
      'referente': referente,
      'telefono_01': telefono01,
      'telefono_02': telefono02,
      'telefono_03': telefono03,
      'indirizzo': indirizzo,
      'mail': mail,
      'note': note,
      'conteggio_preventivi': conteggioPreventivi,
    };
  }
}