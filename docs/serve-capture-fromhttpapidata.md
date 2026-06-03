# serve, Capture & FromHttpApiData

> Tóm tắt một lần gỡ lỗi thực tế: vì sao `serve` báo lỗi, tại sao route
> `Capture "uid" UserId` lại đòi instance `FromHttpApiData`, và bộ ví dụ chạy
> trong `cabal repl` để hiểu sâu cơ chế.
>
> Liên quan: `app/Main.hs` (gọi `serve`), `src/API/Routes.hs` (định nghĩa route),
> `src/Types.hs` (instance `FromHttpApiData UserId`).

---

## 1. Lỗi ban đầu: báo ở `serve` nhưng gốc rễ ở `UserId`

Khi build lần đầu, GHC báo lỗi ngay tại dòng `run 8080 (serve userAPI server)`:

```
app/Main.hs:24:13: error: [GHC-39999]
    • No instance for ‘FromHttpApiData UserId’
        arising from a use of ‘serve’
```

Điều dễ gây nhầm: `serve userAPI server` viết **đúng** rồi (`userAPI :: Proxy UserAPI`).
Lỗi không nằm ở bản thân `serve`, mà ở chỗ thiếu một instance cho kiểu `UserId`.

### Vì sao lỗi lại "đổ" về `serve`?

```haskell
serve :: HasServer api '[] => Proxy api -> Server api -> Application
```

Khi GHC giải ràng buộc `HasServer UserAPI '[]`, nó **bung API ra từng endpoint**.
Tới endpoint có `Capture "uid" UserId`, nó sinh ra yêu cầu `FromHttpApiData UserId`.
Không tìm thấy instance → ràng buộc `HasServer` không thoả → GHC gắn lỗi vào **chỗ
ráp toàn bộ API**, tức là `serve`, dù nguyên nhân thật nằm ở định nghĩa kiểu `UserId`.

> **Bài học:** với Servant, lỗi thường hiện ở `serve` nhưng nguyên nhân nằm ở
> một kiểu được dùng trong route. Đọc dòng `No instance for ...` để biết kiểu nào
> và class nào đang thiếu.

---

## 2. Tại sao `Capture "uid" UserId` cần `FromHttpApiData`

Route trong `src/API/Routes.hs`:

```haskell
"users" :> Capture "uid" UserId :> Get '[JSON] UserProfile
```

**URL chỉ là text.** Khi client gọi `GET /users/550e8400-...`, thứ Servant nhận được
từ đường dẫn chỉ là một chuỗi `Text`: `"550e8400-..."`. Nhưng handler lại đòi một
`UserId`:

```haskell
handleGetUser :: UserId -> Handler UserProfile
```

Giữa hai đầu phải có bước **parse `Text` → `UserId`**. Servant không tự đoán được cách
parse cho mọi kiểu, nên nó "hỏi" qua typeclass:

```haskell
class FromHttpApiData a where
  parseUrlPiece :: Text -> Either Text a   -- text đoạn URL → a (hoặc lỗi)
```

Ràng buộc này được ép ra từ chính instance `HasServer` của `Capture` (rút gọn):

```haskell
instance (FromHttpApiData a, HasServer api context)
  => HasServer (Capture sym a :> api) context where
  route ... = ... case parseUrlPiece pathSegment of
                    Left err -> ... trả về 400 Bad Request
                    Right a  -> ... truyền a vào handler
```

Để ý `FromHttpApiData a` ở vế trái `=>`. Khi `a = UserId`, GHC bắt buộc phải tìm thấy
`FromHttpApiData UserId`. Nếu parse thất bại (`Left`), Servant tự trả **400** — handler
không bao giờ bị gọi với dữ liệu rác.

### Đúng nguồn thì đúng typeclass

| Thành phần route | Dữ liệu đến từ | Typeclass yêu cầu |
|---|---|---|
| `Capture "uid" UserId` | một đoạn **path** trong URL (Text) | `FromHttpApiData` |
| `QueryParam "q" Text` | **query string** `?q=...` (Text) | `FromHttpApiData` |
| `ReqBody '[JSON] NewUser` | **body** dạng JSON | `FromJSON` |

Đây là lý do `NewUser` chỉ cần `FromJSON`, còn `UserId` (dùng trong `Capture`) cần
`FromHttpApiData`. Khác nguồn → khác cách parse → khác typeclass.

---

## 3. Hai cách thêm instance

### Cách A — `deriving newtype` (gọn, mượn nguyên instance của UUID)

```haskell
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}

newtype UserId = UserId UUID
  deriving stock (Show, Eq, Generic)
  deriving anyclass (FromJSON, ToJSON)
  deriving newtype (FromHttpApiData)
```

> **Lưu ý quan trọng:** khi file đã bật `DeriveAnyClass`, phải dùng
> `DerivingStrategies` và ghi rõ strategy (`stock` / `newtype` / `anyclass`) cho
> **mọi** dòng `deriving` của newtype. Nếu không, GHC sẽ đoán nhầm strategy:
> - Để mặc định → chọn *anyclass* cho `FromHttpApiData` → sinh **instance rỗng** →
>   lỗi `missing-methods` (class này không có default cho `parseUrlPiece`).
> - Bật cả `DeriveAnyClass` lẫn `GeneralizedNewtypeDeriving` mà không ghi strategy →
>   lỗi `deriving-defaults` (GHC không biết chọn cái nào).
>
> Dự án bật `-Werror` nên mọi cảnh báo này đều làm vỡ build.

### Cách B — viết instance thủ công (kiểm soát hoàn toàn)

```haskell
{-# LANGUAGE InstanceSigs #-}

import Web.HttpApiData (FromHttpApiData (parseUrlPiece))

instance FromHttpApiData UserId where
  parseUrlPiece :: Text -> Either Text UserId
  parseUrlPiece t = UserId <$> parseUrlPiece t
```

Giải thích vế phải: `parseUrlPiece t` dùng instance của `UUID` (vì `UserId` bọc `UUID`),
cho ra `Either Text UUID`; `UserId <$>` map qua `Either` để bọc thành `UserId`. Nhánh
`Left` (lỗi) được giữ nguyên. Không cần định nghĩa `parseQueryParam` vì class đã có
default `parseQueryParam = parseUrlPiece`.

| | Cách A: `deriving newtype` | Cách B: viết tay |
|---|---|---|
| Code | 1 dòng, compiler sinh | tự viết thân hàm |
| Extension | `DerivingStrategies` + `GeneralizedNewtypeDeriving` | `InstanceSigs` (tuỳ chọn, để ghi chữ ký) |
| Khi nào dùng | muốn **y hệt** logic của `UUID` | cần **logic riêng**: validate, normalize, đổi thông báo lỗi |

> **Quy tắc:** một typeclass cho một kiểu — hoặc derive, hoặc viết tay, **không được
> cả hai**. Để cả hai sẽ gặp lỗi `Duplicate instance declarations`. Khi chuyển từ
> cách này sang cách kia, nhớ gỡ phần cũ ra.

---

## 4. Ví dụ trong `cabal repl`

### 4A. `FromHttpApiData` parse trực tiếp

```
cabal repl mini-brig
```

```haskell
:set -XOverloadedStrings
import Web.HttpApiData
import Data.Text (Text)
import Data.UUID (UUID)
import Types
```

`parseUrlPiece :: Text -> Either Text a` — `Right` = thành công, `Left` = mang thông báo lỗi:

```haskell
parseUrlPiece "42"   :: Either Text Int    -- Right 42
parseUrlPiece "abc"  :: Either Text Int    -- Left "could not parse: `abc' (input does not start with a digit)"
parseUrlPiece "true" :: Either Text Bool   -- Right True

-- UUID: instance có sẵn trong thư viện
parseUrlPiece "550e8400-e29b-41d4-a716-446655440000" :: Either Text UUID   -- Right 550e8400-...
parseUrlPiece "khong-phai-uuid"                       :: Either Text UUID   -- Left "invalid UUID"

-- UserId: instance tự viết trong Types.hs — mượn parser của UUID rồi bọc UserId
parseUrlPiece "550e8400-e29b-41d4-a716-446655440000" :: Either Text UserId  -- Right (UserId 550e8400-...)
parseUrlPiece "rac"                                   :: Either Text UserId  -- Left "invalid UUID"

-- parseQueryParam dùng chung default = parseUrlPiece
parseQueryParam "550e8400-e29b-41d4-a716-446655440000" :: Either Text UserId -- Right (UserId 550e8400-...)
```

**Cốt lõi:** instance `FromHttpApiData UserId` chỉ làm một việc — gọi parser của `UUID`
rồi bọc lại bằng `UserId`. Lỗi `"invalid UUID"` được giữ nguyên từ `UUID` lên `UserId`.
Đây chính là hàm Servant gọi phía sau mỗi `Capture`.

### 4B. `Capture` chạy end-to-end (in-process, không cần socket)

Cách chuẩn để test một route Servant mà không phải mở cổng mạng: dựng `Application`
rồi bơm request thẳng vào bằng `Network.Wai.Test`. Nạp tạm `wai`/`wai-extra` cho repl
(không cần sửa `.cabal`):

```
cabal repl --build-depends wai,wai-extra mini-brig
```

```haskell
:set -XOverloadedStrings -XTypeOperators -XDataKinds
import Network.Wai.Test
import Network.Wai (Application)
import Servant
import Data.UUID (nil)
import API.Routes (UserAPI, userAPI)
import Types

-- handler stub giống app/Main.hs
let stub = User (UserId nil) (Email "stub@example.com") "User stub" Nothing
let server = (\_ -> pure stub) :<|> (\_ -> pure (TokenResponse "tok" (UserId nil))) :<|> (\_ -> pure stub) :: Server UserAPI
let app    = serve userAPI server :: Application

-- bơm 1 GET request, đọc status code trả về
let hit p = runSession (fmap simpleStatus (request (setPath defaultRequest p))) app
```

Kết quả thật:

| Lệnh | Status | Ý nghĩa |
|---|---|---|
| `hit "/users/550e8400-e29b-41d4-a716-446655440000"` | **200 OK** | `Capture` parse `uid` thành `UserId` OK → handler chạy |
| `hit "/users/rac"` | **400 Bad Request** | `parseUrlPiece` trả `Left` → Servant trả 400, **handler không chạy** |
| `hit "/users"` | **404 Not Found** | thiếu đoạn `:uid` → không khớp route |
| `hit "/khong-co"` | **404 Not Found** | đường dẫn lạ → không khớp route |

---

## 5. Hai bài học rút ra

1. **`Capture` = `parseUrlPiece` chạy phía sau.** So sánh 4A và 4B: input `"rac"` ở 4A
   cho `Left "invalid UUID"`; đúng input đó ở 4B cho **400**. Cái `Left` đó chính là
   thứ Servant biến thành 400 — handler luôn nhận `UserId` sạch, không bao giờ thấy
   text rác.

2. **400 vs 404 khác nhau:**
   - Sai *kiểu dữ liệu* trong path (`/users/rac`) → **400** (route khớp nhưng parse hỏng).
   - Sai *hình dạng* path (`/users`, `/khong-co`) → **404** (không route nào khớp).

   Đây chính là lý do `Capture` cần `FromHttpApiData`: để phân biệt "đúng route nhưng
   dữ liệu sai" và sinh đúng mã 400.

> **Ghi chú môi trường:** demo gọi server bằng `curl` qua loopback có thể bị một số
> sandbox chặn (reset kết nối). Cách test in-process ở mục 4B không cần socket nên
> luôn chạy được, và cũng là cách test Servant được khuyến nghị.
