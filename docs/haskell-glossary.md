# Haskell / Servant — Thuật ngữ tra cứu

> Sổ tay thuật ngữ tích lũy trong quá trình làm mini-brig. Bổ sung dần khi gặp khái niệm mới.
>
> Quy ước: mọi khẳng định về hành vi code nên được kiểm chứng bằng `cabal repl` trước khi ghi vào đây.

---

## 1. Ba tầng của Haskell (value / type / kind)

| Thuật ngữ | Định nghĩa | Ví dụ |
|-----------|-----------|-------|
| **Value (giá trị)** | Dữ liệu chạy lúc runtime. Sống ở **term level**. | `5`, `"hello"`, `[1,2,3]` |
| **Type (kiểu)** | Nhãn mô tả giá trị, kiểm tra lúc compile-time. Sống ở **type level**. | `Int`, `String`, `[Int]` |
| **Kind** | "Kiểu của kiểu" — phân loại bản thân các type. Sống ở **kind level**. | `Int :: Type` (còn viết `*`) |

Ba tầng xếp chồng: `value : type : kind`. Ví dụ `5 : Int : Type`.

---

## 2. Promotion & DataKinds

| Thuật ngữ | Định nghĩa |
|-----------|-----------|
| **Promotion (nâng tầng)** | Đưa một thứ ở tầng dưới lên tầng trên: **data constructor → type**, và **type → kind**. Bật bằng pragma `DataKinds`. |
| **Promotion tick** | Dấu nháy đơn `'` đứng trước, báo "cái này đang nói ở tầng type". Ví dụ `'True`, `'[JSON]`. |
| **Type-level list** | Danh sách ở tầng type, viết `'[a, b, ...]`. Servant dùng `'[JSON]` cho danh sách content-type. |
| **Type-level string** | Chuỗi ở tầng type, có kind đặc biệt là **`Symbol`** (GHC cung cấp). Servant dùng làm **path segment**, ví dụ `"register"` → `/register`. |
| **`Symbol`** | Kind dành riêng cho chuỗi ở tầng type. |
| **Type-level programming** | Viết logic ngay trên tầng type để compiler kiểm tra trước khi chạy. Servant API là một ví dụ. |

---

## 3. Type operators & TypeOperators

| Thuật ngữ | Định nghĩa |
|-----------|-----------|
| **Operator** | Tên gồm ký hiệu (`+`, `>>=`, `:>`), dùng **infix** (đặt giữa hai toán hạng). |
| **Type operator** | Operator dùng làm **tên của type**. Cần pragma `TypeOperators`. |
| **`:>`** | Type operator của Servant, đọc "rồi tới" — nối các thành phần của một route. |
| **`:<|>`** | Type operator của Servant, đọc "hoặc" — gộp nhiều endpoint thành một API. |
| **Type alias / type synonym** | Đặt tên cho một biểu thức type dài để tái sử dụng. Ví dụ `type UserAPI = ...`. |

---

## 4. Deriving & Generics (dùng trong Types.hs)

| Thuật ngữ | Định nghĩa |
|-----------|-----------|
| **Typeclass** | Tập hợp hành vi (method) mà nhiều kiểu có thể implement. Ví dụ `Show`, `Eq`, `ToJSON`. |
| **`Generic`** | Typeclass mô tả "cấu trúc tổng quát" (field, constructor) của một kiểu dưới dạng compiler đọc được. Nền tảng cho **generic programming**. |
| **`DeriveGeneric`** | Pragma cho phép `deriving Generic`. |
| **`DeriveAnyClass`** | Pragma cho phép `deriving` bất kỳ class nào có **default method** (không phải viết thân instance). Nhờ nó viết được `deriving (FromJSON, ToJSON)`. |
| **Default method** | Cài đặt mặc định của một method trong class; lớp con có thể dùng luôn mà không override. |
| **`GeneralizedNewtypeDeriving`** | Pragma cho phép newtype **mượn thẳng** instance của kiểu bên trong (`deriving newtype`). |
| **`DerivingStrategies`** | Pragma cho phép chỉ rõ chiến lược derive: `stock`, `newtype`, `anyclass`, `via`. |

---

## 5. Newtype & JSON serialization (Aeson)

| Thuật ngữ | Định nghĩa |
|-----------|-----------|
| **`newtype`** | Bọc đúng **một** giá trị, không có overhead runtime. Ví dụ `newtype Email = Email Text`. |
| **Positional field** | Field **không tên**: `newtype UserId = UserId UUID`. |
| **Record field** | Field **có tên**: `newtype UserId = UserId { unUserId :: UUID }`. |
| **Unary record** | Record có **đúng một** field có tên. |
| **`unwrapUnaryRecords`** | Option của Aeson generic encoding. Mặc định `False` ⇒ unary record vẫn bị **bọc thành object**. |

### Quy tắc serialize đã kiểm chứng bằng repl

| Kiểu | Khai báo | JSON sinh ra |
|------|----------|-------------|
| Positional newtype | `newtype UserId = UserId UUID` | `"…uuid…"` — **trong suốt** |
| Record (unary) newtype | `newtype UserId = UserId { unUserId :: UUID }` | `{"unUserId":"…uuid…"}` — **bị bọc** |
| Record data | `data User = User { userId :: …, userEmail :: … }` | `{"userId":…,"userEmail":…}` — object đúng như mong đợi |

> Kết luận thực dụng: với newtype, dùng **positional field** nếu muốn JSON trong suốt.
> Nếu phải dùng record field mà vẫn muốn trong suốt → `deriving newtype` (cần `GeneralizedNewtypeDeriving`).

---

## 6. Proxy & lập trình tầng type (Symbol, Nat, GADTs)

| Thuật ngữ | Định nghĩa | Ví dụ |
|-----------|-----------|-------|
| **Phantom type (kiểu ma)** | Tham số type **không xuất hiện** ở vế phải định nghĩa, chỉ sống ở tầng type. | `data Proxy a = Proxy` — `a` là phantom |
| **`Proxy`** | Cái "vỏ rỗng" mang theo một kiểu mà không tốn dữ liệu runtime. Dùng để **truyền kiểu cho hàm** (vì hàm chỉ nhận value, không nhận type). | `Proxy :: Proxy Int` |
| **`Symbol`** | Kind của **chuỗi** ở tầng type. `"register"` là một type có kind `Symbol`. Cần `DataKinds`. | `:kind "register"` → `Symbol` |
| **`Nat`** | Kind của **số tự nhiên** ở tầng type. `42` có thể là type có kind `Nat`. Cần `DataKinds`. | `:kind 42` → `Natural` |
| **Reflection (hạ tầng)** | Lấy lại **value runtime** từ type-level. `symbolVal`/`natVal` cần một `Proxy` để biết kiểu. | `symbolVal (Proxy :: Proxy "register")` → `"register"` |
| **`KnownSymbol` / `KnownNat`** | Ràng buộc cho biết "compiler đã biết giá trị này", nhờ đó `symbolVal`/`natVal` chạy được. | — |
| **Type erasure** | Type/kind bị **xoá** lúc chạy — không tốn chi phí runtime. Chỉ value (qua reflection) mới xuống được runtime. | — |
| **GADTs** | Cú pháp khai báo data cho phép mỗi constructor **tự quyết định type kết quả**, kể cả ghi thông tin vào tham số type. | `VNil :: Vec 'Z a` |
| **Type family** | "Hàm chạy ở tầng type": nhận type, trả về type. Cần `TypeFamilies`. | `'Z + m = m` (cộng hai `Nat`) |
| **Length-indexed vector** | Vector **ghi độ dài vào type** (`Vec n a`). Dùng để bắt lỗi độ dài ngay lúc compile (vd `safeHead` không nhận vector rỗng). | `Vec ('S ('S 'Z)) Int` = 2 phần tử |

> **Hai vai trò của Symbol/Nat** (đều ở compile time):
> 1. **Bắt lỗi lúc biên dịch** — vd gọi `safeHead` vào vector rỗng → không compile.
> 2. **Sinh hành vi runtime** — Servant *đọc* các `Symbol` (`"register"`, `"login"`) trong type `UserAPI` rồi dựng ra web server thật, qua đúng cơ chế `symbolVal`.

> **Vì sao import `Proxy (Proxy)` mà `JSON`/`Post` thì không?** `Proxy` được dùng cả như **type** (`Proxy UserAPI`) lẫn **value** (`userAPI = Proxy`), nên phải import cả data constructor. `JSON`/`Post` chỉ dùng như type nên import tên trần là đủ. Xem `src/API/Routes.hs`.

---

## Tham khảo chính thống

- GHC User's Guide — Language extensions: https://downloads.haskell.org/ghc/latest/docs/users_guide/exts/
- Servant docs (type-level DSL): https://docs.servant.dev/
- Aeson `Options` / generic encoding: https://hackage.haskell.org/package/aeson/docs/Data-Aeson.html#t:Options
- `Data.Proxy`: https://hackage.haskell.org/package/base/docs/Data-Proxy.html
- `GHC.TypeLits` (Symbol, Nat, symbolVal, natVal): https://hackage.haskell.org/package/base/docs/GHC-TypeLits.html
