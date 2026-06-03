-- DataKinds: "nâng tầng" (promotion) giá trị lên type level. Nhờ nó mà
--   '[JSON] (type-level list các content-type) và "register"/"login"
--   (type-level string, kind Symbol — một path segment) dùng được như kiểu.
-- DataKinds: promotes values to the type level. This allows '[JSON]
--   (a type-level list of content-types) and "register"/"login"
--   (type-level strings with kind Symbol — URL path segments) to be
--   used as types in the Servant API definition.
{-# LANGUAGE DataKinds #-}
-- TypeOperators: cho phép ký hiệu làm tên kiểu (type operator). Nhờ nó mà
--   :> ("rồi tới") nối các thành phần của một route, và :<|> ("hoặc") gộp
--   nhiều endpoint lại với nhau — tất cả ở tầng type.
-- TypeOperators: allows symbols to be used as type names (type operators).
--   This enables :> ("then") to chain route components, and :<|> ("or")
--   to combine multiple endpoints — all at the type level.
{-# LANGUAGE TypeOperators #-}

module API.Routes where

import Servant (Capture, Get, JSON, Post, Proxy (Proxy), ReqBody, (:<|>), (:>))
import Types (LoginRequest, NewUser, TokenResponse, UserId, UserProfile)

type UserAPI =
  "register" :> ReqBody '[JSON] NewUser :> Post '[JSON] UserProfile
    :<|> "login" :> ReqBody '[JSON] LoginRequest :> Post '[JSON] TokenResponse
    :<|> "users" :> Capture "uid" UserId :> Get '[JSON] UserProfile

userAPI :: Proxy UserAPI
userAPI = Proxy
