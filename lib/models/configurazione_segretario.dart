// lib/models/configurazione_segretario.dart

class ConfigurazioneSegretario {
  final String id;
  final int finestraGiorniToDo; // X giorni (default 14)
  final int finestraGiorniUrgente; // Y giorni (default 3)

  ConfigurazioneSegretario({
    required this.id,
    required this.finestraGiorniToDo,
    required this.finestraGiorniUrgente,
  });

  factory ConfigurazioneSegretario.fromMap(Map<String, dynamic> data, String id) {
    return ConfigurazioneSegretario(
      id: id,
      finestraGiorniToDo: (data['finestra_giorni_todo'] as int?) ?? 14,
      finestraGiorniUrgente: (data['finestra_giorni_urgente'] as int?) ?? 3,
    );
  }

  // Configurazione di fallback nel caso non esista nel DB
  static ConfigurazioneSegretario defaultConfig() {
    return ConfigurazioneSegretario(
      id: 'default', 
      finestraGiorniToDo: 14, 
      finestraGiorniUrgente: 3
    );
  }
}