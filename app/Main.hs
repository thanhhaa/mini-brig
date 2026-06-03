{-# LANGUAGE ExplicitNamespaces #-}
{-# LANGUAGE OverloadedStrings #-}

module Main where

import API.Routes (UserAPI, userAPI)
import Data.UUID (nil)
import Network.Wai.Handler.Warp (run)
import Servant (Server, serve, type (:<|>) (..))
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

main :: IO ()
main = do
  putStrLn "mini-brig listening on port 8080"
  run 8080 (serve userAPI server)

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
