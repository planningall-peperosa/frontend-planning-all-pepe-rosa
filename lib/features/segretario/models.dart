class PromemoriaResponse {
  final List<PromemoriaItem> items;

  PromemoriaResponse({required this.items});

  factory PromemoriaResponse.fromJson(Map<String, dynamic> json) {
    final list = (json['items'] as List<dynamic>? ?? [])
        .map((e) => PromemoriaItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(growable: false);
    return PromemoriaResponse(items: list);
  }
}

class PromemoriaItem {
  // campi base
  final String preventivoId;
  final String dataEvento; // ISO yyyy-mm-dd
  final String ruolo;
  final String? fornitore;
  final int offsetOre;
  final String quando; // ISO datetime

  // per UI / azioni
  final String id;
  final String deadline; // = quando
  final String stato;    // 'todo' | 'overdue' | 'done'

  // **Questi due devono arrivare dal backend così:**
  // - titolo: "Cliente — Evento"
  // - descrizione: "Servizio • Fornitore"
  final String titolo;
  final String descrizione;

  // contatti FORNITORE (non cliente)
  final String? telefono;
  final String? email;

  PromemoriaItem({
    required this.preventivoId,
    required this.dataEvento,
    required this.ruolo,
    required this.fornitore,
    required this.offsetOre,
    required this.quando,
    required this.id,
    required this.deadline,
    required this.stato,
    required this.titolo,
    required this.descrizione,
    required this.telefono,
    required this.email,
  });

  factory PromemoriaItem.fromJson(Map<String, dynamic> json) {
    // Lettura **one-to-one** dei nomi chiave inviati dal backend
    return PromemoriaItem(
      preventivoId: (json['preventivo_id'] ?? '') as String,
      dataEvento: (json['data_evento'] ?? '') as String,
      ruolo: (json['ruolo'] ?? '') as String,
      fornitore: (json['fornitore'] as String?)?.trim(),
      offsetOre: (json['offset_ore'] ?? 0) is int
          ? json['offset_ore'] as int
          : int.tryParse('${json['offset_ore']}') ?? 0,
      quando: (json['quando'] ?? '') as String,
      id: (json['id'] ?? '') as String,
      deadline: (json['deadline'] ?? json['quando'] ?? '') as String,
      stato: (json['stato'] ?? '') as String,

      // 🔧 Qui era l’errore: mappiamo correttamente
      titolo: (json['titolo'] ?? '') as String,         // "Cliente — Evento"
      descrizione: (json['descrizione'] ?? '') as String, // "Servizio • Fornitore"

      // contatti fornitore
      telefono: (json['telefono'] as String?)?.trim(),
      email: (json['email'] as String?)?.trim(),
    );
  }
}
