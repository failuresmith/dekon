enum ProjectionApplyStatus { applied, duplicate, unsupported }

class ProjectionApplyResult {
  const ProjectionApplyResult(this.status, this.eventId);

  final ProjectionApplyStatus status;
  final String eventId;
}

class ProjectionException implements Exception {
  ProjectionException(this.message);

  final String message;

  @override
  String toString() => 'ProjectionException: $message';
}
