import '../../gallery/data/services/upload_metadata_store.dart';

class SettingsActions {
  SettingsActions({UploadMetadataStore? metadataStore})
    : _metadataStore = metadataStore ?? UploadMetadataStore();

  final UploadMetadataStore _metadataStore;

  Future<void> resetUploadMetadata() => _metadataStore.clearAll();
}

final SettingsActions settingsActions = SettingsActions();
