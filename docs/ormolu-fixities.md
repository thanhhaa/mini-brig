# Ormolu fixities & module reexports

> EN: Documentation for the project's `.ormolu` file. The `.ormolu` file itself can only
> contain `infix`/`infixl`/`infixr` and `module ... exports ...` lines — ormolu 0.7.7.0
> does **not** accept `--` comments inside it. So every entry's explanation lives here
> instead, keyed by the operator.
>
> VI: Tài liệu cho file `.ormolu` của project. Bản thân file `.ormolu` chỉ được chứa các
> dòng `infix`/`infixl`/`infixr` và `module ... exports ...` — ormolu 0.7.7.0 **không**
> chấp nhận comment `--` bên trong. Vì vậy mọi phần giải thích được để ở đây, tra theo
> tên operator.

Khi chỉnh fixity, sửa **cả hai**: dòng khai báo trong `.ormolu` và mục tương ứng ở đây.

---

## Module reexport

### `module Imports exports Prelude`

- **EN:** Tell ormolu that the `Imports` module acts as this project's Prelude.
  wire-server pattern: `libs/imports/src/Imports.hs` re-exports Prelude plus common extras
  (`Data.Text`, `Data.Map`, etc.). Without this line, ormolu treats the standard Prelude as
  the implicit import and may misformat qualified names.
- **VI:** Khai báo cho ormolu biết module `Imports` đóng vai trò Prelude của project.
  wire-server dùng pattern này: `libs/imports/src/Imports.hs` re-export Prelude cộng thêm
  các thứ dùng chung. Không có dòng này, ormolu sẽ format sai các tên qualified.

---

## schema-profunctor (`libs/schema-profunctor/src/Data/Schema.hs`)

### `infixl 9 .=`

- **EN:** `(.=) :: Profunctor p => (a -> a') -> p a' b -> p a b`. Alias for `lmap`. Projects
  a field out of a record when building a bidirectional JSON codec (encode + decode share one
  schema definition). Example: `userId .= field "id" schema`. Declared so ormolu knows
  precedence = 9 and avoids inserting unnecessary parentheses in chains like `a .= b .= c`.
- **VI:** Alias của `lmap`. Dùng để "chiếu" một field ra khỏi record khi xây dựng codec JSON
  hai chiều. Khai báo ở đây để ormolu format đúng chuỗi `.= .=` mà không thêm ngoặc thừa.

### `infixl 9 .:`

- **EN:** `(.:)` from Aeson — parse a required key from a JSON object.
  Example: `User <$> obj .: "id" <*> obj .: "email"`. Declared so ormolu does not reformat
  multi-key expressions into hard-to-read layouts.
- **VI:** `(.:)` đến từ Aeson — parse một key bắt buộc từ JSON object. Khai báo ở đây để
  ormolu không reformat biểu thức nhiều key thành dạng khó đọc.

---

## lens package

### `infixr 4 ?~`

- **EN:** `(?~) :: ASetter s t a (Maybe b) -> b -> s -> t`. Set an optional (`Maybe`) field
  inside a lens setter chain. Example: `claimsSet & claimExp ?~ NumericDate expiry`.
- **VI:** Set một field kiểu `Maybe` bên trong chuỗi lens.
  Ví dụ: `claimsSet & claimExp ?~ NumericDate expiry`.

### `infixr 4 .~`

- **EN:** `(.~) :: ASetter s t a b -> b -> s -> t`. Set a field via a lens.
  Example: `config & port .~ 8080`.
- **VI:** Set một field qua lens. Ví dụ: `config & port .~ 8080`.

### `infixl 1 &`

- **EN:** `(&) :: a -> (a -> b) -> b`. Reverse function application. Lets you write lens chains
  left-to-right: `record & field1 .~ v1 & field2 .~ v2`.
- **VI:** Áp dụng hàm theo thứ tự ngược. Cho phép viết chuỗi lens từ trái sang phải, dễ đọc
  hơn: `record & field1 .~ v1 & field2 .~ v2`.

---

## Bilge.Assert (`libs/bilge/src/Bilge/Assert.hs`)

### `infix 4 ===`

- **EN:** `(===) :: (Eq a, Show a) => (Response -> a) -> (Response -> a) -> Assertions ()`.
  Assert that two response-extractors produce the same value.
  Example: `statusCode === const 200`.
- **VI:** Assert hai hàm trích xuất từ `Response` cho ra giá trị bằng nhau.
  Ví dụ: `statusCode === const 200`.

### `infix 4 =/=`

- **EN:** `(=/=) :: (Eq a, Show a) => (Response -> a) -> (Response -> a) -> Assertions ()`.
  Assert that two response-extractors produce different values.
- **VI:** Assert hai hàm trích xuất từ `Response` cho ra giá trị khác nhau.

### `infixr 3 !!!`

- **EN:** `(!!!) :: (MonadIO m, MonadCatch m) => m Response -> Assertions () -> m ()`.
  Run assertions against a response, discarding the response on success.
  Example: `get "/users/self" !!! statusCode === const 200`.
- **VI:** Chạy assertions trên response, bỏ qua response sau khi xong.
  Ví dụ: `get "/users/self" !!! statusCode === const 200`.

### `infixr 3 <!!`

- **EN:** `(<!!) :: (MonadIO m, MonadCatch m) => m Response -> Assertions () -> m Response`.
  Like `(!!!)` but returns the response for further inspection.
  Example: `r <- get "/users/self" <!! statusCode === const 200`.
- **VI:** Giống `(!!!)` nhưng trả về response để dùng tiếp.
  Ví dụ: `r <- get "/users/self" <!! statusCode === const 200`.

---

## Testlib.App (`integration/test/Testlib/App.hs`)

### `infixr 3 &&~`

- **EN:** `(&&~) :: App Bool -> App Bool -> App Bool`. Short-circuit AND inside the
  integration-test `App` monad.
- **VI:** Short-circuit AND bên trong monad `App` của integration test.

### `infixr 2 ||~`

- **EN:** `(||~) :: App Bool -> App Bool -> App Bool`. Short-circuit OR inside the
  integration-test `App` monad.
- **VI:** Short-circuit OR bên trong monad `App` của integration test.

---

## schema-profunctor fmap lifting

### `infix 4 <$$>` / `infix 4 <$$$>`

- **EN:** `(<$$>)` and `(<$$$>)` are `fmap` lifted one or two layers deeper into a
  profunctor/functor stack, used in schema codec definitions. Declared so ormolu formats
  multi-line schema expressions consistently.
- **VI:** `fmap` được nâng (lift) thêm một hoặc hai lớp vào stack profunctor/functor, dùng
  khi định nghĩa codec schema. Khai báo để ormolu format nhất quán các biểu thức schema
  nhiều dòng.

---

## Testlib.HTTP (`integration/test/Testlib/HTTP.hs`)

### ``infixl 1 `bindResponse` ``

- **EN:** `bindResponse :: App Response -> (Response -> App a) -> App a`. Monadic bind
  specialised to HTTP responses in the integration-test `App` monad. Used instead of `(>>=)`
  when handling responses:
  ```haskell
  getUser uid `bindResponse` \resp -> do
    statusCode resp === 200
  ```
- **VI:** Monadic bind chuyên dụng cho HTTP response trong monad `App` của integration test.
  Dùng thay cho `>>=` khi xử lý response:
  ```haskell
  getUser uid `bindResponse` \resp -> do
    statusCode resp === 200
  ```

---

## Liên kết

- [[run-build-curl-threaded]] — quy ước chạy ormolu + cabal-fmt trong project
- [[haskell-glossary]] — type operators (`:<|>`, `:>`), TypeOperators pragma
