# Mini-Brig: Learning Project Roadmap

> Mục tiêu: Xây dựng lại service brig ở dạng tối giản để học Haskell thực tế —
> xác thực, database, gọi service khác — từng bước một.

---

## Tech Stack

| Brig thật | Mini-brig (học) | Lý do đơn giản hơn |
|-----------|-----------------|-------------------|
| Servant | Servant | Giữ nguyên — quan trọng |
| Polysemy | `ReaderT Env IO` | Cùng idea, ít magic hơn |
| Cassandra + Postgres | Chỉ PostgreSQL | Một DB đủ để học |
| ZAuth tokens | JWT (`jose`) | Standard hơn |
| `hasql` | `postgresql-simple` | Dễ đọc hơn |
| `bcrypt` qua subsystem | `bcrypt` trực tiếp | Ít layer hơn |
| Polysemy Effects | Typeclasses / direct IO | Giới thiệu sau Phase 6 |

---

## Cấu trúc Project

```
mini-brig/
├── app/
│   └── Main.hs                  ← Entry point: khởi server
├── src/
│   ├── App.hs                   ← Env, AppM monad (ReaderT + ExceptT)
│   ├── Config.hs                ← Đọc config từ env vars / file
│   ├── Types.hs                 ← Domain types: User, UserId, Email...
│   ├── Error.hs                 ← AppError type
│   ├── API/
│   │   ├── Routes.hs            ← Servant type-level API declaration
│   │   ├── User.hs              ← User handlers (register, get profile)
│   │   └── Auth.hs              ← Auth handlers (login, logout)
│   ├── DB/
│   │   ├── User.hs              ← SQL queries cho user
│   │   └── Migration.hs         ← Schema migrations
│   ├── Auth/
│   │   ├── Password.hs          ← bcrypt hash/verify
│   │   └── JWT.hs               ← Token tạo và verify
│   └── Client/
│       └── Notification.hs      ← Giả lập gọi service khác
├── sql/
│   └── schema.sql               ← DDL
├── test/
│   ├── Spec.hs
│   └── API/
│       ├── UserSpec.hs
│       └── AuthSpec.hs
└── mini-brig.cabal
```

---

## Phase 1 — Scaffolding & Domain Types

**Mục tiêu:** Setup project, định nghĩa types, HTTP server trả về "hello".

**Học được:** Haskell records, newtype, deriving, JSON với Aeson.

```cabal
-- mini-brig.cabal
build-depends:
    base                 >= 4.17
  , servant-server       >= 0.20
  , warp                 >= 3.3
  , aeson                >= 2.1
  , text
  , uuid
```

```haskell
-- src/Types.hs
newtype UserId    = UserId UUID          deriving (Show, Eq, Generic, FromJSON, ToJSON)
newtype Email     = Email Text           deriving (Show, Eq, Generic, FromJSON, ToJSON)
newtype Handle    = Handle Text          deriving (Show, Eq, Generic, FromJSON, ToJSON)

data User = User
  { userId    :: UserId
  , userEmail :: Email
  , userName  :: Text
  , userHandle :: Maybe Handle
  } deriving (Show, Eq, Generic, FromJSON, ToJSON)
```

**Đọc trong brig thật:** [libs/wire-api/src/Wire/API/User.hs](libs/wire-api/src/Wire/API/User.hs)

---

## Phase 2 — Servant Routing

**Mục tiêu:** Khai báo API ở type level. Hiểu tại sao Servant tốt hơn string routing.

**Học được:** `:<|>`, `Capture`, `ReqBody`, `Get`/`Post`, type-level programming.

```haskell
-- src/API/Routes.hs
type UserAPI =
       "register" :> ReqBody '[JSON] NewUser      :> Post '[JSON] UserProfile
  :<|> "login"    :> ReqBody '[JSON] LoginRequest :> Post '[JSON] TokenResponse
  :<|> "users"    :> Capture "uid" UserId         :> Get  '[JSON] UserProfile
  :<|> "users"    :> "self"                       :> Get  '[JSON] UserProfile

userAPI :: Proxy UserAPI
userAPI = Proxy
```

Compile error = route sai. Không cần test thủ công.

**Đọc trong brig thật:** [services/brig/src/Brig/API/Public.hs:371](services/brig/src/Brig/API/Public.hs#L371)

---

## Phase 3 — App Monad (quan trọng nhất)

**Mục tiêu:** Hiểu `ReaderT` và `ExceptT` — nền tảng của mọi Haskell web app.

**Học được:** Monad transformer, `ask`, `throwError`, `liftIO`, `hoistServer`.

```haskell
-- src/App.hs
import Control.Monad.Reader
import Control.Monad.Except
import Data.Pool (Pool)
import Database.PostgreSQL.Simple (Connection)

data Env = Env
  { dbPool    :: Pool Connection
  , jwtSecret :: ByteString
  , port      :: Int
  }

-- AppM là monad của toàn app
type AppM = ReaderT Env (ExceptT AppError IO)

-- Chạy AppM về IO (Servant cần IO)
runAppM :: Env -> AppM a -> IO (Either AppError a)
runAppM env action = runExceptT (runReaderT action env)

-- Chuyển AppM thành Servant Handler
appToHandler :: Env -> AppM a -> Handler a
appToHandler env action =
  liftIO (runAppM env action) >>= \case
    Left err  -> throwError (toServantError err)
    Right val -> pure val
```

**Tại sao cần ReaderT?** Thay vì truyền `env` vào mọi hàm, ta "nhúng" nó vào monad.
**Tại sao cần ExceptT?** Thay vì `IO (Either Error a)` ở khắp nơi, dùng `throwError` sạch hơn.

**Đọc trong brig thật:** [services/brig/src/Brig/App.hs](services/brig/src/Brig/App.hs)

---

## Phase 4 — PostgreSQL

**Mục tiêu:** Kết nối DB, query, migrations đơn giản.

**Học được:** Connection pooling, `FromRow`/`ToRow` instances, SQL trong Haskell.

```cabal
build-depends:
  , postgresql-simple    >= 0.7
  , resource-pool        >= 0.4
```

```sql
-- sql/schema.sql
CREATE TABLE users (
  id            UUID        PRIMARY KEY,
  email         TEXT        UNIQUE NOT NULL,
  name          TEXT        NOT NULL,
  password_hash TEXT        NOT NULL,
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE connections (
  from_user UUID NOT NULL REFERENCES users(id),
  to_user   UUID NOT NULL REFERENCES users(id),
  status    TEXT NOT NULL DEFAULT 'pending',
  PRIMARY KEY (from_user, to_user)
);
```

```haskell
-- src/DB/User.hs
instance FromRow User where
  fromRow = User <$> field <*> field <*> field

getUser :: UserId -> AppM (Maybe User)
getUser uid = do
  pool <- asks dbPool
  liftIO $ withResource pool $ \conn ->
    listToMaybe <$>
      query conn "SELECT id, email, name FROM users WHERE id = ?" (Only uid)

createUser :: NewStoredUser -> AppM User
createUser new = do
  pool <- asks dbPool
  liftIO $ withResource pool $ \conn -> do
    [user] <- query conn
      "INSERT INTO users (id, email, name, password_hash) VALUES (?,?,?,?) RETURNING id, email, name"
      (new.id, new.email, new.name, new.passwordHash)
    pure user
```

**Đọc trong brig thật:** [services/brig/src/Brig/Data/User.hs](services/brig/src/Brig/Data/User.hs)

---

## Phase 5 — Authentication

**Mục tiêu:** Hash password + JWT. Protect routes với middleware.

**Học được:** Bcrypt, JWT (header/payload/signature), Servant Auth.

```cabal
build-depends:
  , bcrypt               >= 0.0.11
  , jose                 >= 0.11
  , servant-auth-server  >= 0.4
```

```haskell
-- src/Auth/Password.hs
import Crypto.BCrypt

hashPassword :: Text -> IO (Maybe ByteString)
hashPassword pwd = hashPasswordUsingPolicy slowerBcryptHashingPolicy (encodeUtf8 pwd)

verifyPassword :: Text -> ByteString -> Bool
verifyPassword pwd hash = validatePassword hash (encodeUtf8 pwd)
```

```haskell
-- src/Auth/JWT.hs
data UserClaims = UserClaims
  { userId :: UserId
  } deriving (Show, Generic, ToJSON, FromJSON)

instance ToJWT UserClaims
instance FromJWT UserClaims

makeToken :: JWK -> UserId -> IO (Either Error SignedJWT)
makeToken key uid = do
  now <- getCurrentTime
  let claims = emptyClaimsSet
        & claimSub ?~ uid
        & claimExp ?~ NumericDate (addUTCTime 3600 now)
  signClaims key (newJWSHeader ((), RS256)) claims
```

```haskell
-- src/API/Routes.hs — Protected routes
type ProtectedAPI = Auth '[JWT] UserClaims :> (
       "users" :> "self" :> Get '[JSON] UserProfile
  :<|> "connections" :> Capture "uid" UserId :> Post '[JSON] Connection
  )
```

**Đọc trong brig thật:** [services/brig/src/Brig/API/Auth.hs:135](services/brig/src/Brig/API/Auth.hs#L135)

---

## Phase 6 — Gọi Service Khác

**Mục tiêu:** Bắt chước `Brig.IO.Intra` — gửi HTTP request sang service khác, xử lý lỗi.

**Học được:** `http-client`, timeout, error handling across service boundaries.

```cabal
build-depends:
  , http-client          >= 0.7
  , http-client-tls      >= 0.3
  , aeson
```

```haskell
-- src/Client/Notification.hs
-- Giả lập brig gọi gundeck để push notification

data NotificationClient = NotificationClient
  { baseUrl :: String
  , manager :: Manager
  }

data UserEvent = UserCreated UserId | UserDeleted UserId

sendNotification :: UserId -> UserEvent -> AppM ()
sendNotification uid event = do
  client <- asks notificationClient
  let body = encode event
      req  = (parseRequest_ $ client.baseUrl <> "/push")
               { method      = "POST"
               , requestBody = RequestBodyLBS body
               }
  response <- liftIO $ httpLbs req client.manager
  case responseStatus response of
    s | s == status200 -> pure ()
    s -> throwError $ ServiceCallFailed "notification" (statusCode s)
```

**Đọc trong brig thật:** [services/brig/src/Brig/IO/Intra.hs](services/brig/src/Brig/IO/Intra.hs)

---

## Phase 7 — Giới thiệu Polysemy (optional)

**Mục tiêu:** Hiểu TẠI SAO Polysemy tồn tại sau khi đã cảm nhận giới hạn của ReaderT.

**Khi nào cần:** Khi muốn test mà không cần database thật, hoặc swap implementation.

```haskell
-- Trước (Phase 3-6): gọi trực tiếp, khó test
createUser :: NewUser -> AppM StoredUser
createUser new = do
  pool <- asks dbPool
  liftIO $ insertUserDB pool new      -- luôn cần DB thật

-- Sau (Phase 7): effect-based, dễ test và swap
createUser :: (Member UserStore r) => NewUser -> Sem r StoredUser
createUser new = UserStore.insert new
-- Test:    interpret bằng IORef in-memory
-- Prod:    interpret bằng Cassandra/Postgres
```

**Đọc trong brig thật:** [services/brig/src/Brig/CanonicalInterpreter.hs](services/brig/src/Brig/CanonicalInterpreter.hs)

---

## Bảng theo dõi tiến độ

| Phase | Nội dung | Khái niệm chính | Trạng thái |
|-------|---------|-----------------|-----------|
| 1 | Scaffolding + Types | records, newtype, Aeson | — |
| 2 | Servant routing | type-level API, `:<|>` | — |
| 3 | App monad | ReaderT, ExceptT, monad transformers | — |
| 4 | PostgreSQL | FromRow, connection pool, SQL | — |
| 5 | Authentication | bcrypt, JWT, protected routes | — |
| 6 | Service calls | http-client, error handling | — |
| 7 | Polysemy | effects, interpreters, testability | — |

---

## Khởi động ngay

```bash
mkdir mini-brig && cd mini-brig
cabal init --non-interactive --lib --exe
```

**Thứ tự viết code:**
1. `src/Types.hs` — định nghĩa `User`, `Email`, `UserId`
2. `app/Main.hs` — server hello world chạy được
3. `src/API/Routes.hs` — khai báo routes
4. `src/App.hs` — `Env` và `AppM`
5. Tiếp tục từng phase...
