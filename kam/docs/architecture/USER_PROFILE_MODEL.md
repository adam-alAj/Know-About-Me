# User profile model

The profile documents, their Dart models, and the read/write semantics —
**as implemented** after Phase 4.

Related documents:

- `AUTHENTICATION_ARCHITECTURE.md` — identity, the state machine, the router guard.
- `FIRESTORE_DATA_MODEL.md` — where these documents sit in the wider schema.
- `FIREBASE_SECURITY.md` — the rules that enforce ownership.
- `../decisions/ADR-008-identity-profile-separation.md` — why identity and profile
  are separate concepts.

---

## 1. Documents

Two documents, because the Security Rules keep the private one private:

```text
users/{uid}                                  the profile (FR-002)
  displayName        string, 1..120          required
  photoUrl           string | absent         optional
  timeZone           string | absent         IANA name, optional
  createdAt          Timestamp (server)      required, immutable
  updatedAt          Timestamp (server)      required, server-set

users/{uid}/settings/preferences             private settings (FR-022, FR-042)
  notificationPreference  string | absent    one of four values
  homeLocation            map | absent       {latitude, longitude, label?, radiusKm}
  updatedAt               Timestamp (server) required, server-set
```

`users/{uid}` holds nothing that a partner may read: partner-visible names are
denormalised into `pairs/{pairId}/members/{uid}` (FIRESTORE_DATA_MODEL §2). Home
coordinates exist **only** here, owner-only, so a partner can never read them
(NFR-005, NFR-036); a partner sees the derived distance/presence written into the
pair's shared state instead.

---

## 2. Dart models

| Model | File | Notes |
| --- | --- | --- |
| `AppUser` | `features/auth/domain/models/app_user.dart` | mirrors `users/{uid}` exactly |
| `UserPreferences` | `features/auth/domain/models/user_preferences.dart` | mirrors the settings document |
| `NotificationPreference` | in `user_preferences.dart` | `allRuleNotifications`, `importantOnly`, `specificRulesOnly`, `noNotifications` |
| `HomeLocation`, `Coordinate` | `features/location/domain/models/location_state.dart` | Phase 1 models, reused unchanged |

Both models are pure Dart — no Firebase, Flutter or Riverpod imports, enforced by
the architecture test.

### `AppUser`

```dart
class AppUser {
  final String id;            // == the Firebase uid; also the document id
  final String displayName;
  final String? photoUrl;
  final String? timeZone;
  final DateTime? createdAt;  // UTC
  final DateTime? updatedAt;  // UTC
}
```

- `id` is not a second identifier: it is the provider's uid (FR-001).
- `copyWith` deliberately exposes **only** `displayName`, `photoUrl`, `timeZone`
  and `updatedAt`. The type cannot express an ownership or creation-time change,
  so a client bug cannot even attempt one (SRS Task 15).
- Timestamps are stored as Firestore `Timestamp`s and converted to UTC `DateTime`s
  on read. Local conversion happens only in the presentation layer (NFR-026).

### `UserPreferences`

A document that does not exist is reported as `UserPreferences.defaults`
(`allRuleNotifications`, no home location): that default is an application-level
decision, not an invented observation. An unrecognised `notificationPreference`
also falls back to the default rather than failing the whole screen.

---

## 3. Field ownership

| Field | Owner | Client write | Partner read | Validation |
| --- | --- | --- | --- | --- |
| `users/{uid}` as a whole | the user | own uid only | **never** | key allow-list |
| `displayName` | the user | yes | via the pair member copy | 1..120, trimmed |
| `photoUrl` | the user | yes (reference only) | via the pair member copy | string |
| `timeZone` | the user | yes | no | string |
| `createdAt` | the server | **no** | no | `== request.time` on create; immutable afterwards |
| `updatedAt` | the server | **no** | no | `== request.time` on every write |
| `notificationPreference` | the user | yes | no | one of four values |
| `homeLocation` | the user | yes | **no** | coordinate ranges checked |

Everything is owner-only: `isSelf(uid)` compares the document path against
`request.auth.uid`, so a client cannot read or write another user's profile, and
cannot create a document under someone else's uid. Verified by emulator tests
(`firebase/test/firestore.rules.test.js`).

---

## 4. Validation, client and server

The client validator and the Rules must agree, or a value can pass the form and be
rejected by the server:

| Rule | Client | Server (`firestore.rules`) |
| --- | --- | --- |
| display name not empty | `AuthInputValidation.displayName` | `size() > 0` |
| display name ≤ 120 characters | `maximumDisplayNameLength` (= `AppUser.maxDisplayNameLength`) | `size() <= 120` |
| no unknown fields | n/a | `keys().hasOnly([...])` |
| server timestamps | `FieldValue.serverTimestamp()` | `== request.time` |
| known notification values | the enum | `in [...]` |
| valid coordinates | n/a | latitude ±90, longitude ±180 |

A unit test asserts the 120-character bound is the same constant on both sides.

---

## 5. Repository contract

```dart
abstract interface class ProfileRepository {
  Future<Result<AppUser?>> getProfile(String uid);          // null = no document
  Stream<Result<AppUser?>> watchProfile(String uid);
  Future<Result<AppUser>> createProfile({required String uid, required String displayName, String? timeZone});
  Future<Result<AppUser>> updateProfile({required String uid, String? displayName, String? photoUrl, String? timeZone});
  Future<Result<UserPreferences>> getPreferences(String uid);
  Future<Result<UserPreferences>> updatePreferences({required String uid,
      NotificationPreference? notificationPreference, HomeLocationOverride homeLocation});
}
```

Semantics that callers rely on:

- `getProfile` returns `Success(null)` when the document does not exist. A
  document that exists but has no usable `displayName` returns a
  `ValidationFailure` instead — reported, never patched with an invented name.
- `createProfile` is **idempotent** and runs in a transaction: an existing document
  is returned untouched. A retry cannot duplicate a profile or discard an edit.
- `updateProfile` uses `update()`, not `set()`, so it fails rather than silently
  creating a document when no profile exists.
- Both write paths re-read the document before returning, because the server
  resolves `serverTimestamp()` and a locally-guessed timestamp would be wrong.
- `HomeLocationOverride` is a three-state parameter (`unchanged` / `set` /
  `cleared`) so "leave it alone" and "remove it" cannot be confused; a nullable
  parameter could not express that, and clearing a home location by accident would
  be data loss.

---

## 6. Read paths and state

```text
currentIdentityProvider ──► uid ──► userProfileProvider(uid) ──► Result<AppUser?>
                                          │
                                          └─► currentUserProfileProvider
                                                 (AsyncValue<Result<AppUser?>>)
```

`userProfileProvider` is a **family keyed by uid**, so a different account reads a
different provider instance and one user's profile can never be served from
another user's cache after a sign-out or an account switch. `signOut()` also
invalidates the profile and preferences families so nothing authenticated is left
in memory.

`PresentationMapping.fromAsyncNullableResult` maps the provider state:

| Provider state | Presentation | Rendered as |
| --- | --- | --- |
| `AsyncLoading` | loading | `LoadingView` |
| `Success(null)` | **empty** | the "finish setting up" form |
| `Success(user)` | loaded | the edit form |
| `Failure(f)` | failure | `ErrorView` with the safe message and retry |

---

## 7. Write paths

```text
ProfileScreen ──► ProfileController ──► ProfileRepository ──► Firestore
```

`ProfileController` decides create vs update:

```dart
final result = _hasProfile
    ? await repository.updateProfile(uid: identity.uid, displayName: trimmed)
    : await repository.createProfile(uid: identity.uid, displayName: trimmed);
```

Guessing wrong is harmless because `createProfile` is idempotent. After a
successful write the controller invalidates the affected providers, so the screen
shows the **stored** values rather than the submitted ones.

Its state is separate from the read state, so a save cannot be mistaken for a load:

| Brief-level state | Where it comes from |
| --- | --- |
| Initial | `ProfileController`: `ProfileIdle` |
| Loading | `currentUserProfileProvider`: `AsyncLoading` |
| Loaded | `currentUserProfileProvider`: `Success(profile)` |
| Updating | `ProfileController`: `ProfileSaving` |
| Updated | `ProfileController`: `ProfileSaved` |
| Error | `ProfileSaveFailed(failure)` or a provider failure |
| Unavailable | a provider failure with a classified reason (for example no backend) |

---

## 8. Deferred

| Field / behaviour | Why it is not here |
| --- | --- |
| Profile image upload | `photoUrl` is a reference only; storage upload needs Cloud Storage and a later phase. |
| Home location UI | The *storage* and validation exist (with coordinate checks); the picker, permissions and distance logic belong to the location phase. |
| Privacy/sharing preferences on the profile | Sharing is per (pair, user) in `pairs/{pairId}/sharing/{uid}`, not a profile field — a profile-level copy would desynchronise. |
| Notification delivery | Only the preference is stored; `FR-041` dispatch belongs to the notifications phase. |
| Profile deletion UI | Allowed by the rules and required by NFR-032; the retention/deletion flow is scheduled with the privacy phases. |
