# Session Log — Nghiên cứu Brig & Setup môi trường Haskell

> Ngày: 2026-05-16  
> Project: wire-server / services/brig  
> Mục tiêu: Hiểu sâu service brig, setup môi trường, lên kế hoạch viết mini-brig để học Haskell

---

## Phần 1 — Phân tích service brig

### Câu hỏi

> 1. Giải thích services/brig trong project này theo cách có cấu trúc (vấn đề nó giải quyết, trách nhiệm, module chính, tương tác với service khác, công nghệ và pattern).
> 2. Phân tích cấu trúc thư mục.
> 3. Tìm entry point chính — service khởi động như thế nào, config load ra sao, HTTP server khởi tạo thế nào.
> 4. Trace toàn bộ luồng xử lý một API liên quan đến user (tạo user hoặc login).
> Viết report dưới dạng file .md

### Kết quả → [brig-deep-dive.md](brig-deep-dive.md)

---

#### 1.1 Brig làm gì?

Wire Server là nền tảng nhắn tin mã nguồn mở. Trong kiến trúc microservices, mỗi service có trách nhiệm riêng:

| Service | Làm gì |
|---------|--------|
| **brig** | Quản lý người dùng, xác thực, kết nối bạn bè |
| galley | Quản lý team, cuộc trò chuyện, phân quyền |
| gundeck | Gửi push notification |
| cargohold | Lưu trữ file, media |
| spar | Xử lý SAML SSO |
| federator | Giao tiếp với các Wire server khác |

**Brig chịu trách nhiệm toàn bộ vòng đời người dùng:** đăng ký, đăng nhập, quản lý profile, quản lý thiết bị (prekeys cho E2E encryption), kết nối bạn bè, kích hoạt email, OAuth, federation.

---

#### 1.2 Cấu trúc thư mục

```
services/brig/
├── exec/Main.hs                 ← Entry point thực thi
├── src/Brig/
│   ├── API/                     ← HTTP handlers
│   │   ├── Public.hs            ← Public routes (Servant sitemap)
│   │   ├── Internal.hs          ← Internal API (cho service khác)
│   │   ├── Federation.hs        ← Federation endpoints
│   │   ├── User.hs              ← Business logic tạo/xóa user
│   │   ├── Auth.hs              ← Login, logout, session
│   │   ├── Client.hs            ← Device client management
│   │   └── Connection.hs        ← Kết nối giữa users
│   ├── App.hs                   ← Env data type (trạng thái toàn service)
│   ├── Run.hs                   ← Khởi động service
│   ├── Main.hs                  ← CLI argument parsing
│   ├── Options.hs               ← Parse config YAML
│   ├── CanonicalInterpreter.hs  ← Kết nối Polysemy effects với implementation
│   ├── Data/                    ← Database queries trực tiếp
│   ├── Effects/                 ← Polysemy effect definitions
│   ├── IO/Intra.hs              ← HTTP calls sang Galley, Gundeck, Cargohold
│   ├── Schema/                  ← DB migrations (V43–V92)
│   └── ...
├── test/unit/ & test/integration/
└── brig.cabal
```

**File quan trọng nhất:**

| File | Vai trò |
|------|---------|
| `exec/Main.hs` | Entry point — gọi `Brig.Main.main` |
| `src/Brig/Run.hs` | Khởi động HTTP server + background threads |
| `src/Brig/App.hs` | Định nghĩa `Env` — trạng thái toàn service |
| `src/Brig/API/Public.hs` | Khai báo tất cả public HTTP routes |
| `src/Brig/API/User.hs` | Business logic tạo user, kích hoạt |
| `src/Brig/API/Auth.hs` | Login, logout, session management |
| `src/Brig/IO/Intra.hs` | Gọi HTTP sang Galley, Gundeck, Cargohold |
| `src/Brig/CanonicalInterpreter.hs` | Effect system wire-up |

---

#### 1.3 Entry point và khởi động

**Luồng khởi động:**

```
binary brig
  │
  ▼
exec/Main.hs            ← withOpenSSL, gọi Brig.Main.main
  │
  ▼
Brig.Main.main          ← parse CLI args, load YAML config
  │                        default: /etc/wire/brig/conf/brig.yaml
  ▼
Brig.Run.run opts
  ├─ newEnv opts         ← kết nối Cassandra, PostgreSQL, Elasticsearch
  │                         tạo HTTP clients cho Galley/Gundeck/Cargohold
  ├─ runAllMigrations    ← chạy PostgreSQL migrations
  ├─ spawn threads:
  │    internalEventListener   ← STOMP/SQS
  │    emailListener           ← AWS SES bounces
  │    sftDiscovery            ← video calling servers
  │    turnDiscovery           ← VoIP TURN servers
  │    authMetrics             ← AWS token metrics
  │    pendingActivationCleanup
  │
  ▼
Warp HTTP server
  ├─ Middleware: OpenTelemetry → Version → RequestId → Prometheus → Gzip → Errors
  └─ Servant.serveWithContext
       ├─ DocsAPI         (Swagger)
       ├─ BrigAPI          (Public)
       ├─ IAPI.API         (Internal)
       ├─ FederationAPI    (Federation)
       └─ VersionAPI       (Version negotiation)
```

**Frameworks:** Servant (type-safe routing), WAI/Warp (HTTP server), Polysemy (effect system).

---

#### 1.4 Trace luồng: POST /register (Tạo User)

**Bước 1 — Servant Router** (`API/Public.hs:500`)
```haskell
Named @"register" createUser   -- route được khai báo ở type level
```

**Bước 2 — Handler** (`API/Public.hs:964`)
```haskell
createUser ip (Public.NewUserPublic new) = lift . runExceptT $ do
  API.checkRestrictedUserCreation new          -- kiểm tra domain restriction
  checkAllowlistWithError RegisterErrorAllowlistError  -- kiểm tra allowlist
  result <- API.createUser (RateLimitIp ip) new  -- gọi business logic
  sendActivationEmail ...                        -- gửi email xác nhận
  cok <- AuthenticationSubsystem.newCookie ...  -- tạo session cookie
  pure $ Public.RegisterSuccess cok (Public.SelfProfile acc)
```

**Bước 3 — Business Logic** (`API/User.hs:359`)
```haskell
createUser rateLimitKey new = do
  email <- fetchAndValidateEmail new
  (mNewTeamUser, teamInvitation, tid) <- handleTeamInvitation new
  verifyUniquenessAndCheckBlacklist emailKey   -- UserKeyStore + BlockListStore → Cassandra
  mHashedPassword <- HashPassword.hashPassword8 rateLimitKey password
  account <- newStoredUser new' mbInv tid mbHandle  -- build record in memory
  lift . liftSem $ do
    UserStore.createUser account Nothing         -- → Cassandra
    GalleyAPIAccess.createSelfConv uid           -- → HTTP → Galley
    Events.generateUserEvent uid Nothing (UserCreated u)  -- → RabbitMQ
  handleEmailActivation email uid ...            -- → ActivationCodeStore → Cassandra
  pure $! CreateUserResult u edata createUserTeam
```

**Bước 4 — Effects → Implementation** (qua Polysemy)

```
UserStore.createUser     → Cassandra query
GalleyAPIAccess.*        → HTTP call sang Galley service
Events.generateUserEvent → RabbitMQ publish
EmailSubsystem.sendMail  → SMTP hoặc AWS SES
BlockListStore.exists    → Cassandra query
```

**Sơ đồ đầy đủ:**
```
POST /register
  → Middleware stack
  → Servant Router → createUser handler (Public.hs)
    → checkRestrictedUserCreation
    → checkAllowlist
    → API.createUser (User.hs)
        → validateEmail
        → verifyUniquenessAndCheckBlacklist → Cassandra
        → hashPassword
        → UserStore.createUser              → Cassandra
        → GalleyAPIAccess.createSelfConv   → HTTP → Galley
        → Events.generateUserEvent         → RabbitMQ
        → ActivationCodeStore              → Cassandra
    → sendActivationEmail                  → SMTP/SES
    → newCookie                            → Cassandra (session)
  ← HTTP 201 { cookie, user }
```

---

#### 1.5 Các công nghệ và pattern

**Databases:**

| DB | Dùng cho |
|----|---------|
| Cassandra | User records, sessions, connections, prekeys |
| PostgreSQL | Team collaborators, user groups, OAuth |
| Elasticsearch | User search |
| DynamoDB (AWS) | Prekey storage (optional) |
| RabbitMQ | Event pub/sub, background jobs |

**Polysemy — Effect System:**
- Tách biệt business logic khỏi implementation (giống dependency injection tại compile time)
- `Member UserStore r` trong type signature = "hàm này cần effect UserStore"
- `CanonicalInterpreter.hs` wire-up effects với Cassandra/PostgreSQL/HTTP thực tế

**Monad Stack:**
```
Handler r a
  = ExceptT HttpError (AppT r) a
  = ExceptT HttpError (ReaderT Env (Sem (BrigCanonicalEffects ++ r))) a
```

**Servant:** Routes khai báo ở type level — sai kiểu = không compile.

---

## Phần 2 — Kế hoạch viết mini-brig để học Haskell

### Câu hỏi

> Nếu muốn viết lại service brig để học hiểu và thực hành code Haskell, xác thực, kết nối db, gọi service khác thì chúng ta nên bắt đầu như thế nào?

### Kết quả → [mini-brig-roadmap.md](mini-brig-roadmap.md)

---

**Chiến lược:** Xây dựng từng phase, mỗi phase thêm một khái niệm mới.

**Tech stack chọn:**

| Brig thật | Mini-brig | Lý do |
|-----------|-----------|-------|
| Servant | Servant | Giữ nguyên |
| Polysemy | `ReaderT Env IO` | Cùng idea, ít magic hơn |
| Cassandra + Postgres | Chỉ PostgreSQL | Một DB đủ |
| ZAuth | JWT (`jose`) | Standard hơn |
| `hasql` | `postgresql-simple` | Dễ đọc hơn |

**7 Phases:**

| Phase | Nội dung | Khái niệm chính |
|-------|---------|-----------------|
| 1 | Scaffolding + Types | records, newtype, Aeson |
| 2 | Servant routing | type-level API, `:<|>` |
| 3 | App monad | ReaderT, ExceptT, monad transformers |
| 4 | PostgreSQL | FromRow, connection pool, SQL |
| 5 | Authentication | bcrypt, JWT, protected routes |
| 6 | Gọi service khác | http-client, error handling |
| 7 | Polysemy (optional) | effects, interpreters, testability |

---

## Phần 3 — Kiểm tra môi trường IDE

### Câu hỏi

> Trước khi setup project, cần setup môi trường IDE trước. Check lại project wire này xem đang dùng lint, format gì, Haskell version bao nhiêu.

### Kết quả

**Wire-server dùng:**

| Công cụ | Version / Tool | Config file |
|---------|---------------|-------------|
| GHC | **9.10** (via Nix: `ghc910`) | `nix/overlay.nix` |
| Formatter | **ormolu** | `.ormolu` |
| Linter | **hlint** | `.hlint.yaml` |
| Dead code | **weeder** | `weeder.toml` |
| Cabal formatter | **cabal-fmt** | — |
| Dev feedback | **ghcid** | — |
| IDE | **HLS** (GHC 9.10 version) | — |
| Compiler flags | `-Werror` | `cabal.project` |
| Build system | Nix flakes + cabal | `flake.nix` |

**Chi tiết `.hlint.yaml`:**
```yaml
- arguments: [ -XQuasiQuotes, -XOverloadedRecordDot, --color ]
- ignore: { name: Redundant $ }      # ormolu style
- ignore: { name: Avoid lambda }
- hint: { lhs: return, rhs: pure }   # prefer pure over return
- error: { name: Use shutdown, lhs: runSettings, rhs: runSettingsWithShutdown }
```

**Chi tiết `.ormolu`:**  
Khai báo fixity cho các operator Wire-specific: `.=`, `?~`, `.~`, `&`, `===`, v.v.

**Máy hiện tại:**

| Công cụ | Trạng thái | Vấn đề |
|---------|-----------|--------|
| GHC | 9.4.7 (active) | Thiếu 9.10 |
| HLS | 2.4.0.0 cho GHC 9.0.2 | **Lệch với GHC active 9.4.7** |
| hlint | 3.5 | Ổn |
| ormolu | Chưa cài | **Thiếu** |
| cabal | 3.10.2.1 | Ổn |

**Fix cần làm:**
```bash
# Cài GHC 9.6.6 (stable, gần wire-server hơn)
ghcup install ghc 9.6.6 && ghcup set ghc 9.6.6

# Cài HLS đúng version
ghcup install hls 2.9.0.1 && ghcup set hls 2.9.0.1

# Cài ormolu
cabal install ormolu --overwrite-policy=always

# VSCode settings
# haskell.formattingProvider = "ormolu"
# haskell.plugin.hlint.diagnosticsOn = true
# editor.formatOnSave = true
```

---

## Phần 4 — Tích hợp Haskell Debugger

### Câu hỏi

> Tích hợp tool https://github.com/well-typed/haskell-debugger vào project. Hướng dẫn cách debug hiệu quả.

### Blocker phát hiện

`haskell-debugger` (hdb) **chỉ hỗ trợ GHC 9.14** — cần custom patches trong GHC chưa có ở version cũ hơn.

| | Version | Tương thích hdb? |
|-|---------|-----------------|
| GHC active | 9.4.7 | Không |
| Wire-server (Nix) | 9.10 | Không |
| hdb yêu cầu | **9.14** | — |

### Quyết định

> **Dùng GHCi built-in debugger + Debug.Trace**

Lý do: Không cần cài thêm, hoạt động ngay, đây là cách Haskell devs thực tế dùng nhiều nhất.

### Kết quả → [haskell-debug-guide.md](haskell-debug-guide.md)

---

**Debug.Trace — Nhanh nhất:**
```haskell
import Debug.Trace (trace, traceShow, traceShowId, traceM, traceShowM)

-- In string
trace "đang vào createUser" someValue

-- In giá trị qua Show
traceShowId someValue   -- in rồi trả về chính nó

-- Trong do-block
traceM $ "email: " <> show email

-- Helper tái sử dụng
debugVal :: Show a => String -> a -> a
debugVal label x = trace (label <> ": " <> show x) x
```

**GHCi Debugger:**
```
cabal repl

:break Module.functionName     -- đặt breakpoint
:step expression               -- chạy, dừng tại breakpoint
:steplocal                     -- step over (không đi vào hàm khác)
:continue                      -- tiếp tục
:print x                       -- in biến (không force)
:force x                       -- force evaluate rồi in
:sprint x                      -- xem phần đã evaluate
:back / :forward               -- backward/forward stepping
```

**Debug monad transformers:**
```
ghci> runExceptT (runReaderT (validateEmail "bad") testEnv)
Left InvalidEmail
```

**ghcid — feedback nhanh nhất:**
```bash
ghcid --command="cabal repl"
```

**Khi nào dùng gì:**

| Tình huống | Tool |
|-----------|------|
| Kiểm tra giá trị nhanh | `traceShowId` / `traceM` |
| Step-through từng dòng | GHCi `:break` + `:step` |
| Test hàm độc lập | GHCi gọi trực tiếp |
| Xem lỗi compile ngay khi save | `ghcid` |
| Debug monad stack | `runExceptT` / `runReaderT` trong GHCi |
| Inspect lazy thunk | GHCi `:sprint` → `:print` → `:force` |

---

## Phần 5 — Tổng hợp output files

### Câu hỏi

> Tổng hợp phần mini project thành 1 file .md và phần kỹ thuật debug thành 1 file .md riêng.

### Kết quả

| File tạo ra | Nội dung |
|-------------|---------|
| [brig-deep-dive.md](brig-deep-dive.md) | Phân tích đầy đủ service brig (4 phần) |
| [mini-brig-roadmap.md](mini-brig-roadmap.md) | Kế hoạch học qua 7 phase, tech stack, cấu trúc project, code ví dụ |
| [haskell-debug-guide.md](haskell-debug-guide.md) | Debug.Trace, GHCi debugger, ghcid, VS Code workflow, bảng "khi nào dùng gì" |
| [serve-capture-fromhttpapidata.md](serve-capture-fromhttpapidata.md) | Lỗi `serve`, vì sao `Capture` cần `FromHttpApiData`, ví dụ `cabal repl` |
| [run-build-curl-threaded.md](run-build-curl-threaded.md) | Chạy project: format/lint/build/run/curl, bug `-threaded` của Warp, bẫy relink + `+RTS --info` |
| [test-suite-setup.md](test-suite-setup.md) | Dựng test hspec + hspec-wai in-process; lỗi 415 / `Hspec.Wai.JSON` thiếu / thứ tự key JSON / pragma thừa |
| [session-log.md](session-log.md) | File này — toàn bộ nội dung trao đổi |

---

## Phần 6 — Gỡ lỗi serve / Capture / FromHttpApiData (Phase 2)

### Câu hỏi

> Giải thích lỗi `serve` trong `app/Main.hs`; vì sao `Capture "uid" UserId` lại
> đòi `FromHttpApiData`; đưa thêm ví dụ dùng `Capture` và `FromHttpApiData` ở
> `cabal repl`.

### Kết quả → [serve-capture-fromhttpapidata.md](serve-capture-fromhttpapidata.md)

---

**Tóm tắt:**

- Lỗi `No instance for FromHttpApiData UserId` báo ở `serve` nhưng gốc rễ ở kiểu
  `UserId`: GHC bung ràng buộc `HasServer UserAPI '[]` tới `Capture "uid" UserId`
  thì đòi `FromHttpApiData UserId`, thiếu instance nên gắn lỗi vào `serve`.
- `Capture` cần `FromHttpApiData` vì URL chỉ là `Text`, phải parse `Text → UserId`
  trước khi gọi handler (`ReqBody` thì dùng `FromJSON` vì nguồn là JSON body).
- Hai cách thêm instance: `deriving newtype` (cần `DerivingStrategies` +
  `GeneralizedNewtypeDeriving`) hoặc viết tay `parseUrlPiece`. Bẫy đã gặp:
  `missing-methods`, `deriving-defaults`, `Duplicate instance`.
- Ví dụ `cabal repl`: `parseUrlPiece` trực tiếp, và test `Capture` end-to-end
  in-process bằng `Network.Wai.Test` (200 / 400 / 404).

---

## Phần 7 — Chạy project: format / lint / build / run / curl (Phase 2)

### Câu hỏi

> Hãy chạy lại project này, kiểm tra format, lint,… và build run project thành
> công, gọi curl thử các hàm.

### Kết quả → [run-build-curl-threaded.md](run-build-curl-threaded.md)

---

**Tóm tắt:**

- Format (`ormolu`), lint (`hlint`), cabal-fmt: tất cả sạch. Build & test
  (`cabal build all`, `cabal test`) đều pass (test còn là stub).
- **Bug:** executable thiếu `-threaded` → Warp crash khi khởi động
  (`getSystemTimerManager: the TimerManager requires linking against the threaded
  runtime`). Sửa: thêm `ghc-options: -threaded -rtsopts -with-rtsopts=-N` vào
  stanza `executable mini-brig`.
- **Bẫy:** thêm `-threaded` rồi nhưng `cabal build` incremental **không relink**
  (binary vẫn vanilla RTS). Phải `cabal clean` rồi build lại; xác minh bằng
  `"$(cabal list-bin exe:mini-brig)" +RTS --info | grep "RTS way"` → cần `rts_thr`
  (không phải `rts_v`).
- **curl:** `/register` 200, `/login` 200, `/users/{uuid}` 200, UUID sai → 400
  "invalid UUID", JSON body thiếu field → 400 (aeson). Handler trả stub cố định
  nhưng routing + JSON + parse UUID đều đúng.
- Lưu ý: target `mini-brig` nhập nhằng giữa `lib:` và `exe:` → dùng
  `cabal run exe:mini-brig`.

---

## Phần 8 — Dựng test suite cho các endpoint (Phase 2)

### Câu hỏi

> Set up a test suite for the endpoints.

### Kết quả → [test-suite-setup.md](test-suite-setup.md)

---

**Tóm tắt:**

- Tách WAI `Application` ra library (`src/API/Server.hs`, export `app`) để cả
  executable lẫn test dùng chung; `app/Main.hs` chỉ còn `run 8080 app`.
- Test in-process bằng `hspec` + `hspec-wai` (gọi thẳng `Application`, không bind
  cổng): 6 test cho `/register`, `/login`, `/users/:uid` + case 400/404 →
  `cabal test` pass 6/6.
- **Lỗi đã xử lý:**
  - Servant trả **415** khi thiếu `Content-Type` → dùng `request` + header
    `application/json` thay cho `post`.
  - `Test.Hspec.Wai.JSON` (quasiquoter `[json|…|]`) **không expose** ở
    hspec-wai 0.12.0 → tự viết matcher decode body thành aeson `Value` rồi so
    sánh (kèm lợi ích **không phụ thuộc thứ tự key**).
  - hlint báo `TypeOperators` thừa → đổi sang `ExplicitNamespaces`.
- Deps test thêm: `aeson, bytestring, hspec, hspec-wai, http-types, text`.

---

## Tóm tắt kết luận

1. **Brig** là service trung tâm của Wire — quản lý toàn bộ người dùng, dùng Servant + Polysemy + Cassandra/Postgres.

2. **Để học Haskell** qua brig: đi từng phase (ReaderT trước Polysemy, `postgresql-simple` trước `hasql`). File [mini-brig-roadmap.md](mini-brig-roadmap.md) là kế hoạch cụ thể.

3. **Môi trường cần fix:** cài GHC 9.6.6 + HLS 2.9.0.1 + ormolu. Wire-server dùng Nix + GHC 9.10 nhưng cho mini-brig thì 9.6 LTS là đủ.

4. **Debug:** `Debug.Trace` + `cabal repl` + `ghcid` là đủ cho 90% trường hợp. `hdb` đợi GHC 9.14 stable.
