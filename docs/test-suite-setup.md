# Dựng test suite cho các endpoint (hspec + hspec-wai)

> Ngày: 2026-06-04
> Mục tiêu: Viết test thật cho 3 endpoint của `UserAPI` (`/register`, `/login`,
> `/users/:uid`) thay cho test stub. Test chạy **in-process** (gọi thẳng WAI
> `Application`), không cần khởi động server trên cổng nào.

---

## 0. TL;DR

| Việc | Kết quả |
|------|---------|
| Tách `Application` ra library (`API.Server`) | để test + exe dùng chung |
| Test bằng `hspec` + `hspec-wai`, in-process | 6 test, không cần Warp |
| `cabal test` | ✅ 6/6 pass |
| ormolu / hlint / cabal-fmt | ✅ sạch |

**3 lỗi đã gặp & cách xử lý** (chi tiết ở mục 5):
1. Servant trả **415** vì request thiếu `Content-Type` → dùng `request` + header.
2. `Test.Hspec.Wai.JSON` **không expose** trong hspec-wai 0.12.0 → tự viết matcher.
3. hlint báo `TypeOperators` thừa → đổi sang `ExplicitNamespaces`.

---

## 1. Vì sao phải refactor trước khi test

Ban đầu WAI `Application` được dựng ngay trong `app/Main.hs`:

```haskell
-- app/Main.hs (cũ)
main = run 8080 (serve userAPI server)
server = handleRegister :<|> handleLogin :<|> handleGetUser
```

`app/Main.hs` thuộc **executable**, không phải library → test-suite **không import
được** `server`/`Application` từ đó. (Library chỉ expose `API.Routes`, `Types`.)

**Cách xử lý:** tách phần "implementation" vào library.

### Bước 1 — Tạo `src/API/Server.hs`

Chuyển `app :: Application`, `server`, các handler và `stubUser` vào module mới
trong `src/` (thuộc library), export `app`:

```haskell
module API.Server (app, server) where
...
app :: Application
app = serve userAPI server
```

### Bước 2 — `app/Main.hs` chỉ còn gọi `app`

```haskell
module Main where

import API.Server (app)
import Network.Wai.Handler.Warp (run)

main :: IO ()
main = do
  putStrLn "mini-brig listening on port 8080"
  run 8080 app
```

### Bước 3 — Cập nhật `.cabal`

- `library` → thêm `API.Server` vào `exposed-modules`.
- `executable` → bỏ deps không còn dùng trực tiếp (`servant-server`, `uuid`),
  giữ `base, mini-brig, warp`.
- Nhớ `cabal-fmt --inplace mini-brig.cabal` (quy ước dự án).

> **Vì sao library không cần thêm dep `wai`?** `Application` được import từ
> `Servant` (servant-server đã re-export), nên không phải khai báo `wai` riêng.

---

## 2. Vì sao test in-process (không bind cổng)

`hspec-wai` chạy `Application` qua `Network.Wai.Test` — gửi request giả lập thẳng
vào hàm `Application`, **không mở socket / cổng nào**. Lợi ích:

- Nhanh (toàn bộ 6 test ~0.001s), không lo cổng bận, không cần `-threaded`.
- Test thuần, không phụ thuộc môi trường mạng.

Khung cơ bản:

```haskell
spec :: Spec
spec = with (pure app) $ do          -- nạp Application một lần
  describe "POST /register" $ do
    it "..." $ request ... `shouldRespondWith` ...
```

---

## 3. Viết test (`test/Main.hs`)

Điểm mấu chốt khi gửi request có JSON body — **phải tự gắn header**
`Content-Type: application/json` (xem lỗi 415 ở mục 5.1):

```haskell
jsonHeaders :: [Header]
jsonHeaders = [(hContentType, "application/json")]

-- POST kèm Content-Type:
request methodPost "/register" jsonHeaders registerBody
  `shouldRespondWith` jsonBody 200 stubProfileValue
```

So khớp body bằng **matcher JSON ngữ nghĩa** tự viết (decode body → so sánh
`Value`, không phụ thuộc thứ tự key — xem lỗi 5.2):

```haskell
jsonBody :: Int -> Value -> ResponseMatcher
jsonBody status expected =
  ResponseMatcher
    { matchStatus = status,
      matchHeaders = [],                       -- bỏ qua kiểm tra Content-Type
      matchBody = MatchBody $ \_ actual ->
        if decode actual == Just expected
          then Nothing
          else Just ("expected JSON: " <> show expected <> "\nbut got: " <> show actual)
    }
```

Các case lỗi chỉ cần khớp status (literal số ⇒ `ResponseMatcher` qua `instance Num`):

```haskell
request methodPost "/register" jsonHeaders "{\"bad\":true}" `shouldRespondWith` 400
get "/users/not-a-uuid" `shouldRespondWith` 400
get "/nope"             `shouldRespondWith` 404
```

### Bảng 6 test

| describe | it | Khẳng định |
|----------|----|-----------|
| POST /register | hợp lệ | 200 + stub profile |
| POST /register | JSON sai/thiếu field | 400 |
| POST /login | hợp lệ | 200 + token |
| GET /users/:uid | UUID hợp lệ | 200 + stub profile |
| GET /users/:uid | UUID sai | 400 |
| Routing | path lạ | 404 |

### Dependencies test-suite (trong `.cabal`)

```cabal
build-depends:
  , aeson        -- Value, decode, object, (.=)
  , base
  , bytestring   -- Data.ByteString.Lazy (kiểu body)
  , hspec        -- khung test
  , hspec-wai    -- request/get/shouldRespondWith/with, ResponseMatcher, MatchBody
  , http-types   -- methodPost, hContentType, Header
  , mini-brig    -- API.Server (app)
  , text         -- Text cho các literal JSON
```

---

## 4. Chạy test

```bash
cabal test                 # build + chạy, in ra từng [✔]
cabal build mini-brig-test # chỉ build test-suite (target tên đầy đủ, không nhập nhằng)
```

Kết quả mong đợi:

```
6 examples, 0 failures
Test suite mini-brig-test: PASS
```

---

## 5. Các lỗi đã gặp & cách xử lý

### 5.1 — Servant trả 415 nếu thiếu Content-Type

**Hiện tượng:** dùng `post "/register" body` (helper của hspec-wai) thì handler
không nhận được body, trả **415 Unsupported Media Type**.

**Nguyên nhân:** `post`/`get` của hspec-wai **không** set header `Content-Type`.
Nhưng `ReqBody '[JSON]` của Servant chỉ chấp nhận khi `Content-Type:
application/json`; thiếu ⇒ 415.

**Cách xử lý:** thay `post` bằng `request` để chèn header thủ công:

```haskell
request methodPost "/register" [(hContentType, "application/json")] body
```

> Liên hệ: đây đúng là lý do khi test `curl` ta cũng phải `-H 'Content-Type:
> application/json'`.

---

### 5.2 — `Test.Hspec.Wai.JSON` không tồn tại

**Hiện tượng:** dự định dùng quasiquoter `[json|...|]`:

```
test/Main.hs:20:8: error:
    Could not find module ‘Test.Hspec.Wai.JSON’
    Perhaps you meant Test.Hspec.Wai.Util, Test.Hspec.Wai
```

**Nguyên nhân:** bản `hspec-wai-0.12.0` resolve về ở máy này **không expose**
module `Test.Hspec.Wai.JSON` (module chứa quasiquoter `[json|…|]`).

**Cách xử lý:** bỏ quasiquoter, tự viết matcher dùng `aeson`:
- Decode body trả về thành `Value` rồi so với `Value` kỳ vọng (mục 3, `jsonBody`).
- `MatchBody` lấy từ `Test.Hspec.Wai.Matcher` (module này có sẵn).

**Lợi ích phụ:** so sánh ở mức `Value` nên **không phụ thuộc thứ tự key** —
tránh luôn lỗi 5.3.

> Cách chẩn đoán: khi GHC báo "Could not find module" cho một module thư viện,
> kiểm tra module thực sự được expose bằng cách xem gợi ý "Perhaps you meant…",
> hoặc `ghc-pkg field <pkg> exposed-modules`.

---

### 5.3 — Thứ tự key JSON không cố định

**Bối cảnh:** nếu so khớp body bằng **chuỗi bytes** thì rất dễ vỡ — aeson sắp
key của record (Generic) theo thứ tự không trùng thứ tự khai báo (quan sát từ
`curl`: `userEmail, userHandle, userId, userName` = alphabet, khác thứ tự khai
báo trong `data User`).

**Cách xử lý:** so sánh ở mức `Value` (`decode actual == Just expected`). `Value`
dạng Object là map ⇒ Eq không quan tâm thứ tự key. Xây expected bằng `object [...]`:

```haskell
stubProfileValue =
  object
    [ "userId" .= nilUuid,
      "userEmail" .= ("stub@example.com" :: Text),
      "userName" .= ("User stub" :: Text),
      "userHandle" .= (Nothing :: Maybe Text)
    ]
```

> Cũng vì lý do tương tự, `matchHeaders = []` để bỏ qua so khớp Content-Type —
> Servant trả `application/json;charset=utf-8`, không cần soi chính xác ở đây.

---

### 5.4 — hlint: `TypeOperators` pragma thừa

**Hiện tượng:**

```
src/API/Server.hs:2:1-30: Warning: Unused LANGUAGE pragma
Found: {-# LANGUAGE TypeOperators #-}
Note: may require `{-# LANGUAGE ExplicitNamespaces #-}` adding to the top
```

**Nguyên nhân:** trong `API.Server` chỉ dùng **value constructor** `:<|>`
(ghép handler) — cái này không cần `TypeOperators`. Thứ thật sự cần là từ khoá
`type` trong dòng import `import Servant (type (:<|>) (..))`, vốn yêu cầu
`ExplicitNamespaces`.

**Cách xử lý:** đổi pragma:

```haskell
{-# LANGUAGE ExplicitNamespaces #-}   -- thay cho TypeOperators
{-# LANGUAGE OverloadedStrings #-}
```

(Khớp với cách `app/Main.hs` gốc đã làm.)

> Bài học: code biên dịch được **không** có nghĩa pragma là tối ưu. Luôn chạy
> `hlint` để dọn pragma/extension thừa — đặc biệt khi bật `-Werror` ở CI.

---

## 6. Checklist tái lập / mở rộng

```bash
# sau khi sửa code/test:
cabal build all                       # biên dịch lib + exe + test
cabal test                            # chạy test, kỳ vọng "N examples, 0 failures"
ormolu --mode check $(find app src test -name '*.hs')
hlint app src test
cabal-fmt --check mini-brig.cabal
```

**Thêm endpoint mới → thêm test:**
1. Khai báo route ở `API.Routes`, handler ở `API.Server`.
2. Trong `test/Main.hs` thêm một `it` trong `describe` tương ứng.
3. Body request: `request method path jsonHeaders body` (nhớ header nếu có JSON).
4. Body response: `jsonBody <status> <Value kỳ vọng>`; case lỗi chỉ cần số status.

---

## 7. Liên kết

- [session-log.md](session-log.md) — nhật ký toàn bộ các session
- [run-build-curl-threaded.md](run-build-curl-threaded.md) — chạy server + curl,
  bug `-threaded`
- [serve-capture-fromhttpapidata.md](serve-capture-fromhttpapidata.md) — vì sao
  `Capture` cần `FromHttpApiData` (liên quan test "UUID sai → 400")
