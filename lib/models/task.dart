/// Estado de una tarea asignada a un mecánico.
/// - [inReview]: el asignado la marcó terminada; un admin/fundador
///   debe confirmarla (va al final para no cambiar los índices guardados).
enum TaskStatus { pending, inProgress, done, inReview }

extension TaskStatusX on TaskStatus {
  String get label {
    switch (this) {
      case TaskStatus.pending:
        return 'Pendiente';
      case TaskStatus.inProgress:
        return 'En curso';
      case TaskStatus.done:
        return 'Terminada';
      case TaskStatus.inReview:
        return 'Por revisar';
    }
  }

  /// Avanza al siguiente estado (para que el mecánico marque su avance).
  TaskStatus get next {
    switch (this) {
      case TaskStatus.pending:
        return TaskStatus.inProgress;
      case TaskStatus.inProgress:
        // El asignado la marca terminada → pasa a revisión del admin.
        return TaskStatus.inReview;
      case TaskStatus.inReview:
        // Solo el admin/fundador la saca de revisión.
        return TaskStatus.inReview;
      case TaskStatus.done:
        return TaskStatus.pending;
    }
  }
}

/// Tarea que el administrador asigna a un mecánico.
class Task {
  final String id;
  final String title;
  final String description;
  final String mechanicId;
  final TaskStatus status;
  final DateTime createdAt;

  /// Nota que deja el admin al rechazarla ("Tarea incompleta...").
  final String? reviewNote;

  /// Cuándo se empezó y cuándo se terminó (para mostrar fecha/hora
  /// y duración en las terminadas).
  final DateTime? startedAt;
  final DateTime? completedAt;

  Task({
    required this.id,
    required this.title,
    required this.description,
    required this.mechanicId,
    this.status = TaskStatus.pending,
    DateTime? createdAt,
    this.reviewNote,
    this.startedAt,
    this.completedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'mechanicId': mechanicId,
        'status': status.index,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'reviewNote': reviewNote,
        'startedAt': startedAt?.millisecondsSinceEpoch,
        'completedAt': completedAt?.millisecondsSinceEpoch,
      };

  factory Task.fromJson(Map<String, dynamic> json) => Task(
        id: json['id'] as String,
        title: json['title'] as String,
        description: json['description'] as String? ?? '',
        mechanicId: json['mechanicId'] as String,
        status: TaskStatus.values[json['status'] as int? ?? 0],
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            json['createdAt'] as int? ?? 0),
        reviewNote: json['reviewNote'] as String?,
        startedAt: json['startedAt'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                json['startedAt'] as int),
        completedAt: json['completedAt'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                json['completedAt'] as int),
      );

  Task copyWith({
    String? title,
    String? description,
    String? mechanicId,
    TaskStatus? status,
    String? reviewNote,
    bool clearReviewNote = false,
    DateTime? startedAt,
    DateTime? completedAt,
  }) =>
      Task(
        id: id,
        title: title ?? this.title,
        description: description ?? this.description,
        mechanicId: mechanicId ?? this.mechanicId,
        status: status ?? this.status,
        createdAt: createdAt,
        reviewNote:
            clearReviewNote ? null : (reviewNote ?? this.reviewNote),
        startedAt: startedAt ?? this.startedAt,
        completedAt: completedAt ?? this.completedAt,
      );
}
