# 🚑 Emergency108 – Flutter Mobile App

> A real-time emergency response mobile app for citizens and ambulance drivers — built with Flutter, Google Maps, WebSockets (STOMP), Firebase Cloud Messaging, and Riverpod.

![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-3.10+-0175C2?logo=dart&logoColor=white)
![Firebase](https://img.shields.io/badge/Firebase-FCM-FFCA28?logo=firebase&logoColor=black)
![Google Maps](https://img.shields.io/badge/Google%20Maps-API-4285F4?logo=googlemaps&logoColor=white)
![WebSocket](https://img.shields.io/badge/WebSocket-STOMP-blueviolet?logo=socketdotio)
![Riverpod](https://img.shields.io/badge/State-Riverpod-00B4D8?logo=dart&logoColor=white)
![Backend](https://img.shields.io/badge/Backend-Spring%20Boot-brightgreen?logo=springboot)
![Admin Panel](https://img.shields.io/badge/Admin%20Panel-React-61DAFB?logo=react&logoColor=black)
![CI/CD](https://img.shields.io/badge/CI%2FCD-GitHub%20Actions-2088FF?logo=githubactions&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green)
![Status](https://img.shields.io/badge/Status-Stable-success)

---

## 🌟 Overview

**Emergency108** is a full-stack emergency dispatch platform. The Flutter mobile app serves **two roles**:

- 👤 **Citizens (PUBLIC role)** — Trigger emergencies in seconds, track the assigned ambulance live on a map, get first-aid guidance from an AI doctor, and share emergency contacts. Nearby citizens are also notified to lend a helping hand.
- 🚑 **Drivers (DRIVER role)** — Receive push notification assignments, accept or reject dispatches, stream live GPS location back to the backend and admin panel, and manage their shift.

The app connects to the [Emergency108 Spring Boot backend](https://github.com/anupamkushwaha85/emergency-dispatch-system) over **REST APIs** (JWT-authenticated) and **WebSockets (STOMP)** for zero-latency live updates.

### 🔗 Related Repositories & Links

| Component | Link |
|---|---|
| 🖥️ Backend (Spring Boot) | [emergency-dispatch-system](https://github.com/anupamkushwaha85/emergency-dispatch-system) |
| 📊 Admin Panel (React) | [emergency-dispatch-admin-panel](https://github.com/anupamkushwaha85/emergency-dispatch-admin-panel) |
| 🌐 Admin Panel Live Demo | [emergency-dispatch-admin-panel.vercel.app](https://emergency-dispatch-admin-panel.vercel.app/) |

---

## ✨ Key Features

### 🆘 3-Second SOS Emergency Trigger
- Press and **hold the SOS button for 3 seconds** to trigger an emergency — prevents accidental triggers
- An animated circular progress arc fills as you hold, giving clear visual feedback
- On release, the emergency is instantly reported to the backend with your GPS coordinates

### ⏱️ 100-Second Auto-Dispatch Countdown
- After SOS is triggered, a **100-second countdown** begins
- The system automatically dispatches the nearest available ambulance when the timer hits zero
- A **"Skip Wait: Dispatch Now"** button lets you dispatch immediately without waiting — useful when the situation is critical
- The countdown is optimized with `ValueNotifier` so only the timer widget rebuilds — not the entire screen

### 🗺️ Live Ambulance Tracking (Google Maps)
- Once dispatched, a **live Google Maps view** appears showing:
  - Your GPS location (patient marker)
  - The ambulance's real-time location (updates via WebSocket)
  - A **polyline route** drawn from the ambulance to you using the Maps Routes API
- Debounced map updates prevent redundant API calls on every GPS tick
- Concurrent update protection ensures map state stays consistent

### 📡 Real-Time WebSocket Communication (STOMP)
- App subscribes to a **STOMP WebSocket channel** to receive live ambulance GPS updates
- Driver location pings from the backend are immediately rendered on the map
- SockJS fallback for environments where raw WebSocket is blocked

### 🔔 Firebase Cloud Messaging (FCM) Push Notifications
- FCM token is registered with the backend on login
- **Citizens** receive push notifications on:
  - Emergency status changes (`DISPATCHED`, `COMPLETED`, `CANCELLED`)
  - Helping Hand alerts when nearby emergencies occur
- **Drivers** receive push notifications on:
  - New assignment dispatch
  - Assignment cancellations and reassignments
- Foreground notifications show as in-app `SnackBar` with a `VIEW` action

### 🤝 Helping Hand — Community First Response
- When an emergency is created **for SELF**, **nearby PUBLIC users within 3 km** are instantly notified via FCM — "🚨 Emergency Nearby!"
- If the emergency is created **for someone else** (bystander calling for a stranger), the Helping Hand notification is **skipped entirely** — respecting victim privacy
- Helpers see approximate location, distance, and emergency type — no personal details of the victim are exposed
- They can choose to rush to the scene and provide immediate first aid before the ambulance arrives
- Helpers can view all nearby active emergencies via a live feed in the app

### 🗺️ Live Turn-by-Turn Directions with Exact Distance
- During active tracking, the Google Maps view shows a **live polyline route** from the ambulance's real-time location to the patient
- The **exact road distance** (km/m) and **estimated time of arrival (ETA)** are displayed and updated continuously as the ambulance moves
- Route is recalculated intelligently using debouncing — only requests a new route when the ambulance has moved enough to warrant an update, preventing excessive Maps API calls
- Patient and ambulance markers update smoothly on every GPS ping from the driver

### 📞 Driver Can Call the Patient
- After accepting an emergency, the driver sees the patient's phone number and can **call them directly with one tap** from inside the app
- Useful for coordinating exact pickup location, floor number, gate access, etc.
- Uses `url_launcher` to open the native phone dialer — no in-app calling infra needed

### 🌍 Open in Google Maps / Native Navigation
- Both the **driver and the patient** can tap a button to open the emergency location in the **native Google Maps app** for full turn-by-turn navigation
- Driver can use Google Maps navigation to drive to the patient, then to the hospital
- Patient can share or view their own pinned location in Google Maps as confirmation

### 🚫 Accept is Final — No Rejection After Accepting
- Once a driver taps **Accept** on an emergency assignment, the action is **irreversible**
- The driver cannot reject the emergency after accepting — this prevents drivers from abandoning mid-route
- The only way to end the assignment is to complete the mission by marking the patient picked up and delivering them to the hospital

### 🔄 Auto-Reassignment to Next Nearest Driver
- If a driver **rejects** the assignment or **does not respond within the timeout window**, the emergency is automatically reassigned to the **next nearest available driver**
- The `AssignmentTimeoutScheduler` runs in the background and triggers reassignment without any manual intervention
- This cascades through drivers by distance until one accepts — ensuring no emergency goes unattended
- Drivers who time out or reject too often can be flagged by the system

### 🏥 Nearest Hospital Automatically Assigned
- When an ambulance is dispatched, the backend uses the **Haversine formula** to find and assign the **nearest hospital** to the emergency location
- The hospital is selected from the registered hospital database using a native MySQL geospatial query
- The assigned hospital is shown to both the driver and the admin panel
- The driver's mission is only marked complete when they arrive at the assigned hospital (within 100 m proximity check)

### 🤖 AI Doctor — First Aid Guidance
- Built-in **AI First Aid screen** accessible during an active emergency
- Provides step-by-step first aid instructions to help citizens assist the patient while waiting for the ambulance

### 🔒 OTP-Based Authentication
- Phone number → **6-digit OTP** → JWT issued by the backend
- SMS Autofill support — OTP is automatically detected and filled in
- JWT is stored locally and attached to all API requests
- Role-based routing: `PUBLIC` users see the citizen home screen, `DRIVER` users see the driver dashboard

### 🚑 Driver Mode
- Dedicated driver home screen with shift-on/off toggle
- Incoming emergency assignments with **Accept / Reject** actions
- Real-time GPS streaming from driver device to backend over WebSocket
- Assignment history and status tracking

### 📇 Emergency Contacts
- Import contacts from the phone to set up emergency contacts
- Contacts are auto-called when an emergency is triggered (after arrival)

### ⚙️ Profile & Settings
- Profile completion flow on first login
- Settings screen for preferences and notifications
- Image picker for profile/document photo upload

---

## 🏗️ Architecture

Feature-first clean architecture — each feature is fully self-contained.

```
lib/
├── core/
│   ├── config/         # App config, base URLs, API keys (env-injected)
│   ├── network/        # Dio HTTP client, interceptors
│   ├── routing/        # GoRouter navigation
│   ├── services/       # FCM notification service
│   └── theme/          # App theme, colors, typography
│
└── features/
    ├── auth/           # Login, OTP, JWT storage
    ├── home/           # Citizen home: SOS button, countdown, tracking, map
    ├── driver/         # Driver home: assignment accept/reject, GPS streaming
    ├── emergency/      # Emergency repository, ownership modal
    ├── helping_hand/   # Community first-response feature
    ├── ai_doctor/      # AI first aid guidance screen
    ├── location/       # Maps repository, route polyline
    ├── profile/        # Profile management, document upload
    ├── settings/       # Preferences, notifications
    ├── onboarding/     # First-launch onboarding flow
    └── splash/         # Splash screen, auth gate
```

---

## 🛠️ Tech Stack

| Category | Technology |
|---|---|
| Framework | Flutter 3.x |
| Language | Dart 3.10+ |
| State Management | Riverpod 2.x + Riverpod Generator |
| Navigation | GoRouter 14.x |
| HTTP Client | Dio 5.x |
| WebSockets | STOMP Dart Client + web_socket_channel |
| Maps | Google Maps Flutter 2.7 |
| Location | Geolocator 13.x |
| Push Notifications | Firebase Messaging (FCM) + Flutter Local Notifications |
| Fonts & Animations | Google Fonts, Flutter Animate, Lottie |
| OTP | SMS Autofill |
| Contacts | Flutter Contacts |
| Storage | Shared Preferences |
| Image | Image Picker |
| CI/CD | GitHub Actions (auto APK build + release) |

---

## 🚀 Getting Started

### Prerequisites
- Flutter SDK `^3.10.7`
- Android Studio or VS Code with Flutter extension
- A Firebase project (for FCM)
- Google Maps API key

### 1. Clone the repo
```bash
git clone https://github.com/anupamkushwaha85/emergency108.git
cd emergency108
```

### 2. Set up secrets

Create `android/local.properties`:
```properties
sdk.dir=YOUR_ANDROID_SDK_PATH
GOOGLE_MAPS_API_KEY=YOUR_KEY_HERE
```

Place your Firebase `google-services.json` at:
```
android/app/google-services.json
```

### 3. Install dependencies
```bash
flutter pub get
```

### 4. Run
```bash
flutter run
```

### 5. Build release APK
```bash
flutter build apk --release
```

The APK will be at `build/app/outputs/flutter-apk/app-release.apk`.

---

## 📦 Automated APK Releases (GitHub Actions)

Every push to `main` automatically:
1. Sets up Flutter and Java on GitHub's servers
2. Injects secrets from GitHub Secrets (`GOOGLE_SERVICES_JSON`, `GOOGLE_MAPS_API_KEY`)
3. Builds the release APK
4. Publishes it to the [Releases tab](https://github.com/anupamkushwaha85/emergency108/releases)

Users can always download the latest APK directly from Releases without needing to build locally.

---

## 🔐 Security

- All API keys are injected at build time via environment variables — **never hardcoded**
- `google-services.json` and `local.properties` are gitignored
- JWT is issued by the backend after OTP verification
- All API communication is over HTTPS

---

## 🌐 System Architecture

```
┌─────────────────────┐      REST + WebSocket (STOMP)      ┌──────────────────────────┐
│  Flutter Mobile App │ ─────────────────────────────────► │  Spring Boot Backend      │
│  (Citizen + Driver) │ ◄───────────────────────────────── │  MySQL · FCM · JWT · Maps │
└─────────────────────┘                                     └──────────┬───────────────┘
                                                                       │ WebSocket
                                                                       ▼
                                                            ┌──────────────────────────┐
                                                            │  React Admin Panel        │
                                                            │  (Vercel — live demo)     │
                                                            └──────────────────────────┘
```

---

## 📄 License

MIT — see [LICENSE](LICENSE) for details.
