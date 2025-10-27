import '../../gallery/data/services/upload_metadata_store.dart';

class SettingsActions {
  SettingsActions({UploadMetadataStore? metadataStore})
    : _metadataStore = metadataStore ?? UploadMetadataStore();

  final UploadMetadataStore _metadataStore;

  Future<void> resetUploadMetadata() => _metadataStore.clearAll();

  Future<Map<String, String>> loadSyncedPhotos() => _metadataStore.loadAll();
}

final SettingsActions settingsActions = SettingsActions();
