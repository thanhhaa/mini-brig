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

## 7. Build / Cabal / RTS — thuật ngữ khi build & chạy

> Các khái niệm gặp khi build, run server và sửa bug `-threaded`
> (xem [run-build-curl-threaded.md](run-build-curl-threaded.md)).

| Thuật ngữ | Định nghĩa |
|-----------|-----------|
| **Stanza** | Một **khối khai báo có tên** trong file `.cabal`. Mỗi target là một stanza: `library`, `executable mini-brig`, `test-suite mini-brig-test`, và `common warnings`. Trong stanza đặt các field như `build-depends`, `ghc-options`, `hs-source-dirs`. |
| **`common` stanza** | Stanza khai báo cấu hình dùng chung; các stanza khác kéo vào bằng `import:`. Ví dụ `common warnings` đặt `ghc-options: -Wall -Werror`, rồi mỗi target `import: warnings`. |
| **Component / target** | Một thứ build ra được: thư viện (lib), file chạy (exe), bộ test. Một package có nhiều component. Tên đầy đủ: `lib:mini-brig`, `exe:mini-brig`, `test:mini-brig-test` (dùng khi tên bị nhập nhằng). |
| **`main-is`** | Field khai báo file chứa module **entry point** (`main`) cho `executable`/`test-suite`. Ví dụ `main-is: Main.hs`. |
| **`other-modules`** | Field liệt kê **mọi module khác** (không phải `Main`) thuộc về target và cần được biên dịch. ⚠️ `import` trong code **không** tự bảo Cabal build module đó — Cabal **chỉ** build những module nằm trong `main-is` + `other-modules`. Thiếu ⇒ lỗi *"Could not find module …"* và file bị **bỏ sót khi `cabal sdist`**. Đây là module **nội bộ** (không export ra ngoài package). |
| **`exposed-modules`** | Chỉ có ở stanza `library`: module **public** mà package/target khác import được (vd `API.Server`). Khác `other-modules` (nội bộ, không export). |
| **Compile** | Dịch **từng** file `.hs` → file đối tượng `.o` (object file). Là bước theo từng module. |
| **Object file (`.o`)** | Mã máy đã dịch của một module, **chưa** ghép thành chương trình hoàn chỉnh. |
| **Link / Linking** | Bước **ghép** tất cả `.o` + các thư viện (kể cả RTS) thành một **binary** chạy được. Khác hẳn bước compile. |
| **Relink** | **Link lại** binary mà không cần compile lại module nào. Các option ảnh hưởng *lúc link* (như `-threaded`) chỉ có tác dụng sau khi relink. |
| **Build incremental** | Build **chỉ phần đã đổi**: module nào sửa thì compile lại module đó, rồi relink. Cabal dò thay đổi theo nội dung file + cấu hình. Nhanh hơn build lại từ đầu. ⚠️ **Bẫy:** đổi option *link-time* (vd `-threaded`) đôi khi **không** kích hoạt relink trong build incremental — phải `cabal clean` rồi build lại. |
| **`cabal clean`** | Xoá toàn bộ kết quả build (`dist-newstyle`) để build lại **từ đầu** — cách chắc chắn khi incremental build "kẹt". |
| **RTS (Runtime System)** | Phần code lõi GHC nhúng vào **mọi** binary Haskell: quản lý bộ nhớ (GC), lập lịch green thread, I/O manager, timer manager… Chương trình của bạn chạy *bên trên* RTS. |
| **RTS way** | "Phiên bản" RTS được link vào binary. Hai loại hay gặp: **vanilla** (`rts_v`) và **threaded** (`rts_thr`). Xem bằng `<binary> +RTS --info \| grep "RTS way"`. |
| **Binary threaded / `-threaded`** | Binary được **link với threaded RTS** (qua `ghc-options: -threaded`). Threaded RTS có scheduler đa nhân + I/O manager đầy đủ. **Warp bắt buộc** dùng nó (vì cần timer/event manager); thiếu thì crash *"the TimerManager requires linking against the threaded runtime"*. |
| **Vanilla RTS** | RTS mặc định (non-threaded), `rts_v`. Đủ cho chương trình đơn giản nhưng **không** chạy được Warp. |
| **`-rtsopts`** | Cho phép truyền tuỳ chọn RTS khi chạy: `./prog +RTS -N4 -RTS`. |
| **`-with-rtsopts=-N`** | Nhúng sẵn option RTS mặc định vào binary; `-N` = dùng tất cả core CPU. |
| **Link-time vs compile-time option** | *Compile-time* (vd `-Wall`) ảnh hưởng lúc dịch từng module. *Link-time* (vd `-threaded`) ảnh hưởng lúc ghép binary. Đây là lý do đổi `-threaded` cần **relink**, không chỉ recompile. |

> **Quy trình chẩn đoán "đổi `-threaded` mà server vẫn crash":**
> 1. `cabal build exe:mini-brig` báo *Up to date* nhưng binary chưa đổi → nghi incremental không relink.
> 2. Kiểm chứng: `"$(cabal list-bin exe:mini-brig)" +RTS --info \| grep "RTS way"`.
>    - `rts_v` = vanilla → chưa threaded (sai).
>    - `rts_thr` = threaded → đúng.
> 3. Sửa: `cabal clean && cabal build exe:mini-brig`, kiểm lại RTS way.

---

## 8. Deriving strategy chi tiết

> Mở rộng cho `DerivingStrategies` ở [mục 4](#4-deriving--generics-dùng-trong-typeshs).
> Khi bật `DeriveAnyClass`, GHC dễ "đoán nhầm" cách derive ⇒ nên ghi **rõ chiến lược**.

**Strategy (chiến lược derive)** = chỉ định GHC *sinh instance bằng cách nào*. Viết
ngay sau `deriving`:

| Strategy | Cú pháp | GHC làm gì | Dùng khi |
|----------|---------|-----------|----------|
| **stock** | `deriving stock (Show, Eq, Generic)` | Dùng bộ derive **có sẵn trong GHC** (Eq, Ord, Show, Read, Enum, Bounded, Functor, Foldable, Traversable, Generic, Data…). | Các class chuẩn cơ bản. |
| **newtype** | `deriving newtype (FromJSON, ToJSON)` | **Mượn thẳng** instance của kiểu bên trong newtype (cần `GeneralizedNewtypeDeriving`). | Muốn `UserId` (bọc `UUID`) hành xử *giống hệt* `UUID`. |
| **anyclass** | `deriving anyclass (FromJSON, ToJSON)` | Tạo instance **rỗng**, xài hết **default method** của class (cần `DeriveAnyClass`). Với Aeson, default method dựa trên `Generic`. | Class có default method dựa trên `Generic` (như Aeson). |
| **via** | `deriving (Show) via (X)` | Derive **thông qua** một kiểu khác có cùng biểu diễn runtime (cần `DerivingVia`). | Tái dùng instance của một wrapper sẵn có. |

> **Vì sao phải nói rõ strategy?** Khi bật `DeriveAnyClass`, dòng
> `deriving (FromJSON, ToJSON)` *không ghi strategy* sẽ bị GHC mặc định chọn
> **anyclass** → sinh instance rỗng. Nếu thực ra ta muốn **newtype** (mượn của
> `UUID`) thì hành vi sai mà **không báo lỗi**. Ghi `deriving newtype (...)` /
> `deriving anyclass (...)` để khỏi mơ hồ.

**Phân biệt nhanh `newtype` vs `anyclass` (hay nhầm nhất):**

| | `deriving newtype` | `deriving anyclass` |
|--|--------------------|---------------------|
| Lấy instance từ đâu | Kiểu **bên trong** newtype | **Default method** của class |
| JSON của `newtype UserId = UserId UUID` | `"…uuid…"` (giống UUID) | `{...}` qua Generic của UserId |
| Pragma cần | `GeneralizedNewtypeDeriving` | `DeriveAnyClass` |

---

## Tham khảo chính thống

- GHC User's Guide — Language extensions: https://downloads.haskell.org/ghc/latest/docs/users_guide/exts/
- Servant docs (type-level DSL): https://docs.servant.dev/
- Aeson `Options` / generic encoding: https://hackage.haskell.org/package/aeson/docs/Data-Aeson.html#t:Options
- `Data.Proxy`: https://hackage.haskell.org/package/base/docs/Data-Proxy.html
- `GHC.TypeLits` (Symbol, Nat, symbolVal, natVal): https://hackage.haskell.org/package/base/docs/GHC-TypeLits.html
- Cabal — package description / stanzas & fields: https://cabal.readthedocs.io/en/stable/cabal-package.html
- GHC User's Guide — `-threaded`, `-rtsopts`, RTS options: https://downloads.haskell.org/ghc/latest/docs/users_guide/phases.html#options-affecting-linking
- GHC User's Guide — Deriving strategies: https://downloads.haskell.org/ghc/latest/docs/users_guide/exts/deriving_strategies.html
