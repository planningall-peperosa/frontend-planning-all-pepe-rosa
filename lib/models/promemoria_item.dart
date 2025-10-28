class PromemoriaResponse {
  final List<PromemoriaItem> items;

  PromemoriaResponse({required this.items});

  factory PromemoriaResponse.fromJson(Map<String, dynamic> json) {
    final list = (json['items'] as List<dynamic>? ?? [])
        // Il mapping qui è solo per coerenza, ma il SegretarioProvider non userà questa factory JSON
        .map((e) => PromemoriaItem.fromMap(Map<String, dynamic>.from(e as Map))) 
        .toList(growable: false);
    return PromemoriaResponse(items: list);
  }
}

class PromemoriaItem {
  // campi base
  final String preventivoId;
  final String servizioId; // 🚨 NUOVO: Riferimento al singolo servizio nel preventivo (es. nome ruolo o ID)
  final String dataEvento; // ISO yyyy-mm-dd
  final String ruolo;
  final String? fornitore;
  final int numeroOspiti;
  final String? tipoPasto;
  final String? noteServizio;
  
  // 🚨 REMINDER LOGIC FIELDS
  final bool isContattato; 

  // per UI / azioni
  final String id;
  final String deadline; 
  final String statoCalcolato; // 'todo' | 'urgente' | 'done' (Calcolato lato client)

  final String titolo; // "Cliente — Evento"
  final String descrizione; // "Servizio • Fornitore"

  // contatti FORNITORE
  final String? telefono;
  final String? email;
  
  // Calcolato internamente o mappato da backend legacy
  final int offsetOre; 
  final String quando; 

  PromemoriaItem({
    required this.preventivoId,
    required this.servizioId,
    required this.dataEvento,
    required this.ruolo,
    required this.fornitore,
    this.tipoPasto,
    this.noteServizio,
    this.offsetOre = 0,
    this.quando = '',
    this.numeroOspiti = 0,
    required this.id,
    required this.deadline,
    required this.statoCalcolato,
    required this.titolo,
    required this.descrizione,
    required this.telefono,
    required this.email,
    required this.isContattato,
  });

  // Factory per mappare i dati da Firestore (usata dal nuovo Provider)
  factory PromemoriaItem.fromMap(Map<String, dynamic> data) {
    return PromemoriaItem(
      preventivoId: data['preventivo_id'] as String? ?? '',
      servizioId: data['servizio_id'] as String? ?? '', 
      dataEvento: data['data_evento'] as String? ?? '',
      ruolo: data['ruolo'] as String? ?? '',
      fornitore: data['fornitore'] as String?,
      numeroOspiti: (data['numero_ospiti'] as num?)?.toInt() ?? 0,
      tipoPasto: data['tipo_pasto'] as String?,
      noteServizio: data['note_servizio'] as String?,
      id: data['id'] as String? ?? '', 
      deadline: data['deadline'] as String? ?? '',
      statoCalcolato: data['stato_calcolato'] as String? ?? 'todo',
      titolo: data['titolo'] as String? ?? '',
      descrizione: data['descrizione'] as String? ?? '',
      telefono: data['telefono'] as String?,
      email: data['email'] as String?,
      // Mappiamo il campo stato di contatto sul nostro nuovo campo Firestore
      isContattato: data['is_contattato'] as bool? ?? false, 
      offsetOre: (data['offset_ore'] as int?) ?? 0,
      quando: data['quando'] as String? ?? '',
    );
  }
}