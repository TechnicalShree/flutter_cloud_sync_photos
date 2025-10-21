typedef FolderPathResolver = String Function(String? folderName);

/// Default implementation for turning a user-provided folder name into the
/// sanitized folder segment expected by the backend.
///
/// This mirrors the legacy behaviour from [AuthService.buildFolderPath] while
/// making the logic shareable outside of the auth domain so other features can
/// participate in the same normalization rules without depending on
/// [AuthService].
String defaultFolderPathResolver(String? folderName) {
  final trimmed = folderName?.trim() ?? '';
  if (trimmed.isEmpty) {
    return 'Unsorted';
  }

  final sanitized = trimmed
      .replaceAll('/', '_')
      .replaceAll('\\', '_')
      .trim();

  if (sanitized.isEmpty) {
    return 'Unsorted';
  }

  return sanitized;
}
