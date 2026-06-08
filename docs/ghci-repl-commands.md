# GHCi / cabal repl — Command Reference

## Khởi động

```bash
cabal repl          # load toàn bộ project (lib + app)
cabal repl lib:mini-brig  # chỉ load library
```

---

## Xem kiểu & kind

| Lệnh | Dùng khi | Ví dụ |
|---|---|---|
| `:type <expr>` | xem kiểu của một expression | `:type encode (Email "a")` |
| `:kind <type>` | xem kind của một type | `:kind Maybe` |
| `:kind! <type>` | xem kind và **expand** type family/alias | `:kind! Rep Email` |

### `:kind!` với Generic

```haskell
import GHC.Generics (Rep)
import Types (Email, User, UserProfile)

:kind! Rep Email        -- xem cấu trúc Generic của newtype
:kind! Rep User         -- xem cấu trúc Generic của data record
:kind! Rep UserProfile  -- giống Rep User vì UserProfile = type alias
```

Kết quả trả về cây `M1`:
- `M1 D` — Datatype metadata (tên, module, có phải newtype không)
- `M1 C` — Constructor metadata (tên, prefix/infix, có record syntax không)
- `M1 S` — Selector/field metadata (`Just "fieldName"` hoặc `Nothing`)
- `K1 R <Type>` — lá: kiểu thật của field
- `:*:` — ghép nhiều field (product)
- `:+:` — phân nhánh nhiều constructor (sum)

---

## Xem thông tin instance

| Lệnh | Dùng khi | Ví dụ |
|---|---|---|
| `:info <name>` | xem definition + tất cả instances | `:info Email` |
| `:info <typeclass>` | xem các method + instances đã có | `:info FromJSON` |

```haskell
:info Value    -- thấy tất cả constructor: Object, Array, String, Number, Bool, Null
:info Result   -- thấy: data Result a = Error String | Success a
```

---

## Bật extension trong repl

```haskell
:set -XOverloadedStrings    -- cho phép "..." là Text/ByteString
:set -XDeriveGeneric        -- bật DeriveGeneric
:set -XDeriveAnyClass       -- bật DeriveAnyClass
:set -XNoDeriveAnyClass     -- tắt lại
```

---

## Test FromJSON / ToJSON

```haskell
import Data.Aeson
import Types (Email, User)

-- encode: Haskell → ByteString JSON
encode (Email "alice@example.com")
-- "\"alice@example.com\""

-- decode: ByteString JSON → Maybe a
decode "\"alice@example.com\"" :: Maybe Email
-- Just (Email "alice@example.com")

-- fromJSON: Value → Result a  (thấy được thông báo lỗi)
fromJSON (String "alice@example.com") :: Result Email
-- Success (Email "alice@example.com")

fromJSON (Number 42) :: Result Email
-- Error "parsing Text failed, expected String, but encountered Number"

-- toJSON: Haskell → Value  (dùng để tạo Value cho fromJSON)
toJSON ("alice@example.com" :: String)
-- String "alice@example.com"
```

---

## Multiline input

```haskell
:{
newtype Foo = Foo Text
  deriving (Show, Eq)
:}
```

---

## Phân biệt `String "..."` vs `"..." :: String`

| | `String "..."` | `"..." :: String` |
|---|---|---|
| `String` là | **constructor** của `Value` (Aeson) | **kiểu** `[Char]` (Haskell Prelude) |
| Kết quả | `Value` | `[Char]` |
| Dùng khi | cần tạo `Value` để pass vào `fromJSON` | cần chỉ rõ literal là `[Char]` chứ không phải `Text` |

---

## Reload sau khi sửa file

```haskell
:reload   -- hoặc :r
```

---

## Liên kết

- [[haskell-glossary]] — thuật ngữ Haskell: typeclass, deriving, Generic, Aeson
- [[haskell-debug-guide]] — debug với GHCi `:break`/`:step`, ghcid, Debug.Trace
- [[test-suite-setup]] — test các instance `FromJSON`/`ToJSON` thực tế
