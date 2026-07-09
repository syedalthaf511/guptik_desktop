# Guptik Desktop

A comprehensive Flutter-based desktop application for home automation, media management, secure communications, and data analytics.

## Project Structure

```
lib/
├── main.dart                    # Application entry point
├── app_config.dart             # Global configuration settings
├── assets/                     # Images and static assets
├── models/                     # Data models for various features
│   ├── auto_comment_post.dart
│   ├── board.dart
│   ├── conversation.dart
│   ├── database_table.dart
│   ├── home.dart
│   ├── message.dart
│   ├── room.dart
│   ├── server_status.dart
│   ├── social_conversation.dart
│   ├── social_message.dart
│   ├── switch.dart
│   ├── trust_session.dart
│   ├── vault_file.dart
│   ├── facebook/               # Facebook-specific models
│   ├── mediaplayer/            # Media player models
│   └── whatsapp/               # WhatsApp models
├── resources/                  # Static resources and documentation
├── screens/                    # UI screens organized by feature
│   ├── auth/                   # Authentication screens
│   │   ├── boot_screen.dart
│   │   ├── login_screen.dart
│   │   └── login_signup_screen.dart
│   ├── dashboard/              # Dashboard components (legacy)
│   │   ├── all_insights_widget.dart
│   │   ├── dashboard_overview.dart
│   │   ├── dashboard_screen.dart
│   │   └── sidebar_widget.dart
│   ├── datatables/             # Database table management
│   ├── facebook/               # Facebook integration
│   ├── guptik/                 # Guptik-specific screens
│   ├── home_control/           # Home automation control (new dashboard location)
│   │   ├── dashboard_home_screen.dart  # Main dashboard screen
│   │   └── home_control_screen.dart    # Home control with tabbed interface
│   ├── mediaplayer/            # Media player functionality
│   ├── onboarding/             # Setup and installation screens
│   ├── settings/               # Application settings
│   ├── trust_me/               # Secure communications
│   ├── vault/                  # Secure file storage
│   └── whatsapp/               # WhatsApp integration
├── services/                   # Business logic and external service integration
│   ├── storage_service.dart
│   ├── supabase_service.dart
│   ├── zalzira.service.dart
│   ├── external/               # External service connectors
│   │   ├── docker_service.dart
│   │   ├── ollama_service.dart
│   │   ├── osint_service.dart
│   │   └── postgres_service.dart
│   ├── facebook/               # Facebook service integration
│   ├── mediaplayer/            # Media player services
│   ├── trustme/                # Secure communication services
│   └── whatsapp/               # WhatsApp services
├── utils/                      # Utility functions and helpers
└── widgets/                    # Reusable UI components
```

## Key Features

### 1. Home Automation Control
- **Location**: `lib/screens/home_control/`
- **Main Screen**: `home_control_screen.dart` - Tabbed interface with Dashboard and Home Control
- **Dashboard**: First tab showing all MJAOI insights and connections
- **Homes Management**: Second tab for managing smart homes, rooms, and devices

### 2. Authentication & Onboarding
- **Auth Flow**: `lib/screens/auth/` - Login/Signup and boot sequence
- **Installation**: `lib/screens/onboarding/` - System setup and configuration
- **Storage Selection**: Choose where to store local data

### 3. Media Management
- **Location**: `lib/screens/mediaplayer/`
- Features include media playback, creator profiles, and file uploads

### 4. Secure Communications
- **TrustMe**: `lib/screens/trust_me/` - Secure messaging platform
- **WhatsApp**: `lib/screens/whatsapp/` - WhatsApp integration

### 5. Data Analytics & Management
- **DataTables**: `lib/screens/datatables/` - Database table management
- **Vault**: `lib/screens/vault/` - Secure file storage

### 6. Facebook Integration
- **Location**: `lib/screens/facebook/` - Meta dashboard and analytics

### 7. Settings & Configuration
- **Location**: `lib/screens/settings/` - Application settings and service management

## Services Architecture

### External Services
- **Docker Service**: `lib/services/external/docker_service.dart` - Container management
- **PostgreSQL Service**: `lib/services/external/postgres_service.dart` - Local database
- **Ollama Service**: `lib/services/external/ollama_service.dart` - AI/ML capabilities
- **OSINT Service**: `lib/services/external/osint_service.dart` - Intelligence gathering

### Platform-Specific Services
- **Facebook**: `lib/services/facebook/`
- **MediaPlayer**: `lib/services/mediaplayer/`
- **TrustMe**: `lib/services/trustme/`
- **WhatsApp**: `lib/services/whatsapp/`

## Installation Instructions

### Prerequisites
- Flutter SDK
- Docker Desktop (for local services)
- Supabase account (configured with provided credentials)

### Linux/macOS:
```bash
bash install.sh
```

### Windows (PowerShell):
```powershell
powershell -ExecutionPolicy Bypass -File install.sh
```

## Development Setup

1. Clone the repository
2. Run `flutter pub get`
3. Ensure Docker is running
4. Start the application with `flutter run -d windows` (or your target platform)

## Important Notes

- The application uses Supabase for cloud authentication and data synchronization
- Local services run in Docker containers managed by the Docker service
- All sensitive data is encrypted using the encryption helper utilities
- The dashboard now resides in the Home Control section as the first tab
- Legacy dashboard files in `lib/screens/dashboard/` are no longer actively used but retained for reference

## Unused/Deprecated Files

- `lib/screens/dashboard/dashboard_screen.dart` - Legacy dashboard screen (replaced by new implementation)
- Some files in `lib/models/facebook/`, `lib/models/mediaplayer/`, and `lib/models/whatsapp/` may be unused depending on current integration status

## Connection Flow

1. **Authentication**: User logs in through `login_signup_screen.dart`
2. **Device Registration**: Device is registered with Supabase
3. **Cloudflare Tunnel**: Secure tunnel is established for remote access
4. **Storage Selection**: User chooses local storage location
5. **Installation**: Docker services are configured and started
6. **Database Initialization**: Local PostgreSQL database is set up
7. **AI Engine Setup**: Ollama service is configured
8. **Main Application**: User enters Home Control dashboard