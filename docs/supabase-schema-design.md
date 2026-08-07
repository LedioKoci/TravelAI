# Supabase Database Schema Design

Status: **proposal — not yet implemented**
Scope: introduce Supabase as the cloud database/auth provider for user accounts and cloud-synced saved travels, replacing (or complementing) the current on-device `shared_preferences` storage in `frontend/lib/services/travel_storage_service.dart`.

---

## 1. Goals

* Give each user a real account so saved travels follow them across devices instead of living only in local storage.
* Keep the existing `SavedTravel` JSON shape (`id`, `destinationCity`, `departureCity`, `startDate`, `endDate`, `savedAt`, `travelPlan`) as the source of truth for the migration — the client model shouldn't need to change much.
* Use Supabase's built-in `auth.users` table rather than hand-rolling authentication.
* Keep row-level security (RLS) on from day one — users must only ever see their own rows.
* Short-lived access tokens with a rotating, hashed refresh token, so a leaked access token has a tight blast radius.
* Leave room to grow: preferences, trip collaboration, richer analytics — without a v1 schema that has to be torn up.

## 2. Non-goals (for this pass)

* No real-time collaboration / trip-sharing between users yet (noted as a future extension in §7).
* No migration script for existing local-only saved travels yet (comes after schema is approved).
* No social login (Google/Apple) at launch — noted as a follow-up, not built now.

---

## 3. Auth model

Supabase ships an `auth.users` table for free (email, password hash, OAuth identities, `id uuid`). We piggyback on it for *identity* (who the user is, their password) instead of inventing our own `users` table — but session tokens are minted and controlled by our own Node/Express backend, not Supabase's session tokens directly, so we can enforce the 15-minute/rotating-refresh policy below precisely. See §4.

* `auth.users.id` (uuid) is the canonical user id, used as the foreign key everywhere below.
* A `public.profiles` table extends it with app-specific fields Supabase Auth doesn't hold, created automatically via a trigger on `auth.users` insert.

```
auth.users (managed by Supabase)
 ├─ id            uuid PK
 ├─ email         text
 ├─ created_at    timestamptz
 └─ ...auth internals
```

### `public.profiles`

| column          | type          | notes                                              |
|-----------------|---------------|-----------------------------------------------------|
| id              | uuid PK, FK → auth.users(id) on delete cascade | 1:1 with the auth user |
| display_name    | text          | nullable; falls back to email in the UI            |
| home_city       | text          | nullable; feeds the "Departing from home?" toggle — see §3.1 for how it's kept out of the LLM parsing step |
| created_at      | timestamptz   | default `now()`                                     |
| updated_at      | timestamptz   | default `now()`, bumped by trigger on update         |

Trigger: `handle_new_user()` on `auth.users` AFTER INSERT → inserts a matching `profiles` row so the app never has to remember to create one.

`preferred_currency` was considered and deliberately cut: the app doesn't handle checkout/payment, only planning/display, so "converting prices" would mean standing up a live FX-rate dependency and reconciling it against two integrations (Duffel, Nuitee) that already return prices in their own currencies — a lot of surface area for a cosmetic preference nobody's asked for. Revisit only if real conversion becomes a scoped feature, not a footnote column.

### 3.1 `home_city` and the "Departing from home?" toggle — avoiding LLM ambiguity

Planned UX: a toggle under the search bar ("Departing from home?") that, when on, should default the trip's origin to `profiles.home_city` without the user having to type it.

The risk: if `home_city` were injected into the free-text prompt sent to Gemini (e.g. prepending "departing from Milan..."), it collides with whatever the user actually typed. If their text also names an origin ("...from Bergamo..."), the model now has two conflicting signals to arbitrate — exactly the kind of ambiguity that produces inconsistent parses. And if it were injected on every query regardless, it's spending prompt tokens/latency reconstructing something already known deterministically.

Resolution: **keep `home_city` out of the LLM prompt entirely; apply it as a deterministic post-processing fallback, not an LLM input.**

1. Client sends the raw query text plus a separate `departingFromHome: boolean` flag — never merged into the text itself.
2. Gemini parses the query exactly as it does today. This requires `origin` to be an **optional** field in the extraction schema/prompt (worth verifying against the current prompt — if it's currently required, the model may already be hallucinating a plausible origin rather than admitting "unspecified" when the user omits one).
3. In backend code — *not* the LLM — after parsing: if `origin` came back null/empty **and** `departingFromHome` is `true`, fill it in from `profiles.home_city`. If the user's text already gave an explicit origin, their text wins outright; the toggle only fills a gap, it never overrides an explicit value.

This keeps the LLM doing only what it's good at — extracting what's actually stated in the text — and makes the toggle a plain, deterministic, unit-testable fallback, consistent with the pure-function testing style already used in `backend/tests/helpers.test.js`.

---

## 4. Token & session design

### 4.1 Token types

| token | format | lifetime | where stored |
|-------|--------|----------|---------------|
| **Access token** | JWT, signed by the backend (`JWT_SECRET`), payload `{ sub: user_id, iat, exp }` | **15 minutes** | Client memory/secure storage only; never persisted server-side (stateless, verified by signature + `exp`) |
| **Refresh token** | Opaque random value (e.g. 256-bit, `crypto.randomBytes(32).toString('base64url')`) | Longer-lived (proposed 30 days, sliding) | Client secure storage (`flutter_secure_storage`); server stores only its **SHA-256 hash**, never the raw value |

The backend — not Supabase Auth's own session tokens — is the source of truth for sessions, since the 15-minute expiry and rotation-on-refresh policy are custom requirements. Supabase's `auth.users` is used purely to verify email/password at login time (`supabase.auth.signInWithPassword`); once that succeeds, the Node backend mints its own access/refresh pair.

### 4.2 `public.refresh_tokens`

| column        | type        | notes |
|---------------|-------------|-------|
| id            | uuid PK, default `gen_random_uuid()` | |
| user_id       | uuid, FK → auth.users(id) on delete cascade, not null | |
| token_hash    | text, not null, unique | SHA-256 hex digest of the raw refresh token — the raw value is never stored |
| issued_at     | timestamptz, default `now()` | |
| expires_at    | timestamptz, not null | `issued_at + 30 days` at creation time |
| revoked_at    | timestamptz, nullable | set when the token is rotated away, logged out, or invalidated for reuse (see §4.4) |
| replaced_by   | uuid, FK → refresh_tokens(id), nullable | points to the token that replaced this one on rotation, forming an auditable chain |
| user_agent    | text, nullable | optional, for a future "active sessions" / "log out other devices" UI |

Indexes:
* `idx_refresh_tokens_token_hash` unique on `(token_hash)` — the refresh endpoint's lookup is always by hash.
* `idx_refresh_tokens_user_id` on `(user_id)` — powers a future "active sessions" list and bulk-revoke on password change/logout-everywhere.

RLS: enabled, but this table is only ever touched by the backend via the service-role key (never queried by the client), same trust model as `saved_travels` — see §6.

### 4.3 Flow

**Login** (`POST /api/auth/login`):
1. Verify email/password against `auth.users` via `supabase.auth.signInWithPassword`.
2. Mint access token (JWT, `exp` = now + 15m).
3. Generate raw refresh token, store `sha256(rawToken)` in `refresh_tokens` with `expires_at` = now + 30d.
4. Return `{ accessToken, refreshToken }` to the client; client persists both in secure storage.

**Authenticated request** (e.g. `GET /api/travels`):
1. Client sends `Authorization: Bearer <accessToken>`.
2. Backend verifies JWT signature + `exp`. If expired or invalid → **`401 Unauthorized`**.
3. Client's HTTP layer intercepts the 401 transparently (showing a loading state, never surfacing an error to the user for this specific case), and calls the refresh endpoint before retrying the original request.

**Refresh** (`POST /api/auth/refresh`):
1. Client sends the current refresh token in the body.
2. Backend computes `sha256(refreshToken)` and looks it up in `refresh_tokens`.
3. If not found, expired, or already `revoked_at` → reject with `401`, forcing a full re-login (see reuse detection in §4.4).
4. If valid: mint a **new** access token *and* a **new** refresh token (rotation), insert the new refresh token row, set the old row's `revoked_at = now()` and `replaced_by = <new row id>`.
5. Return the new `{ accessToken, refreshToken }` pair; client overwrites both in secure storage. The old refresh token is now dead — it cannot be used again.

**Logout**: revoke the current refresh token row (`revoked_at = now()`) so it can't be replayed, and let the (already short-lived) access token simply expire client-side.

### 4.4 Rotation & reuse detection

Rotating the refresh token on every use (as requested) has a valuable side effect: it lets us detect token theft. If a refresh token is ever presented that is **already `revoked_at`** (i.e. someone is replaying a token that was already exchanged), that's a strong signal the token was stolen and used by both the legitimate client and an attacker. In that case the backend should revoke **every** refresh token for that `user_id` (walk `replaced_by` or just bulk-revoke by `user_id`), forcing a full re-login everywhere. This is a standard refresh-token-rotation-with-reuse-detection pattern and costs nothing extra in the schema (`replaced_by` already gives us the chain).

### 4.5 Why 401 (not 404) as the expiry signal

Per your note, the client will treat a specific status from the backend as "access token expired, refresh silently." **401 Unauthorized** is used for this rather than 404, since 404 conventionally means "resource not found" — reusing it for auth would make a real 404 (e.g. a deleted saved travel) indistinguishable from an expired token, and could cause the client to loop into an unnecessary refresh. 401 is unambiguous and lets the client's HTTP interceptor apply the same "expired token" handling to *any* endpoint without endpoint-specific logic.

---

## 5. Core domain tables

### `public.saved_travels`

Direct cloud counterpart of the local `SavedTravel` model.

| column            | type         | notes |
|-------------------|--------------|-------|
| id                | uuid PK, default `gen_random_uuid()` | replaces the client's `millisecondsSinceEpoch` id scheme |
| user_id           | uuid, FK → auth.users(id) on delete cascade, not null | owner of the trip |
| destination_city  | text, not null | denormalized from `travelPlan.planSummary` for fast list rendering (mirrors sidebar use case) |
| departure_city    | text | nullable, same reasoning |
| start_date        | date | nullable — trips can be "flexible" |
| end_date          | date | nullable |
| travel_plan       | jsonb, not null | the full generated plan blob (flights, hotel, weather, news, visa) — schemaless by design since it comes straight from the Gemini/Duffel/Nuitee pipeline |
| saved_at          | timestamptz, default `now()` | when the user tapped "save" |
| created_at        | timestamptz, default `now()` |
| updated_at        | timestamptz, default `now()` |

Indexes:
* `idx_saved_travels_user_id` on `(user_id)` — every list query filters by owner.
* `idx_saved_travels_user_saved_at` on `(user_id, saved_at desc)` — matches the existing client-side sort (`b.savedAt.compareTo(a.savedAt)`).
* Optional: GIN index on `travel_plan` if we ever need to query inside the blob (e.g. "trips that used airline X"); skip until there's a real query need.

RLS policies (RLS enabled on the table; kept on as defense-in-depth even though the trusted Node backend, using the service-role key, is the only caller — see §6):
* `select`: `auth.uid() = user_id`
* `insert`: `auth.uid() = user_id`
* `update`: `auth.uid() = user_id`
* `delete`: `auth.uid() = user_id`

### `public.search_history` *(optional, phase 2)*

Not required for MVP, but the natural next table once saved travels work — lets us log every generated plan (not just saved ones) for analytics / "recent searches" UX.

| column          | type        | notes |
|-----------------|-------------|-------|
| id              | uuid PK     |
| user_id         | uuid, FK → auth.users(id), nullable | nullable so anonymous/pre-login searches can still be logged if desired |
| raw_query       | text        | the free-text input the user typed |
| parsed_request  | jsonb       | Gemini's structured extraction (origin, destination, dates, travelers) |
| created_at      | timestamptz, default `now()` |

---

## 6. Entity-relationship summary

```
auth.users (1) ──────── (1) public.profiles
     │
     ├─────────────── (many) public.refresh_tokens
     │
     │ (1)
     ▼ (many)
public.saved_travels
     │
     │ (1)            [phase 2]
     ▼ (many)
public.search_history
```

* One user → one profile (1:1).
* One user → many saved travels (1:N).
* One user → many refresh tokens (1:N) — one per active device/session; rotation keeps at most one *valid* row per session lineage.
* `saved_travels.travel_plan` stays `jsonb` rather than being fully normalized (separate `flights`, `hotels`, `weather` tables) because:
  * The plan is a point-in-time snapshot from third-party APIs (Duffel/Nuitee prices change constantly) — normalizing would imply it's "live" data, which it isn't.
  * The existing frontend already treats it as an opaque `Map<String, dynamic>` end to end; normalizing would require a parallel serialization layer for no functional gain right now.
  * `destination_city` / `departure_city` / dates are pulled out as real columns specifically so common queries (list, sort, filter by city/date) don't need to reach into JSON.

---

## 7. Future extensions (not built now, just reserving space)

* **Trip sharing / collaborators**: a `saved_travel_collaborators` join table (`saved_travel_id`, `user_id`, `role`) if trips become shareable.
* **Multi-currency display preference**: if this becomes a real feature, add `profiles.preferred_currency` back as a scoped project (display-only reformatting of already-fetched prices, not a live conversion pipeline touching Duffel/Nuitee) — see §3 for why it was cut from v1.
* **Push notification tokens**: a `device_tokens` table keyed by `user_id` if we add price-drop or trip-reminder notifications.
* **Soft delete**: swap `delete` policy/behavior for a `deleted_at` column if "undo delete" becomes a feature — no schema break either way since it's additive.
* **"Active sessions" / "log out other devices" UI**: `refresh_tokens.user_agent` plus a bulk-revoke-by-`user_id` endpoint already gives us what we need for this.
* **Google/Apple OAuth**: additive — Supabase Auth supports it without changing `auth.users`/`profiles`; only the login flow and provider config change.

---

## 8. Decisions (locked in)

* **Sync path: client → Node/Express backend → Supabase.** The Flutter app never talks to Supabase directly. All saved-travel reads/writes go through new endpoints on the existing backend (e.g. `POST/GET/DELETE /api/travels`), which hold the Supabase **service-role key** server-side and enforce `user_id` scoping in application code (RLS stays on as defense-in-depth, but the backend is the trusted caller). This matches the current architecture where the Flutter app only ever calls the Node backend, never third-party APIs directly.
* **Auth methods: email/password at launch**, with the schema and Supabase Auth config left open to add Google/Apple OAuth later — `auth.users`/`profiles` need no changes to support that when it comes; it's purely a frontend + Supabase Auth provider config addition.
* **Login required to save.** Saving a travel plan now requires an authenticated user — no anonymous/local-only save path going forward. This simplifies `saved_travels` (no nullable `user_id`, no "claim on login" merge logic) and the client UX (show a sign-in prompt when the user taps "save" while logged out). `shared_preferences` local storage is retired for saved travels rather than kept as a guest fallback.
* **Access token: 15-minute expiry, backend-issued JWT.** Verified stateless by signature; no DB lookup needed per request.
* **Refresh token: opaque, hashed at rest, rotated on every use.** Raw value shown to the client exactly once (at issuance); the backend only ever stores/compares `sha256(token)`. A used-and-revoked token being replayed triggers full session invalidation (§4.4).
* **Expiry signal: `401 Unauthorized`**, not 404 — see §4.5 for rationale. The client's HTTP layer treats a 401 as "silently refresh, then retry," showing the user a loading state rather than an error, and only surfaces a hard "please log in again" screen if the refresh call itself fails (refresh token expired/revoked/reused).

## 9. Migration path (high-level, for later)

1. Provision Supabase project, enable email/password auth (leave Google/Apple providers off but note them in project config for later).
2. Create `profiles`, `saved_travels`, `refresh_tokens` tables + RLS policies + the `handle_new_user` trigger via a SQL migration checked into `backend/supabase/migrations/`.
3. Add `@supabase/supabase-js` to the **backend** only, initialized with the service-role key (never shipped to the client), used solely for password verification against `auth.users` and for the `saved_travels`/`search_history` data access. New Express routes:
   * `POST /api/auth/login`, `POST /api/auth/signup`, `POST /api/auth/refresh`, `POST /api/auth/logout` — issue/rotate/revoke the backend's own access + refresh tokens per §4.
   * `GET/POST/DELETE /api/travels` — saved-travels CRUD, each requiring a valid backend-issued access token (verified via JWT signature, not a Supabase call) and scoped to that `user_id`.
4. Add an `authenticate` Express middleware that verifies the access token JWT and returns `401` on missing/expired/invalid tokens, per §4.5.
5. Update `TravelStorageService` on the Flutter side to call the new `/api/travels` endpoints instead of `shared_preferences`, with an HTTP client wrapper that: attaches `Authorization: Bearer <accessToken>`; on a `401`, calls `/api/auth/refresh`, stores the new token pair, and retries the original request once (all behind a loading state, invisible to the user); and on refresh failure, routes to a login screen.
6. Store both tokens via `flutter_secure_storage` (not `shared_preferences`, which is unencrypted) on the client.
7. Gate the existing "save" button/action behind an auth check — logged-out users see a sign-in prompt instead of a silent local save.
8. Add backend tests mirroring the existing `jest`/`supertest` coverage style for the new `/api/auth/*` and `/api/travels` endpoints, including: 401 on expired/missing access token, successful rotation on `/api/auth/refresh`, and reuse-detection invalidation.
