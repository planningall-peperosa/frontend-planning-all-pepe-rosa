// lib/models/dipendente.dart
// VERSIONE PIU' ROBUSTA

class Dipendente {
  final String idUnico;
  String nomeDipendente;
  String ruolo;
  String pin;
  String email;
  String telefono;
  String colore;

  String campoExtra01;
  String campoExtra02;
  String campoExtra03;
  String campoExtra04;
  String campoExtra05;
  String campoExtra06;
  String campoExtra07;
  String campoExtra08;
  String campoExtra09;
  String campoExtra10;

  Dipendente({
    required this.idUnico,
    required this.nomeDipendente,
    required this.ruolo,
    required this.pin,
    required this.email,
    required this.telefono,
    required this.colore,
    required this.campoExtra01,
    required this.campoExtra02,
    required this.campoExtra03,
    required this.campoExtra04,
    required this.campoExtra05,
    required this.campoExtra06,
    required this.campoExtra07,
    required this.campoExtra08,
    required this.campoExtra09,
    required this.campoExtra10,
  });

  factory Dipendente.fromJson(Map<String, dynamic> json) {
    // Funzione helper per convertire in modo sicuro qualsiasi valore a stringa
    String _asString(dynamic value) => value?.toString() ?? '';

    return Dipendente(
      idUnico: _asString(json['id_unico']),
      nomeDipendente: _asString(json['nome_dipendente']),
      ruolo: _asString(json['ruolo']),
      pin: _asString(json['pin']),
      email: _asString(json['email']),
      telefono: _asString(json['telefono']),
      colore: _asString(json['colore']),
      campoExtra01: _asString(json['campo_extra_01']),
      campoExtra02: _asString(json['campo_extra_02']),
      campoExtra03: _asString(json['campo_extra_03']),
      campoExtra04: _asString(json['campo_extra_04']),
      campoExtra05: _asString(json['campo_extra_05']),
      campoExtra06: _asString(json['campo_extra_06']),
      campoExtra07: _asString(json['campo_extra_07']),
      campoExtra08: _asString(json['campo_extra_08']),
      campoExtra09: _asString(json['campo_extra_09']),
      campoExtra10: _asString(json['campo_extra_10']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id_unico': idUnico,
      'nome_dipendente': nomeDipendente,
      'ruolo': ruolo,
      'pin': pin,
      'email': email,
      'telefono': telefono,
      'colore': colore,
      'campo_extra_01': campoExtra01,
      'campo_extra_02': campoExtra02,
      'campo_extra_03': campoExtra03,
      'campo_extra_04': campoExtra04,
      'campo_extra_05': campoExtra05,
      'campo_extra_06': campoExtra06,
      'campo_extra_07': campoExtra07,
      'campo_extra_08': campoExtra08,
      'campo_extra_09': campoExtra09,
      'campo_extra_10': campoExtra10,
    };
  }
}