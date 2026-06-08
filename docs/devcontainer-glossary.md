# Dev Container & Codespaces — Thuật ngữ môi trường dev

> Môi trường dev đóng gói trong repo (`.devcontainer/`). Mở project bằng GitHub
> Codespaces hoặc VS Code "Dev Containers" → ai cũng có **cùng một toolchain**,
> không phải cài GHC/cabal lên máy thật.

---

## Thuật ngữ

| Thuật ngữ | Định nghĩa |
|-----------|-----------|
| **Dev Container** | Container Linux mô tả sẵn môi trường dev của project. Định nghĩa trong `.devcontainer/devcontainer.json`. Giải quyết bệnh "máy tôi chạy được mà máy bạn thì không". |
| **GitHub Codespaces** | Dịch vụ chạy Dev Container **trên cloud**; mở repo là có VS Code + môi trường sẵn sàng trong trình duyệt. |
| **`devcontainer.json`** | File khai báo container: `image`, `forwardPorts`, `postCreateCommand`, extension VS Code… |
| **Base image** | Image nền để dựng container (vd `mcr.microsoft.com/devcontainers/base:ubuntu` = Ubuntu trần). Image trần ⇒ phải tự cài toolchain qua `postCreateCommand`. |
| **MCR (Microsoft Container Registry)** | Kho image của Microsoft. Codespaces kéo nhanh và **không** giới hạn pull ẩn danh — khác **Docker Hub** (image `haskell:9.6.7` ở Docker Hub từng bị **timeout/giới hạn pull**, nên dự án đổi sang MCR base + tự cài). |
| **`forwardPorts`** | Cổng container được "chuyển tiếp" ra ngoài để truy cập từ máy/host. Ở đây `8080` = cổng server mini-brig. |
| **`postCreateCommand`** | Lệnh chạy **một lần** sau khi container dựng xong (ở đây gọi `postCreate.sh` để cài Haskell + build dep). |
| **`ghcup`** | Trình quản lý phiên bản Haskell (GHC, cabal, HLS, stack). Cài qua script `get-ghcup.haskell.org`. |
| **`BOOTSTRAP_HASKELL_NONINTERACTIVE`** | Biến môi trường bảo ghcup cài **không tương tác** (không hỏi/chờ nhập phím). **Bắt buộc** trong CI/Codespaces — thiếu thì script treo chờ input. Đi kèm `BOOTSTRAP_HASKELL_GHC_VERSION`, `..._INSTALL_HLS`, `..._ADJUST_BASHRC`. |
| **HLS (Haskell Language Server)** | Backend cho IDE (autocomplete, hover type, lint). Extension `haskell.haskell` của VS Code nói chuyện với HLS. |
| **`source $HOME/.ghcup/env`** | Nạp `PATH` ghcup vào **phiên shell hiện tại**. Cần vì `ADJUST_BASHRC` chỉ có hiệu lực ở terminal **mở sau**, còn script đang chạy thì chưa thấy `cabal`. |
| **`cabal build --only-dependencies`** | Build trước **chỉ các dependency** (không build code project). Dùng trong setup để HLS index nhanh + lần build đầu của dev không phải chờ tải/dịch dep. |

> **Vì sao base image trần + tự cài, thay vì image `haskell:9.6.7` có sẵn?**
> Image Haskell ở Docker Hub kéo bị timeout (giới hạn pull). Đổi sang MCR Ubuntu
> (kéo nhanh) rồi cài GHC bằng ghcup trong `postCreate.sh` — đánh đổi: setup lâu
> hơn một chút lần đầu, nhưng **dựng được ổn định**.

---

## Tham khảo

- Dev Containers — devcontainer.json reference: https://containers.dev/implementors/json_reference/
- GitHub Codespaces — devcontainer: https://docs.github.com/en/codespaces/setting-up-your-project-for-codespaces
- ghcup (cài GHC/cabal/HLS): https://www.haskell.org/ghcup/

---

## Liên kết

- [[cabal-rts-glossary]] — build pipeline, GHC RTS và bẫy `-threaded`
- [[run-build-curl-threaded]] — format/lint/build/run trong môi trường thực tế
