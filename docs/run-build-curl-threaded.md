# Chạy mini-brig: format → lint → build → run → curl (và bug `-threaded`)

> Ngày: 2026-06-04
> Mục tiêu: Chạy lại toàn bộ project mini-brig — kiểm tra format, lint, build,
> run server và gọi thử các endpoint bằng `curl`. Trong quá trình đã phát hiện
> và sửa một bug khiến server không khởi động được.

---

## 0. TL;DR

| Bước | Lệnh | Kết quả |
|------|------|---------|
| Format | `ormolu --mode check $(find app src test -name '*.hs')` | ✅ sạch |
| Lint | `hlint app src test` | ✅ No hints |
| Cabal format | `cabal-fmt --check mini-brig.cabal` | ✅ sạch |
| Build | `cabal build all` | ✅ |
| Test | `cabal test` | ✅ 1/1 (stub) |
| Run + curl | 3 endpoint | ✅ sau khi sửa bug |

**Bug đã sửa:** executable thiếu `-threaded` → Warp crash ngay khi khởi động.
**Bẫy phụ:** thêm `-threaded` rồi nhưng `cabal build` *incremental* không relink →
phải `cabal clean` mới ra binary threaded.

---

## 1. Bộ công cụ (toolchain)

Các binary dùng trong session, đều cài sẵn:

```
ormolu      → ~/.cabal/bin/ormolu        # format Haskell
hlint       → ~/.local/bin/hlint         # lint
cabal-fmt   → ~/.cabal/bin/cabal-fmt     # format file .cabal
cabal       → ~/.ghcup/bin/cabal
ghc 9.6.7   → ~/.ghcup/bin/ghc
```

> Quy ước dự án: **luôn chạy `cabal-fmt --inplace` sau khi sửa file `.cabal`.**

---

## 2. Format / Lint / Cabal-fmt

Chạy 3 lệnh kiểm tra (chỉ *check*, không sửa):

```bash
ormolu --mode check $(find app src test -name '*.hs')   # exit 0 = đã đúng format
hlint app src test                                       # "No hints"
cabal-fmt --check mini-brig.cabal                        # exit 0 = đã đúng format
```

Tất cả đều sạch ngay từ đầu — code đã được format chuẩn từ các session trước.

---

## 3. Build & Test

```bash
cabal build all      # build cả library, executable, test-suite
cabal test           # "Test suite not yet implemented." → PASS (stub)
```

Test hiện chỉ là stub (`test/Main.hs` in một dòng rồi exit 0) — chưa có assertion thật.

> Lưu ý: target tên `mini-brig` bị **nhập nhằng** giữa `lib:mini-brig` và
> `exe:mini-brig`. Khi build/run riêng executable phải ghi rõ:
> `cabal build exe:mini-brig`, `cabal run exe:mini-brig`,
> `cabal list-bin exe:mini-brig`.

---

## 4. 🐞 Bug chính: Warp cần threaded runtime

### Triệu chứng

Chạy server (`cabal run exe:mini-brig`) → log spam liên tục, server không phục vụ
request nào, `curl` trả về `exit 56` (connection reset):

```
GHC.Event.Thread.getSystemTimerManager: the TimerManager requires
linking against the threaded runtime
CallStack (from HasCallStack):
  error, called at libraries/base/GHC/Event/Thread.hs:290:13 in base:GHC.Event.Thread
```

### Nguyên nhân

`Network.Wai.Handler.Warp.run` dùng **event manager / timer manager** của GHC RTS.
Các manager này chỉ tồn tại trong **threaded RTS**. Nếu executable được link bằng
*vanilla* (non-threaded) RTS thì `getSystemTimerManager` gọi `error` → crash.

Mặc định `cabal` **không** bật `-threaded`; phải khai báo trong file `.cabal`.

### Cách sửa

Thêm `ghc-options` vào stanza `executable mini-brig` trong `mini-brig.cabal`:

```cabal
executable mini-brig
  import:           warnings
  main-is:          Main.hs

  -- -threaded         : link threaded RTS. Warp's network/timer event manager
  --                     cần nó, nếu không sẽ crash "TimerManager requires
  --                     linking against the threaded runtime".
  -- -rtsopts          : cho phép truyền +RTS option ở command line.
  -- -with-rtsopts=-N  : mặc định dùng tất cả core.
  ghc-options:      -threaded -rtsopts -with-rtsopts=-N
  ...
```

Rồi `cabal-fmt --inplace mini-brig.cabal` (theo quy ước dự án).

| Flag | Ý nghĩa |
|------|---------|
| `-threaded` | Link threaded RTS — **bắt buộc cho Warp** |
| `-rtsopts` | Cho phép truyền `+RTS ... -RTS` khi chạy |
| `-with-rtsopts=-N` | Mặc định dùng số core = số CPU |

---

## 5. ⚠️ Bẫy phụ: incremental build không relink với `-threaded`

Sau khi thêm `-threaded`, `cabal build exe:mini-brig` báo:

```
mini-brig-0.1.0.0 (exe:mini-brig) (configuration changed)
... Building ...
```

Nhìn như đã rebuild. **Nhưng binary vẫn là vanilla RTS** — server vẫn crash y hệt.

### Cách kiểm chứng RTS way

Mọi binary GHC đều trả lời `+RTS --info`. Field `"RTS way"` cho biết link kiểu gì:

```bash
BIN=$(cabal list-bin exe:mini-brig)
"$BIN" +RTS --info | grep "RTS way"
```

| Giá trị | Nghĩa |
|---------|-------|
| `rts_v`   | **vanilla** (non-threaded) — Warp sẽ crash |
| `rts_thr` | **threaded** — OK |

Sau khi thêm `-threaded`, kiểm tra vẫn ra `rts_v`. `touch app/Main.hs` rồi build
lại → cabal vẫn báo "Up to date" (cabal so sánh theo nội dung, không theo mtime),
RTS way vẫn `rts_v`.

### Giải pháp: `cabal clean`

```bash
cabal clean
cabal build exe:mini-brig
"$(cabal list-bin exe:mini-brig)" +RTS --info | grep "RTS way"
# → ("RTS way", "rts_thr")   ✅
```

> **Bài học:** thay đổi *link-time options* (như `-threaded`) đôi khi không kích
> hoạt relink trong build incremental của cabal. Khi binary "đáng lẽ phải khác mà
> vẫn y nguyên", hãy `cabal clean` rồi build lại, và xác nhận bằng
> `+RTS --info | grep "RTS way"`.

---

## 6. Chạy server & gọi curl

```bash
BIN=$(cabal list-bin exe:mini-brig)
"$BIN"          # in "mini-brig listening on port 8080", lắng nghe :8080
```

API (định nghĩa ở `src/API/Routes.hs`):

```haskell
type UserAPI =
       "register" :> ReqBody '[JSON] NewUser      :> Post '[JSON] UserProfile
  :<|> "login"    :> ReqBody '[JSON] LoginRequest :> Post '[JSON] TokenResponse
  :<|> "users"    :> Capture "uid" UserId         :> Get  '[JSON] UserProfile
```

### Các lệnh curl và kết quả

```bash
# 1) POST /register → 200
curl -X POST localhost:8080/register -H 'Content-Type: application/json' \
  -d '{"newUserEmail":"alice@example.com","newUsername":"alice","newUserHandle":"alice_h"}'
# {"userEmail":"stub@example.com","userHandle":null,
#  "userId":"00000000-0000-0000-0000-000000000000","userName":"User stub"}

# 2) POST /login → 200
curl -X POST localhost:8080/login -H 'Content-Type: application/json' \
  -d '{"loginEmail":"alice@example.com","loginPassword":"secret"}'
# {"token":"stub-token","tokenUserId":"00000000-0000-0000-0000-000000000000"}

# 3) GET /users/{uuid hợp lệ} → 200
curl localhost:8080/users/00000000-0000-0000-0000-000000000000
# (stub user, giống /register)

# 4) GET /users/not-a-uuid → 400   ← instance FromHttpApiData UserId hoạt động
curl localhost:8080/users/not-a-uuid
# invalid UUID

# 5) POST /register với JSON sai → 400   ← aeson FromJSON báo lỗi
curl -X POST localhost:8080/register -H 'Content-Type: application/json' -d '{"bad":true}'
# Error in $: parsing Types.NewUser(NewUser) failed, key "newUserEmail" not found
```

### Nhận xét

- Handler hiện **trả stub cố định** (`stubUser`, `"stub-token"`) — xem
  `app/Main.hs`. Chưa có business logic / DB; nhưng:
  - **Routing** đúng (3 endpoint phân biệt method + path).
  - **JSON serialize/deserialize** đúng (aeson, derive Generic).
  - **Parse UUID từ URL** đúng — `Capture "uid" UserId` dùng instance
    `FromHttpApiData UserId` (xem [serve-capture-fromhttpapidata.md](serve-capture-fromhttpapidata.md)),
    UUID sai → tự động 400 "invalid UUID".
  - **Validation body** đúng — JSON thiếu field → 400 với thông báo của aeson.

---

## 7. Checklist tái lập nhanh

```bash
# format / lint
ormolu --mode check $(find app src test -name '*.hs')
hlint app src test
cabal-fmt --check mini-brig.cabal

# build / test
cabal build all
cabal test

# chạy server (nhớ exe: để khỏi nhập nhằng với lib:)
cabal run exe:mini-brig
# nếu crash "TimerManager requires threaded runtime":
#   → đảm bảo ghc-options có -threaded trong executable stanza
#   → cabal clean && cabal build exe:mini-brig
#   → kiểm: "$(cabal list-bin exe:mini-brig)" +RTS --info | grep "RTS way"  # rts_thr

# smoke test
curl -X POST localhost:8080/register -H 'Content-Type: application/json' \
  -d '{"newUserEmail":"a@b.com","newUsername":"a","newUserHandle":null}'
```

---

## 8. Liên kết

- [[session-log]] — nhật ký toàn bộ các session
- [[serve-capture-fromhttpapidata]] — vì sao `Capture` cần `FromHttpApiData`, cách parse UUID → UserId
- [[mini-brig-roadmap]] — kế hoạch phát triển mini-brig
- [[haskell-debug-guide]] — công cụ debug Haskell
- [[cabal-rts-glossary]] — thuật ngữ `-threaded`, RTS way, incremental build
- [[http-web-glossary]] — HTTP status codes, methods, Warp, WAI
