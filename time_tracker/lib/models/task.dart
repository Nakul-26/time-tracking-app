class Task {
  const Task({required this.id, required this.name, required this.category});

  final String id;
  final String name;
  final String category;

  Map<String, String> toMap() {
    return <String, String>{'name': name, 'category': category};
  }

  factory Task.fromMap(String id, Map<dynamic, dynamic> map) {
    return Task(
      id: id,
      name: map['name'] as String? ?? '',
      category: map['category'] as String? ?? '',
    );
  }
}
