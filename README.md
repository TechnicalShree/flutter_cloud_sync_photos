# Cloud Sync Photos (Flutter)

Cloud Sync Photos is a Flutter app for securely syncing local gallery photos to a cloud backend, browsing synced media, and managing albums and settings. It supports login, offline session handling, uploads with metadata, and a Material 3 UI with dynamic color theming.

## Features
- Authentication:
  - Login via username/password using a cookie-based session.
  - Session persistence across app restarts via secure storage.
  - Session verification on startup and graceful offline handling.
  - Logout clears cookies and user details.
- Gallery & Uploads:
  - Read local media and display grid gallery and detail views.
  - Upload photos (multipart) with options: private/public, target folder, optimize.
  - Maintain upload queue and metadata (content hash, status) locally.
  - Unsync (request server-side removal by content hash).
  - Thumbnail caching to disk for fast scrolling.
- Albums:
  - Albums overview and detail pages, empty states.
- Synced:
  - View synced photos page.
- Settings:
  - Upload preferences and general app settings.
- UI/Navigation:
  - Material 3 theming with dynamic color (Android 12+).
  - Shared axis page transitions and thoughtful empty/loading states.

## Project Structure
- `lib/app.dart`: App root, theming, routes, and `AuthGate`.
- `lib/main.dart`: Entry point.
- `lib/core/*`:
  - `constants/app_strings.dart`: App title and strings.
  - `theme/app_theme.dart`: Light/dark Material 3 themes with dynamic color.
  - `navigation/shared_axis_page_route.dart`: Shared axis transitions.
  - `network/`:
    - `api_client.dart`: Typed API client with endpoints and cookie support.
    - `api_config.dart`, `network_config.dart`: Base URLs and endpoints.
    - `network_service.dart`: Connectivity checks.
    - `api_exception.dart`: Unified error type.
- `lib/features/auth/`:
  - `presentation/pages/login_page.dart`, `widgets/login_view.dart`: Login UI.
  - `presentation/widgets/auth_gate.dart`: Resolves initial auth and routes to login/home.
  - `data/services/auth_service.dart`: Core auth/session, uploads, unsync, user details.
  - `data/services/session_manager.dart`: Persists cookies and user details.
  - `domain/models/user_details.dart`: User model.
  - `data/models/photo_media.dart`: Local media model for uploads and folder naming.
- `lib/features/gallery/`: Gallery pages, grid/slivers, permission prompts, thumbnails, upload queue and metadata store.
- `lib/features/albums/`: Albums overview and details.
- `lib/features/synced/`: Synced photos page.
- `lib/features/home/`: Main home page after login.
- `lib/features/settings/`: Settings page, upload preferences store/actions.

## Key Flows
- Login (`AuthService.login`):
  - Sends `POST` to `ApiEndpoint.login` with form fields `usr` and `pwd`.
  - Extracts `Set-Cookie` header(s), stores and sets as default on the API client.
  - Fetches and persists user details; emits `AuthStatus.authenticated`.
- Initial auth resolution (`AuthService.resolveInitialAuth`):
  - If offline: load stored cookies and user details and set status to `offline` or `unauthenticated`.
  - If online: `verifySession` against `ApiEndpoint.verifySession`; loads or fetches user details.
- Verify session (`AuthService.verifySession`):
  - Ensures cookies are loaded and attempts a `GET`; on failure logs out and returns false.
- Upload file (`AuthService.uploadFile`):
  - Sends multipart with fields `is_private`, `folder`, `optimize`.
- Unsync file (`AuthService.unsyncFile`):
  - Sends `POST` with `content_hash` to request server removal.

## Requirements
- Flutter 3.24+ and Dart SDK compatible with the project `pubspec.yaml`.
- Android/iOS toolchains as per Flutter docs.
- Backend server that implements the API endpoints defined under `core/network`.

## Setup
1. Install Flutter dependencies:
   - `flutter pub get`
2. Configure API base URL and endpoints:
   - Update `lib/core/network/api_config.dart` and `lib/core/network/network_config.dart` as needed for your backend.
3. (Optional) Configure dynamic color support on Android 12+; older devices fall back to theme colors.
4. Run the app:
   - Android: `flutter run -d android`
   - iOS: `flutter run -d ios`

## Usage
- Launch the app. `AuthGate` checks network and session:
  - If no session: navigates to Login.
  - If cookies exist but offline: app enters limited offline state.
  - If session valid: navigates to Home.
- Sign in with your credentials. On success you’re routed to Home.
- Browse local gallery, select photos to upload; uploads use your chosen preferences.
- Use Settings to adjust upload behavior and other preferences.

## Error Handling
- Network and API failures are surfaced via `ApiException` with status codes.
- Login view presents friendly error messages and retry guidance.
- On invalid/expired session, the app clears state and returns to Login.

## Security & Privacy
- Session cookies are stored and reapplied only for the app’s API client.
- Upload parameters allow private uploads; ensure your backend enforces access control.

## Development Notes
- Code follows a feature-first structure (`features/<domain>/...`).
- Keep API shapes consistent with `api_client.dart` parsers and `ApiException` usage.
- Thumbnail and upload metadata caches live under gallery data services; prefer their APIs over direct disk access.

## License
This project is for learning and experimentation. Add your preferred license if distributing.
