#!/usr/bin/env bash
set -euo pipefail

# 1) Thư viện hệ thống mà GHC/ghcup cần trên Ubuntu (gmp, ncurses, ffi...).
#    Base image chạy user "vscode" có sudo không mật khẩu.
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  build-essential curl libffi-dev libffi8 libgmp-dev libgmp10 \
  libncurses-dev libtinfo6 pkg-config

# 2) Cài ghcup + GHC 9.6.7 + cabal + HLS (khớp base ^>=4.18.3.0).
#    Các biến BOOTSTRAP_* để chạy KHÔNG tương tác (không bị treo chờ nhập phím):
export BOOTSTRAP_HASKELL_NONINTERACTIVE=1          # không hỏi gì
export BOOTSTRAP_HASKELL_GHC_VERSION=9.6.7         # GHC khớp project
export BOOTSTRAP_HASKELL_CABAL_VERSION=recommended
export BOOTSTRAP_HASKELL_INSTALL_HLS=1             # cài luôn HLS
export BOOTSTRAP_HASKELL_ADJUST_BASHRC=1           # thêm ghcup vào PATH cho terminal mới
curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | sh

# 3) Nạp PATH ghcup cho CHÍNH script này (bước trên chỉ sửa .bashrc cho phiên sau).
source "$HOME/.ghcup/env"

# 4) Build sẵn dependency -> HLS index nhanh + lần chạy đầu không phải chờ.
cabal update
cabal build --only-dependencies --enable-tests

# 5) Build project (lúc này -Werror áp dụng cho code của bạn).
cabal build