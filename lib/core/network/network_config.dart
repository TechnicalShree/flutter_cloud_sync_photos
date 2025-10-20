class NetworkConfig {
  // static const String baseUrl = 'https://frappe.technicalshree.in/';
  static const String baseUrl = 'https://backup.technicalshree.in/';
}

enum ApiEndpoint {
  login('api/method/login'),
  verifySession('api/method/backup_app.api.verify_session.verify_session'),
  userDetails('api/method/backup_app.api.user_details.get_user_details'),
  uploadFile('api/method/backup_app.api.files.upload_file_safe'),
  unsyncFile('api/method/backup_app.api.files.unsync_file');

  const ApiEndpoint(this.path);
  final String path;
}
