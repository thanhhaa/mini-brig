# Mini-Brig Learning Path

---

## Chiến lược tổng quan

```
Phase 1 → Basic HTTP server + domain types
Phase 2 → Type-safe routing với Servant
Phase 3 → App monad (ReaderT + ExceptT)
Phase 4 → Database thật (PostgreSQL)
Phase 5 → Authentication (password hashing + JWT)
Phase 6 → Gọi service khác (HTTP client)
Phase 7 → (tuỳ chọn) Giới thiệu Polysemy
```

Mỗi phase chỉ thêm **một khái niệm mới** — đây là cách học Haskell hiệu quả nhất.

---

## Tech stack cho mini-brig

| Brig thật | Mini-brig (học) | Lý do đơn giản hơn |
|-----------|-----------------|-------------------|
| Servant | Servant | Giữ nguyên — quan trọng |
| Polysemy | `ReaderT Env IO` | Cùng idea, ít magic hơn |
| Cassandra + Postgres | Chỉ PostgreSQL | Một DB đủ để học |
| ZAuth tokens | JWT (thư viện `jose`) | Standard hơn |
| `hasql` | `postgresql-simple` | Dễ đọc hơn |
| `bcrypt` qua subsystem | `bcrypt` trực tiếp | Ít layer hơn |

---

## Phase 1 — Scaffolding và domain types

**Mục tiêu:** Setup project, định nghĩa types, HTTP server đơn giản nhất.

```
mini-brig/
├── app/
│   └── Main.hs
├── src/
│   ├── Types.hs         ← Định nghĩa User, UserId, Email...
│   ├── Config.hs        ← Đọc config từ env vars
│   └── API/
│       └── Routes.hs    ← Khai báo Servant API
├── mini-brig.cabal
└── cabal.project
```

Bắt đầu bằng `cabal init` rồi thêm dependencies:

```cabal
build-depends:
    base
  , servant-server
  , warp
  , aeson
  , text
  , uuid
```

**Khái niệm học được:** Haskell records, newtype, deriving, JSON với Aeson.

---

## Phase 2 — Servant routing

**Mục tiêu:** Khai báo API ở type level, hiểu tại sao Servant tốt hơn string-based routing.

```haskell
-- src/API/Routes.hs
type UserAPI =
       "register" :> ReqBody '[JSON] NewUser      :> Post '[JSON] UserProfile
  :<|> "login"    :> ReqBody '[JSON] LoginRequest :> Post '[JSON] TokenResponse
  :<|> "users"    :> Capture "uid" UserId         :> Get  '[JSON] UserProfile
```

Compile error = route sai. Không cần test thủ công.

**Khái niệm học được:** Type-level programming, `:<|>`, `Capture`, `ReqBody`, `Named`.

---

## Phase 3 — App monad (quan trọng nhất)

**Mục tiêu:** Hiểu tại sao cần `ReaderT` và `ExceptT` — đây là nền tảng của mọi Haskell app.

```haskell
-- src/App.hs

data Env = Env
  { dbPool    :: Pool Connection   -- kết nối database
  , jwtSecret :: ByteString        -- ký JWT
  , port      :: Int
  }

-- AppM là "monad" của toàn app
type AppM = ReaderT Env (ExceptT AppError IO)

-- Chạy AppM về IO (Servant cần IO)
runAppM :: Env -> AppM a -> IO (Either AppError a)
runAppM env action = runExceptT (runReaderT action env)
```

**Tại sao cần ReaderT?** Thay vì truyền `env` vào mọi hàm, ta "nhúng" nó vào monad.

**Tại sao cần ExceptT?** Thay vì `IO (Either Error a)` ở mọi nơi, ta có cú pháp sạch hơn với `throwError`.

**Khái niệm học được:** Monad transformer, `ask`, `throwError`, `liftIO`, `hoistServer`.

---

## Phase 4 — PostgreSQL

**Mục tiêu:** Connect DB, query, migrations đơn giản.

```haskell
-- src/DB/User.hs
createUser :: NewStoredUser -> AppM StoredUser
createUser new = do
  pool <- asks dbPool           -- lấy pool từ Env
  liftIO $ withResource pool $ \conn ->
    query conn
      "INSERT INTO users (id, email, name, password_hash) VALUES (?,?,?,?) RETURNING *"
      (new.id, new.email, new.name, new.passwordHash)
```

Schema đơn giản:

```sql
CREATE TABLE users (
  id            UUID PRIMARY KEY,
  email         TEXT UNIQUE NOT NULL,
  name          TEXT NOT NULL,
  password_hash TEXT NOT NULL,
  created_at    TIMESTAMPTZ DEFAULT NOW()
);
```

**Khái niệm học được:** Connection pooling, `FromRow`/`ToRow` instances, migrations thủ công.

---

## Phase 5 — Authentication

**Mục tiêu:** Hash password + tạo/verify JWT.

```haskell
-- src/Auth.hs

-- Hash password khi register
hashPassword :: PlainTextPassword -> IO PasswordHash
hashPassword pwd = bcrypt 12 (encodeUtf8 pwd)

-- Verify khi login
verifyPassword :: PlainTextPassword -> PasswordHash -> Bool
verifyPassword pwd hash = validatePassword (encodeUtf8 pwd) hash

-- Tạo JWT sau khi login thành công
makeToken :: UserId -> AppM Token
makeToken uid = do
  secret <- asks jwtSecret
  now    <- liftIO getCurrentTime
  let claims = jwtClaims uid (addUTCTime 3600 now)  -- 1 giờ
  pure $ signJWT secret claims

-- Protect routes với middleware
type ProtectedAPI = Auth '[JWT] UserId :> "users" :> "self" :> Get '[JSON] UserProfile
```

**Khái niệm học được:** Bcrypt, JWT (header/payload/signature), Servant Auth, middleware.

---

## Phase 6 — Gọi service khác

**Mục tiêu:** Bắt chước cách brig gọi galley — gửi HTTP request, parse response, xử lý lỗi.

```haskell
-- src/Client/Notification.hs
-- Giả lập việc brig gọi gundeck để push notification

data NotificationClient = NotificationClient
  { baseUrl :: BaseUrl
  , manager :: Manager
  }

sendNotification :: UserId -> Event -> AppM ()
sendNotification uid event = do
  client <- asks notificationClient
  let req = buildRequest client uid event
  response <- liftIO $ httpLbs req client.manager
  case responseStatus response of
    s | s == status200 -> pure ()
    s -> throwError $ ServiceCallFailed "notification" s
```

**Khái niệm học được:** `http-client`, error handling across service boundaries, timeouts.

---

## Phase 7 — Giới thiệu Polysemy (sau khi đã hiểu Phase 1–6)

Sau khi đã build mini-brig với `ReaderT`, bạn sẽ tự thấy vấn đề:
- Khó test vì mọi thứ đều là `IO`
- Muốn swap implementation (real DB vs in-memory) thì phải sửa nhiều chỗ

Đây là lúc Polysemy có ý nghĩa:

```haskell
-- Trước (Phase 3-6): gọi trực tiếp
createUser :: NewUser -> AppM StoredUser
createUser new = do
  pool <- asks dbPool
  liftIO $ insertUserDB pool new

-- Sau (Phase 7): effect-based
createUser :: (Member UserStore r) => NewUser -> Sem r StoredUser
createUser new = UserStore.insert new
-- Implementation được inject ở ngoài — dễ test, dễ swap
```

---

## Bắt đầu ngay hôm nay

```bash
# 1. Tạo project
mkdir mini-brig && cd mini-brig
cabal init --non-interactive

# 2. Tạo file cabal với dependencies cần thiết
# (thêm servant-server, warp, aeson, postgresql-simple, bcrypt, jose, resource-pool)

# 3. Bắt đầu từ file này:
# src/Types.hs → định nghĩa User, Email, UserId
# app/Main.hs  → server đơn giản trả về "hello"
```

**Thứ tự đọc code brig thật song song:**

| Bạn đang học | Đọc trong brig |
|-------------|----------------|
| Phase 2 (Servant) | [API/Public.hs:371](services/brig/src/Brig/API/Public.hs#L371) — `servantSitemap` |
| Phase 3 (App monad) | [App.hs](services/brig/src/Brig/App.hs) — `Env`, `AppT` |
| Phase 4 (DB) | [Data/User.hs](services/brig/src/Brig/Data/User.hs) |
| Phase 5 (Auth) | [API/Auth.hs:135](services/brig/src/Brig/API/Auth.hs#L135) — `login` |
| Phase 6 (Service calls) | [IO/Intra.hs](services/brig/src/Brig/IO/Intra.hs) |
| Phase 7 (Polysemy) | [CanonicalInterpreter.hs](services/brig/src/Brig/CanonicalInterpreter.hs) |
