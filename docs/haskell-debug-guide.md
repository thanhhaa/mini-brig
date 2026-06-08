# Haskell Debug Guide

> Không cần cài thêm công cụ — `cabal repl` và `Debug.Trace` đủ cho 90% trường hợp.
>
> `haskell-debugger` (hdb) từ well-typed yêu cầu GHC 9.14 (chưa stable).
> Khi GHC 9.14 stable thì upgrade sau. Hiện tại dùng workflow dưới đây.

---

## 1. Debug.Trace — Nhanh nhất, dùng nhiều nhất

Có sẵn trong `base` — không cần cài thêm.

```haskell
import Debug.Trace (trace, traceShow, traceShowId, traceM, traceShowM)
```

### Các hàm

| Hàm | Dùng khi | Ví dụ |
|-----|---------|-------|
| `trace msg val` | In string tùy ý, trả về `val` | `trace "got here" x` |
| `traceShow x x` | In giá trị qua `Show`, trả về nó | `traceShow result result` |
| `traceShowId x` | Như trên, viết gọn hơn | `filter f $ traceShowId xs` |
| `traceM msg` | Trong `do`-block (monadic) | `traceM $ "uid: " <> show uid` |
| `traceShowM x` | `traceM` + `show` | `traceShowM result` |

### Ví dụ thực tế

```haskell
-- Inspect giá trị giữa pipeline
processUsers users =
  users
    |> filter isActive
    |> traceShowId          -- in list sau filter
    |> map normalize
    |> traceShowId          -- in list sau map

-- Trong do-notation
createUser new = do
  traceM $ "createUser: email=" <> show new.email
  result <- validateEmail new.email
  traceShowM result         -- in kết quả validation
  pure result

-- Helper tái sử dụng — dán vào mọi project
debugVal :: Show a => String -> a -> a
debugVal label x = trace (label <> ": " <> show x) x

-- Dùng:
count = debugVal "user count" (length users)
```

### Lưu ý

- Output ra `stderr`, không lẫn với response HTTP
- Xóa hết `trace` trước khi commit (hoặc dùng `{-# WARNING trace ... #-}`)
- Với lazy evaluation: `trace` chỉ chạy khi giá trị được force — đôi khi không xuất hiện như mong đợi

---

## 2. GHCi Built-in Debugger — Step-through thực sự

### Mở GHCi

```bash
cabal repl                        # load toàn bộ project
cabal repl mini-brig:lib          # chỉ load library
cabal repl mini-brig:test:spec    # load test suite
```

### Breakpoints

```
:break Module.functionName        -- breakpoint tại hàm
:break Module 42                  -- breakpoint tại dòng 42
:break Module 42 10               -- breakpoint tại dòng 42, cột 10
:show breaks                      -- liệt kê tất cả breakpoints
:delete 1                         -- xóa breakpoint số 1
:delete *                         -- xóa tất cả
```

### Chạy và stepping

```
:step expression                  -- chạy expression, dừng tại breakpoint đầu tiên
:step                             -- step một bước
:steplocal                        -- step nhưng không đi vào hàm khác (step over)
:stepmodule                       -- step chỉ trong module hiện tại
:continue                         -- chạy đến breakpoint tiếp theo
:back                             -- quay lại bước trước (nếu có history)
:forward                          -- tiến tới sau khi :back
:history                          -- xem lịch sử các bước đã qua
```

### Inspect giá trị

```
:print x                          -- in x, không force evaluate thêm
:force x                          -- force evaluate rồi in (cẩn thận infinite list)
:sprint x                         -- in phần đã evaluate (thấy thunks chưa evaluate)
```

Khác nhau giữa `:print`, `:sprint`, `:force`:
```
-- Giả sử xs = [1..] (infinite list, chưa evaluate)
:sprint xs   →  xs = _            -- chưa evaluate gì
:print  xs   →  xs = 1 : _       -- evaluate một phần
:force  xs   →  <vòng lặp vô tận>  -- NGUY HIỂM với infinite list
```

### Ví dụ session đầy đủ

```
$ cabal repl

ghci> :break API.User.createUser
Breakpoint 0 activated at src/API/User.hs:45:1-80

ghci> :step (createUser (NewUser "alice@example.com" "Alice"))
Stopped in API.User.createUser, src/API/User.hs:46:3-30

ghci> :print new
new = NewUser {email = "alice@example.com", name = "Alice"}

ghci> :steplocal
Stopped in API.User.createUser, src/API/User.hs:47:3-45

ghci> email
"alice@example.com"

ghci> :continue
Right (User {userId = ..., ...})
```

---

## 3. Debug Monad Transformers trong GHCi

Khi code dùng `ExceptT`, `ReaderT`, `AppM` — chạy thủ công để test từng lớp.

```haskell
-- Tạo test Env
ghci> let testEnv = Env { dbPool = pool, jwtSecret = "secret", port = 8080 }

-- Chạy AppM thủ công
ghci> runExceptT (runReaderT (validateEmail "bad") testEnv)
Left InvalidEmail

ghci> runExceptT (runReaderT (validateEmail "good@example.com") testEnv)
Right "good@example.com"

-- Chạy IO actions trực tiếp
ghci> conn <- connectPostgreSQL "host=localhost dbname=mini_brig"
ghci> query_ conn "SELECT id, email FROM users" :: IO [(UUID, Text)]
[(uuid1, "alice@example.com"), ...]
```

---

## 4. ghcid — Feedback nhanh nhất khi viết code

```bash
# Cài
cabal install ghcid

# Dùng — tự reload khi save file
ghcid --command="cabal repl"

# Tự chạy lại main khi reload
ghcid --command="cabal repl" --test=":main"

# Tự chạy test
ghcid --command="cabal repl mini-brig:test:spec" --test="main"
```

`ghcid` không phải debugger nhưng thay thế được 70% nhu cầu: compile error và type error hiện ra ngay lập tức mà không cần chạy lại.

---

## 5. Các kỹ thuật đặc thù Haskell

### Debug với Lazy Evaluation

```haskell
-- Vấn đề: trace không xuất hiện vì giá trị chưa được force
result = trace "computing..." (expensiveComputation x)
-- Nếu result không bao giờ được dùng → trace không chạy

-- Giải pháp: dùng seq để force
result `seq` trace "result computed" result

-- Hoặc dùng deepseq (force toàn bộ structure)
import Control.DeepSeq (deepseq, NFData)
result `deepseq` trace "fully computed" result
```

### Debug Type Errors

```haskell
-- Thêm type annotation để thu hẹp nơi lỗi
createUser :: NewUser -> AppM User     -- explicit signature giúp GHC báo lỗi chính xác hơn
createUser new = do
  let uid = newUserId new :: UserId    -- annotate intermediate values
  ...
```

### Dùng `error` và `undefined` tạm thời

```haskell
-- Stub hàm chưa implement để build được project trước
processPayment :: Payment -> AppM Receipt
processPayment = error "TODO: implement processPayment"

-- Hoặc dùng typed hole để GHC gợi ý type
processPayment payment = _todo
-- GHC sẽ báo: Found hole '_todo' of type 'AppM Receipt'
--             Relevant bindings: payment :: Payment
```

### GHCi với multi-line input

```
ghci> :{
ghci|   let x = 1
ghci|       y = 2
ghci|   in x + y
ghci| :}
3
```

---

## 6. VS Code Workflow

### Setup terminal

Mở hai terminal panel trong VS Code:

```
Terminal 1: ghcid (luôn chạy)
  ghcid --command="cabal repl"

Terminal 2: cabal repl (debug thủ công)
  cabal repl
```

### Shortcut reload GHCi (`.vscode/keybindings.json`)

```json
[
  {
    "key": "ctrl+shift+r",
    "command": "workbench.action.terminal.sendSequence",
    "args": { "text": ":reload\n" }
  }
]
```

### Extension hỗ trợ hiện tại

| Extension | ID | Dùng cho |
|-----------|-----|---------|
| Haskell | `haskell.haskell` | HLS integration (type hints, go-to-def) |
| Haskell Syntax | `justusadam.language-haskell` | Syntax highlighting |

> **Lưu ý:** HLS của bạn đang ở version 2.4.0.0 cho GHC 9.0.2, trong khi GHC active là 9.4.7.
> Cần fix: `ghcup install hls 2.9.0.1 && ghcup set hls 2.9.0.1`

---

## 7. Khi nào dùng gì

| Tình huống | Tool | Lệnh |
|-----------|------|------|
| Kiểm tra giá trị nhanh | `traceShowId` / `traceM` | import rồi dán vào code |
| Step-through từng dòng | GHCi `:break` + `:step` | `cabal repl` |
| Test một hàm độc lập | GHCi gọi trực tiếp | `cabal repl` |
| Xem lỗi compile ngay khi save | ghcid | `ghcid --command="cabal repl"` |
| Debug monad stack | `runExceptT` / `runReaderT` trong GHCi | `cabal repl` |
| Inspect lazy thunk | GHCi `:sprint` → `:print` → `:force` | `cabal repl` |
| Force evaluate để debug | `deepseq` + `trace` | import `Control.DeepSeq` |
| Stub code chưa implement | `error "TODO"` hoặc typed hole `_` | viết thẳng vào code |

---

## 8. Tương lai: haskell-debugger (hdb)

Khi GHC 9.14 stable:

```bash
ghcup install ghc 9.14.x
ghcup set ghc 9.14.x
cabal install haskell-debugger
```

Cài VS Code extension: `Well-Typed.haskell-debugger-extension`

Tạo `.vscode/launch.json`:
```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "type": "haskell-debugger",
      "request": "launch",
      "name": "Debug mini-brig",
      "projectRoot": "${workspaceFolder}",
      "entryFile": "app/Main.hs",
      "entryPoint": "main"
    }
  ]
}
```

Có đầy đủ: breakpoints, step-in/over/out, inspect variables, conditional breakpoints.

---

## Liên kết

- [[ghci-repl-commands]] — command reference GHCi: `:type`, `:kind!`, `:info`
- [[run-build-curl-threaded]] — build, chạy server và smoke test curl
- [[test-suite-setup]] — test suite hspec + hspec-wai in-process
