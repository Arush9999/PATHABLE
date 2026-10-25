import 'package:equatable/equatable.dart';

enum ConfirmationResponse {
  stillPresent,
  resolved,
  unableToDetermine;

  String get label => switch (this) {
        ConfirmationResponse.stillPresent => 'Still present',
        ConfirmationResponse.resolved => 'Looks resolved',
        ConfirmationResponse.unableToDetermine => 'Unable to determine',
      };
}

enum EvidenceType {
  visual,
  traveledThrough,
  other;

  String get label => switch (this) {
        EvidenceType.visual => 'Visual observation',
        EvidenceType.traveledThrough => 'Traveled through area',
        EvidenceType.other => 'Other',
      };
}

class HazardConfirmation extends Equatable {
  const HazardConfirmation({
    required this.id,
    required this.hazardId,
    required this.response,
    required this.createdAt,
    this.userId,
    this.evidenceType,
  });

  final String id;
  final String hazardId;
  final ConfirmationResponse response;
  final DateTime createdAt;
  final String? userId;
  final EvidenceType? evidenceType;

  @override
  List<Object?> get props =>
      [id, hazardId, response, createdAt, userId, evidenceType];
}
