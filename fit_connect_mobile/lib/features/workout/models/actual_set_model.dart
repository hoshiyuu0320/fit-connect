class ActualSet {
  final int setNumber;
  final int reps;
  final double weight;
  final bool done;

  const ActualSet({
    required this.setNumber,
    required this.reps,
    required this.weight,
    required this.done,
  });

  factory ActualSet.fromJson(Map<String, dynamic> json) => ActualSet(
    setNumber: (json['set_number'] as num).toInt(),
    reps: (json['reps'] as num).toInt(),
    weight: (json['weight'] as num).toDouble(),
    done: json['done'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'set_number': setNumber,
    'reps': reps,
    'weight': weight,
    'done': done,
  };

  ActualSet copyWith({
    int? setNumber,
    int? reps,
    double? weight,
    bool? done,
  }) => ActualSet(
    setNumber: setNumber ?? this.setNumber,
    reps: reps ?? this.reps,
    weight: weight ?? this.weight,
    done: done ?? this.done,
  );
}
