{-# LANGUAGE ExplicitNamespaces #-}
{-# LANGUAGE OverloadedStrings #-}

-- API.Server tách phần "implementation" (handler + WAI Application) ra khỏi
-- API.Routes (chỉ định nghĩa kiểu API). Nhờ vậy cả executable (app/Main.hs) và
-- test-suite (test/Main.hs) đều import được `app` — test gọi thẳng Application
-- in-process, không cần khởi động server thật trên cổng nào.
module API.Server (app, server) where

import API.Routes (UserAPI, userAPI)
import Data.UUID (nil)
import Servant
  ( Application,
    Server,
    serve,
    type (:<|>) (..),
  )
import Servant.Server (Handler)
import Types
  ( Email (Email),
    LoginRequest,
    NewUser,
    TokenResponse (..),
    User (..),
    UserId (UserId),
    UserProfile,
  )

-- WAI Application sẵn sàng phục vụ: ghép proxy API với các handler.
app :: Application
app = serve userAPI server

server :: Server UserAPI
server =
  handleRegister
    :<|> handleLogin
    :<|> handleGetUser

handleRegister :: NewUser -> Handler UserProfile
handleRegister _new = pure stubUser

handleLogin :: LoginRequest -> Handler TokenResponse
handleLogin _req = pure (TokenResponse "stub-token" (UserId nil))

handleGetUser :: UserId -> Handler UserProfile
handleGetUser _uid = pure stubUser

stubUser :: User
stubUser =
  User
    { userId = UserId nil,
      userEmail = Email "stub@example.com",
      userName = "User stub",
      userHandle = Nothing
    }
