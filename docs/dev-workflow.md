# Workflow phát triển mini-brig

> Mục tiêu: mô tả các vòng lặp công việc thường ngày khi làm việc với mini-brig —
> format code, lint, build, test, chạy server, và đóng gói/chạy bằng Docker.
> Đây là tài liệu "tra nhanh": copy lệnh là chạy được.

---

## 0. TL;DR — bảng lệnh

| Việc | Lệnh | Ghi chú |
|------|------|---------|
| Format Haskell | `ormolu --mode inplace $(find app src test -name '*.hs')` | sửa tại chỗ |
| Check format Haskell | `ormolu --mode check $(find app src test -name '*.hs')` | chỉ kiểm tra, không sửa |
| Lint | `hlint app src test` | gợi ý cải thiện code |
| Format .cabal | `cabal-fmt --inplace mini-brig.cabal` | **bắt buộc** sau khi sửa .cabal |
| Check .cabal | `cabal-fmt --check mini-brig.cabal` | chỉ kiểm tra |
| Build | `cabal build all` | cả lib + exe + test |
| Test | `cabal test` | |
| Chạy server | `cabal run exe:mini-brig` | lắng nghe `:8080` |
| Build Docker image | `docker build -t mini-brig .` | |
| Chạy Docker container | `docker run --rm -p 8080:8080 mini-brig` | |

> **Thứ tự khuyến nghị trước khi commit:** format → lint → cabal-fmt → build → test.

---

## 1. Bộ công cụ (toolchain)

Các binary dùng trong dự án:

```
ormolu      → ~/.cabal/bin/ormolu        # format Haskell
hlint       → ~/.local/bin/hlint         # lint Haskell
cabal-fmt   → ~/.cabal/bin/cabal-fmt     # format file .cabal
cabal       → ~/.ghcup/bin/cabal         # build tool
ghc 9.6.7   → ~/.ghcup/bin/ghc           # compiler (khớp base ^>=4.18.3.0)
docker      → Docker Desktop             # đóng gói / chạy container
```

> **Lưu ý target nhập nhằng:** tên `mini-brig` vừa là `lib:mini-brig` vừa là
> `exe:mini-brig`. Khi thao tác riêng executable phải ghi rõ tiền tố:
> `cabal build exe:mini-brig`, `cabal run exe:mini-brig`, `cabal list-bin exe:mini-brig`.

---

## 2. Vòng lặp format & lint

Ba công cụ độc lập, mỗi cái lo một phần:

| Công cụ | Lo phần nào | File |
|---------|-------------|------|
| `ormolu` | style/layout code Haskell | `*.hs` |
| `hlint` | gợi ý logic/idiom tốt hơn | `*.hs` |
| `cabal-fmt` | layout file build | `mini-brig.cabal` |

### Ormolu — format code Haskell

```bash
# Sửa tại chỗ tất cả file .hs
ormolu --mode inplace $(find app src test -name '*.hs')

# Hoặc chỉ kiểm tra (CI dùng cái này; exit != 0 nếu chưa format)
ormolu --mode check $(find app src test -name '*.hs')
```

> Cấu hình fixity/reexport của ormolu nằm ở file `.ormolu`. Phần giải thích từng
> entry xem [[ormolu-fixities]] (bản thân file `.ormolu` không cho phép comment `--`).

### HLint — lint

```bash
hlint app src test     # "No hints" = sạch
```

### cabal-fmt — format file .cabal

```bash
cabal-fmt --inplace mini-brig.cabal    # sửa tại chỗ
cabal-fmt --check   mini-brig.cabal    # chỉ kiểm tra
```

> **Quy ước dự án (bắt buộc):** luôn chạy `cabal-fmt --inplace mini-brig.cabal`
> ngay sau khi sửa file `.cabal` — thêm dependency, đổi ghc-options, v.v.

---

## 3. Vòng lặp build & test

```bash
cabal build all     # build library, executable, test-suite (-Werror áp dụng)
cabal test          # chạy test-suite mini-brig-test (hspec)
```

Một số biến thể hữu ích:

```bash
cabal build exe:mini-brig         # chỉ build executable
cabal build lib:mini-brig         # chỉ build library
cabal repl lib:mini-brig          # mở GHCi với library đã load (xem [[ghci-repl-commands]])
cabal clean                       # xóa dist-newstyle, build lại từ đầu
```

> **Khi nào cần `cabal clean`:** đổi *link-time options* (như `-threaded`) đôi khi
> không kích hoạt relink trong build incremental. Nếu binary "đáng lẽ phải khác mà
> vẫn y nguyên", chạy `cabal clean` rồi build lại. Chi tiết: [[run-build-curl-threaded]].

---

## 4. Chạy server & gọi thử

```bash
cabal run exe:mini-brig
# → "mini-brig listening on port 8080", lắng nghe :8080
```

> ⚠️ **Bẫy cổng 8080 (đã vấp):** trên máy dev này, container Docker `pgadmin_container_dev`
> thường chiếm sẵn `:8080`. Khi đó mini-brig native chết ngay với
> `bind: resource busy (Address already in use)`, và `curl localhost:8080` lại gọi **nhầm
> sang pgAdmin** (trả về trang 404 Werkzeug + lỗi "CSRF token") — dễ tưởng nhầm là bug mini-brig.
>
> **Kiểm tra trước khi chạy:**
> ```bash
> lsof -nP -iTCP:8080 -sTCP:LISTEN   # ai đang giữ 8080?
> docker ps                          # có phải container của mình không?
> ```
> **Nếu 8080 bận** (đừng dừng container không liên quan) — verify trên cổng khác mà không sửa code:
> ```bash
> { echo 'Network.Wai.Handler.Warp.run 8090 API.Server.app'; sleep 120; } \
>   | cabal repl exe:mini-brig &        # giữ stdin mở bằng sleep, nếu không ghci EOF → server chết
> # rồi curl localhost:8090/...
> ```
> Hoặc chạy qua Docker map cổng khác: `docker run --rm -p 8090:8080 mini-brig`.

Hoặc lấy đường dẫn binary rồi chạy trực tiếp:

```bash
BIN=$(cabal list-bin exe:mini-brig)
"$BIN"
```

Smoke test bằng `curl` (3 endpoint, xem `src/API/Routes.hs`):

```bash
# POST /register
curl -X POST localhost:8080/register -H 'Content-Type: application/json' \
  -d '{"newUserEmail":"alice@example.com","newUsername":"alice","newUserHandle":"alice_h"}'

# POST /login
curl -X POST localhost:8080/login -H 'Content-Type: application/json' \
  -d '{"loginEmail":"alice@example.com","loginPassword":"secret"}'

# GET /users/{uuid}
curl localhost:8080/users/00000000-0000-0000-0000-000000000000
```

> Toàn bộ chi tiết các endpoint + kết quả mong đợi + bug `-threaded`: [[run-build-curl-threaded]].

---

## 5. Vòng lặp Docker

`Dockerfile` dùng **multi-stage build**: stage `build` (toolchain Haskell đầy đủ)
compile + test, stage `runtime` (Debian slim) chỉ chứa binary đã build.

### Build & chạy

```bash
docker build -t mini-brig .                  # build image (test chạy trong build, fail test = fail build)
docker run --rm -p 8080:8080 mini-brig       # chạy container, map cổng 8080
```

- `--rm` : tự xóa container khi thoát.
- `-p 8080:8080` : map cổng host → cổng container (Warp nghe `:8080`).

### Image là bất biến — đổi code phải build lại

Container đang chạy **không** tự cập nhật theo source. Đổi code → `docker build`
lại → `docker run` lại. Nhưng **layer cache** khiến việc này rẻ:

| Thay đổi | Layer được tái dùng | Hệ quả |
|----------|--------------------|--------|
| Chỉ sửa file `.hs` | `COPY mini-brig.cabal` + build deps | bỏ qua compile deps, chỉ compile lại code → nhanh |
| Sửa `mini-brig.cabal` | (không) | build lại cả deps → chậm |

Đây là lý do Dockerfile `COPY mini-brig.cabal` **trước** rồi mới `COPY . .` —
để layer dependency (nặng nhất) chỉ rebuild khi `.cabal` đổi, không phải mỗi lần
sửa một dòng code.

### Lệnh Docker hữu ích

```bash
docker images                  # liệt kê image
docker ps                      # container đang chạy
docker ps -a                   # cả container đã dừng
docker system df               # dung lượng image / container / build cache
docker builder prune           # xóa build cache (BuildKit)
docker logs <container>        # xem log container
```

> Trên macOS, daemon `dockerd` chạy trong một VM Linux nhẹ; mọi layer/cache nằm
> trong VM đó (file ổ ảo của Docker Desktop), không phải trực tiếp trên ổ Mac.

### Dev nhanh: không build image mỗi lần

Vòng lặp build-image mỗi lần đổi code chỉ hợp cho **production/CI**. Khi dev hằng
ngày, chạy thẳng `cabal build` / `cabal run` trên máy (nhanh nhất), chỉ dùng Docker
khi cần kiểm tra artifact cuối hoặc môi trường giống production.

---

## 6. Checklist trước khi commit

```bash
# 1. format / lint
ormolu --mode check $(find app src test -name '*.hs')
hlint app src test
cabal-fmt --check mini-brig.cabal

# 2. build / test (-Werror)
cabal build all
cabal test

# 3. (tùy chọn) kiểm tra image build sạch
docker build -t mini-brig .
```

---

## 7. Liên kết

- [[run-build-curl-threaded]] — format → lint → build → run → curl chi tiết + bug `-threaded`
- [[ormolu-fixities]] — cấu hình file `.ormolu`, giải thích từng fixity/reexport
- [[ghci-repl-commands]] — lệnh trong `cabal repl` / GHCi
- [[test-suite-setup]] — cấu hình test-suite hspec
- [[cabal-rts-glossary]] — thuật ngữ cabal, `-threaded`, RTS way, incremental build
- [[devcontainer-glossary]] — thuật ngữ devcontainer / Docker / Codespaces
- [[http-web-glossary]] — HTTP status codes, methods, Warp, WAI
- [[mini-brig-roadmap]] — kế hoạch phát triển mini-brig
- [[session-log]] — nhật ký các session
