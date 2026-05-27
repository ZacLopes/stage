class Company {
  final String id;
  final String name;
  final String? logoUrl;
  final String? description;
  /// HTML cru do description da empresa (popular via getOrCreateCompany no
  /// backend). Null pra companies criadas antes da migration ou que ainda
  /// não foram re-sincronizadas. App cai no fallback de [description].
  final String? descriptionHtml;
  final String? website;
  final String? industry;
  final String? size;

  Company({
    required this.id,
    required this.name,
    this.logoUrl,
    this.description,
    this.descriptionHtml,
    this.website,
    this.industry,
    this.size,
  });

  factory Company.fromJson(Map<String, dynamic> json) {
    return Company(
      id: json['id'] as String,
      name: json['name'] as String,
      logoUrl: json['logo_url'] as String?,
      description: json['description'] as String?,
      descriptionHtml: json['description_html'] as String?,
      website: json['website'] as String?,
      industry: json['industry'] as String?,
      size: json['size'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'logo_url': logoUrl,
      'description': description,
      'description_html': descriptionHtml,
      'website': website,
      'industry': industry,
      'size': size,
    };
  }
}
