class VoiceModel {
  final String voiceId;
  final String name;
  final String? previewUrl;
  final String category;
  final String description;
  final String language;

  VoiceModel({
    required this.voiceId,
    required this.name,
    this.previewUrl,
    this.category = 'Standard',
    this.description = '',
    this.language = 'english',
  });

  factory VoiceModel.fromJson(Map<String, dynamic> json) {
    return VoiceModel(
      voiceId: json['voice_id'] ?? json['voiceId'] ?? json['id'] ?? 'default',
      name: json['name'] ?? 'Default Voice',
      previewUrl: json['preview_url'] ?? json['previewUrl'],
      category: json['category'] ?? 'Standard',
      description: json['description'] ?? '',
      language: json['language'] ?? 'english',
    );
  }

  static List<VoiceModel> defaultVoices() {
    return [
      VoiceModel(
        voiceId: 'default',
        name: 'Default Natural Voice (Edge TTS)',
        category: 'Standard',
        description: 'Fast, clear neural speech synthesis',
      ),
      VoiceModel(
        voiceId: 'CwhRBWXzGAHq8TQ4Fs17',
        name: 'Roger (Laid-back & Natural)',
        category: 'Neural AI',
        description: 'Deep Indian male accent',
      ),
      VoiceModel(
        voiceId: 'EXAVITQu4vr4xnSDxMaL',
        name: 'Sarah (Confident & Professional)',
        category: 'Neural AI',
        description: 'Clear Indian female accent',
      ),
      VoiceModel(
        voiceId: 'FGY2WhTYpPnrIDTdsKH5',
        name: 'Laura (Upbeat & Energetic)',
        category: 'Neural AI',
        description: 'Expressive female voice',
      ),
      VoiceModel(
        voiceId: 'IKne3meq5aSn9XLyUdCD',
        name: 'Charlie (Energetic & Clear)',
        category: 'Neural AI',
        description: 'Dynamic male voice',
      ),
      VoiceModel(
        voiceId: 'JBFqnCBsd6RMkjVDRZzb',
        name: 'George (Storyteller & Rich)',
        category: 'Neural AI',
        description: 'Narrator male tone',
      ),
      VoiceModel(
        voiceId: 'N2lVS1w4EtoT3dr4eOWO',
        name: 'Callum (Deep & Resonant)',
        category: 'Neural AI',
        description: 'Deep male tone',
      ),
      VoiceModel(
        voiceId: 'SAz9YHcvj6GT2YYXdXww',
        name: 'River (Relaxed & Smooth)',
        category: 'Neural AI',
        description: 'Neutral relaxed accent',
      ),
      VoiceModel(
        voiceId: 'SOYHLrjzK2X1ezoPC6cr',
        name: 'Harry (Resonant & Calm)',
        category: 'Neural AI',
        description: 'Calm male voice',
      ),
      VoiceModel(
        voiceId: 'TX3LPaxmHKxFdv7VOQHJ',
        name: 'Liam (Casual & Friendly)',
        category: 'Neural AI',
        description: 'Friendly male tone',
      ),
      VoiceModel(
        voiceId: 'Xb7hH8MSUJpSbSDYk0k2',
        name: 'Alice (Clear Educator)',
        category: 'Neural AI',
        description: 'Educational female voice',
      ),
      VoiceModel(
        voiceId: 'XrExE9yKIg1WjnnlVkGX',
        name: 'Matilda (Expressive & Warm)',
        category: 'Neural AI',
        description: 'Warm female narrator',
      ),
      VoiceModel(
        voiceId: 'bIHbv24MWmeRgasZH58o',
        name: 'Will (Smooth & Professional)',
        category: 'Neural AI',
        description: 'Professional male accent',
      ),
      VoiceModel(
        voiceId: 'cgSgspJ2msm6clMCkdW9',
        name: 'Jessica (Bright & Conversational)',
        category: 'Neural AI',
        description: 'Bright female voice',
      ),
      VoiceModel(
        voiceId: 'cjVigY5qzO86Huf0OWal',
        name: 'Eric (Formal & Authoritative)',
        category: 'Neural AI',
        description: 'Formal male voice',
      ),
      VoiceModel(
        voiceId: 'hpp4J3VqNfWAUOO0d1Us',
        name: 'Bella (Soft & Professional)',
        category: 'Neural AI',
        description: 'Soft female tone',
      ),
      VoiceModel(
        voiceId: 'iP95p4xoKVk53GoZ742B',
        name: 'Chris (Conversational & Friendly)',
        category: 'Neural AI',
        description: 'Conversational male tone',
      ),
      VoiceModel(
        voiceId: 'nPczCjzI2devNBz1zQrb',
        name: 'Brian (Deep Authority)',
        category: 'Neural AI',
        description: 'Deep authoritative male',
      ),
      VoiceModel(
        voiceId: 'onwK4e9ZLuTAKqWW03F9',
        name: 'Daniel (Broadcaster Style)',
        category: 'Neural AI',
        description: 'News broadcaster style',
      ),
      VoiceModel(
        voiceId: 'pFZP5JQG7iQjIQuC4Bku',
        name: 'Lily (Warm & Empathetic)',
        category: 'Neural AI',
        description: 'Empathetic female voice',
      ),
      VoiceModel(
        voiceId: 'pNInz6obpgDQGcFmaJgB',
        name: 'Adam (Direct & Clear)',
        category: 'Neural AI',
        description: 'Direct male accent',
      ),
      VoiceModel(
        voiceId: 'pqHfZKP75CvOlQylNhV4',
        name: 'Bill (Wise & Experienced)',
        category: 'Neural AI',
        description: 'Wise male voice',
      ),
    ];
  }
}
