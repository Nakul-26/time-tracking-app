class Task {
  const Task({
    required this.id,
    required this.name,
    required this.category,
    required this.defaultMinutes,
  });

  final String id;
  final String name;
  final String category;
  final int defaultMinutes;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'name': name,
      'category': category,
      'defaultMinutes': defaultMinutes,
    };
  }

  factory Task.fromMap(String id, Map<dynamic, dynamic> map) {
    final dynamic rawDefaultMinutes = map['defaultMinutes'];

    return Task(
      id: id,
      name: map['name'] as String? ?? '',
      category: map['category'] as String? ?? '',
      defaultMinutes: rawDefaultMinutes is int
          ? rawDefaultMinutes
          : int.tryParse(rawDefaultMinutes?.toString() ?? '') ?? 30,
    );
  }
}
