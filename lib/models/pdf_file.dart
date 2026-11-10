class PdfFile {
  final String name;
  final String path;
  final DateTime createdAt;
  final int size;
  final bool isImported;

  PdfFile({
    required this.name,
    required this.path,
    required this.createdAt,
    required this.size,
    this.isImported = false,
  });

  PdfFile copyWith({
    String? name,
    String? path,
    DateTime? createdAt,
    int? size,
    bool? isImported,
  }) {
    return PdfFile(
      name: name ?? this.name,
      path: path ?? this.path,
      createdAt: createdAt ?? this.createdAt,
      size: size ?? this.size,
      isImported: isImported ?? this.isImported,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'path': path,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'size': size,
      'isImported': isImported,
    };
  }

  factory PdfFile.fromJson(Map<String, dynamic> json) {
    final rawCreatedAt = json['createdAt'];
    final DateTime parsedDate;
    if (rawCreatedAt is int) {
      parsedDate = DateTime.fromMillisecondsSinceEpoch(rawCreatedAt);
    } else if (rawCreatedAt is String) {
      parsedDate = DateTime.tryParse(rawCreatedAt) ?? DateTime.now();
    } else {
      parsedDate = DateTime.now();
    }

    return PdfFile(
      name: (json['name'] as String?) ?? 'Document.pdf',
      path: (json['path'] as String?) ?? '',
      createdAt: parsedDate,
      size: (json['size'] as num?)?.toInt() ?? 0,
      isImported: (json['isImported'] as bool?) ?? false,
    );
  }
}
