# Cabal & GHC RTS — Thuật ngữ build & runtime

> Các khái niệm gặp khi build, run server và sửa bug `-threaded`
> (xem [[run-build-curl-threaded]]).

---

## Cabal — stanzas & fields

| Thuật ngữ | Định nghĩa |
|-----------|-----------|
| **Stanza** | Một **khối khai báo có tên** trong file `.cabal`. Mỗi target là một stanza: `library`, `executable mini-brig`, `test-suite mini-brig-test`, và `common warnings`. Trong stanza đặt các field như `build-depends`, `ghc-options`, `hs-source-dirs`. |
| **`common` stanza** | Stanza khai báo cấu hình dùng chung; các stanza khác kéo vào bằng `import:`. Ví dụ `common warnings` đặt `ghc-options: -Wall -Werror`, rồi mỗi target `import: warnings`. |
| **Component / target** | Một thứ build ra được: thư viện (lib), file chạy (exe), bộ test. Một package có nhiều component. Tên đầy đủ: `lib:mini-brig`, `exe:mini-brig`, `test:mini-brig-test` (dùng khi tên bị nhập nhằng). |
| **`main-is`** | Field khai báo file chứa module **entry point** (`main`) cho `executable`/`test-suite`. Ví dụ `main-is: Main.hs`. |
| **`other-modules`** | Field liệt kê **mọi module khác** (không phải `Main`) thuộc về target và cần được biên dịch. ⚠️ `import` trong code **không** tự bảo Cabal build module đó — Cabal **chỉ** build những module nằm trong `main-is` + `other-modules`. Thiếu ⇒ lỗi *"Could not find module …"* và file bị **bỏ sót khi `cabal sdist`**. Đây là module **nội bộ** (không export ra ngoài package). |
| **`exposed-modules`** | Chỉ có ở stanza `library`: module **public** mà package/target khác import được (vd `API.Server`). Khác `other-modules` (nội bộ, không export). |

---

## Build pipeline — compile, link, incremental

| Thuật ngữ | Định nghĩa |
|-----------|-----------|
| **Compile** | Dịch **từng** file `.hs` → file đối tượng `.o` (object file). Là bước theo từng module. |
| **Object file (`.o`)** | Mã máy đã dịch của một module, **chưa** ghép thành chương trình hoàn chỉnh. |
| **Link / Linking** | Bước **ghép** tất cả `.o` + các thư viện (kể cả RTS) thành một **binary** chạy được. Khác hẳn bước compile. |
| **Relink** | **Link lại** binary mà không cần compile lại module nào. Các option ảnh hưởng *lúc link* (như `-threaded`) chỉ có tác dụng sau khi relink. |
| **Build incremental** | Build **chỉ phần đã đổi**: module nào sửa thì compile lại module đó, rồi relink. Cabal dò thay đổi theo nội dung file + cấu hình. Nhanh hơn build lại từ đầu. ⚠️ **Bẫy:** đổi option *link-time* (vd `-threaded`) đôi khi **không** kích hoạt relink trong build incremental — phải `cabal clean` rồi build lại. |
| **`cabal clean`** | Xoá toàn bộ kết quả build (`dist-newstyle`) để build lại **từ đầu** — cách chắc chắn khi incremental build "kẹt". |

---

## GHC RTS (Runtime System)

| Thuật ngữ | Định nghĩa |
|-----------|-----------|
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

## Tham khảo

- Cabal — package description / stanzas & fields: https://cabal.readthedocs.io/en/stable/cabal-package.html
- GHC User's Guide — `-threaded`, `-rtsopts`, RTS options: https://downloads.haskell.org/ghc/latest/docs/users_guide/phases.html#options-affecting-linking

---

## Liên kết

- [[run-build-curl-threaded]] — thực tế gặp bug `-threaded` và cách sửa (`cabal clean`, kiểm tra RTS way)
- [[devcontainer-glossary]] — môi trường dev container, ghcup, toolchain
