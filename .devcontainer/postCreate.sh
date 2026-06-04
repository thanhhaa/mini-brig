#!/usr/bin/env bash

# -e: dừng ngay khi 1 command lỗi | -u: lỗi nếu dùng biến chưa set
# -o pipefail: lỗi giữa pipe cũng làm cả pipe fail (không nuốt lỗi)
set -euo pipefail

# 0) An toàn: nếu image chưa có ghcup thì cài (image haskell:9.6.7 thường đã có sẵn).
if ! command -v ghcup >/dev/null 2>&1; then
  curl -sSf https://get-ghcup.haskell.org | BOOTSTRAP_HASKELL_NONINTERACTIVE=1 sh
  # Nạp PATH của ghcup cho phiên shell hiện tại.
  source "$HOME/.ghcup/env"
fi

# 1) Cài Haskell Language Server khớp GHC 9.6.7 đang có.
#    --set: đặt làm mặc định trên PATH để extension VS Code tìm thấy ngay.
ghcup install hls --set

# 2) Tải/cập nhật package index từ Hackage (bắt buộc trước lần build đầu).
cabal update

# 3) Build sẵn TẤT CẢ dependency (servant-server, warp, aeson, uuid...).
#    Chưa build code của bạn -> tránh dính -Werror ở bước này.
#    Lợi: HLS index nhanh + lần `cabal run` đầu không phải chờ compile deps.
cabal build --only-dependencies --enable-tests

# 4) Build project (library + executable). Đây là lúc -Werror áp dụng cho code của bạn.
cabal build