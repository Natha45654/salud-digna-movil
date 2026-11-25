/// Datos ficticios de clínicas y estudios para el recorrido de demostración
/// (sección 11: "Datos ficticios de clínicas y estudios: conservar").
library;

class Study {
  final String id;
  final String name;
  final double price;
  const Study(this.id, this.name, this.price);

  Map<String, dynamic> toJson() =>
      {'studyId': id, 'studyName': name, 'price': price};
}

class Clinic {
  final String id;
  final String name;
  final String city;
  const Clinic(this.id, this.name, this.city);

  Map<String, dynamic> toJson() =>
      {'clinicId': id, 'clinicName': name, 'city': city};
}

const studies = <Study>[
  Study('STD-001', 'Ultrasonido abdominal', 350),
  Study('STD-002', 'Ultrasonido obstétrico', 420),
  Study('STD-003', 'Química sanguínea 27 elementos', 290),
  Study('STD-004', 'Rayos X de tórax', 180),
  Study('STD-005', 'Examen de la vista', 0),
];

const clinics = <Clinic>[
  Clinic('CLI-012', 'Salud Digna Guadalajara Centro', 'Guadalajara'),
  Clinic('CLI-015', 'Salud Digna Tlajomulco', 'Tlajomulco de Zúñiga'),
  Clinic('CLI-020', 'Salud Digna Zapopan Patria', 'Zapopan'),
  Clinic('CLI-031', 'Salud Digna Culiacán Centro', 'Culiacán'),
];

Study? studyById(String? id) =>
    id == null ? null : studies.where((s) => s.id == id).firstOrNull;

Clinic? clinicById(String? id) =>
    id == null ? null : clinics.where((c) => c.id == id).firstOrNull;

/// Horarios candidatos de demo (próximos 3 días, de 8:00 a 13:00). La
/// disponibilidad real se consulta al orquestador; ver `availableSlots` del
/// cliente.
List<DateTime> catalogSlots() => availableSlots();

/// Horarios ficticios (próximos días, de 8:00 a 13:00).
List<DateTime> availableSlots() {
  final now = DateTime.now();
  final base = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
  final out = <DateTime>[];
  for (var d = 0; d < 3; d++) {
    for (var h = 8; h <= 13; h++) {
      out.add(base.add(Duration(days: d, hours: h)));
    }
  }
  return out;
}
