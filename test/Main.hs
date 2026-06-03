{-# LANGUAGE OverloadedStrings #-}

-- Test in-process cho UserAPI: chạy thẳng WAI `Application` (API.Server.app)
-- qua hspec-wai, KHÔNG cần bind cổng / khởi động Warp. Mỗi `it` gửi một request
-- giả lập rồi so khớp status + body.
module Main (main) where

import API.Server (app)
import Data.Aeson (Value, decode, object, (.=))
import Data.ByteString.Lazy (ByteString)
import Data.Text (Text)
import Network.HTTP.Types (Header, hContentType, methodPost)
import Test.Hspec (Spec, describe, hspec, it)
import Test.Hspec.Wai
  ( ResponseMatcher (..),
    get,
    request,
    shouldRespondWith,
    with,
  )
import Test.Hspec.Wai.Matcher (MatchBody (MatchBody))

main :: IO ()
main = hspec spec

spec :: Spec
spec = with (pure app) $ do
  describe "POST /register" $ do
    it "trả về stub user profile (200)" $
      request methodPost "/register" jsonHeaders registerBody
        `shouldRespondWith` jsonBody 200 stubProfileValue

    it "trả 400 khi JSON body sai/thiếu field" $
      request methodPost "/register" jsonHeaders "{\"bad\":true}"
        `shouldRespondWith` 400

  describe "POST /login" $
    it "trả về token (200)" $
      request methodPost "/login" jsonHeaders loginBody
        `shouldRespondWith` jsonBody 200 tokenValue

  describe "GET /users/:uid" $ do
    it "trả về stub user profile khi UUID hợp lệ (200)" $
      get "/users/00000000-0000-0000-0000-000000000000"
        `shouldRespondWith` jsonBody 200 stubProfileValue

    it "trả 400 khi UUID không hợp lệ" $
      get "/users/not-a-uuid" `shouldRespondWith` 400

  describe "Routing" $
    it "trả 404 cho path không tồn tại" $
      get "/nope" `shouldRespondWith` 404

-- hspec-wai `post` không gắn Content-Type, nhưng Servant ReqBody '[JSON] đòi
-- header "application/json" (thiếu thì 415). Vì vậy dùng `request` + header này.
jsonHeaders :: [Header]
jsonHeaders = [(hContentType, "application/json")]

registerBody :: ByteString
registerBody = "{\"newUserEmail\":\"alice@example.com\",\"newUsername\":\"alice\",\"newUserHandle\":null}"

loginBody :: ByteString
loginBody = "{\"loginEmail\":\"alice@example.com\",\"loginPassword\":\"secret\"}"

nilUuid :: Text
nilUuid = "00000000-0000-0000-0000-000000000000"

stubProfileValue :: Value
stubProfileValue =
  object
    [ "userId" .= nilUuid,
      "userEmail" .= ("stub@example.com" :: Text),
      "userName" .= ("User stub" :: Text),
      "userHandle" .= (Nothing :: Maybe Text)
    ]

tokenValue :: Value
tokenValue =
  object
    [ "token" .= ("stub-token" :: Text),
      "tokenUserId" .= nilUuid
    ]

-- Matcher JSON ngữ nghĩa: kiểm status + decode body thành Value rồi so sánh.
-- So sánh ở mức Value nên KHÔNG phụ thuộc thứ tự key; matchHeaders=[] để bỏ qua
-- Content-Type (Servant trả "application/json;charset=utf-8").
jsonBody :: Int -> Value -> ResponseMatcher
jsonBody status expected =
  ResponseMatcher
    { matchStatus = status,
      matchHeaders = [],
      matchBody = MatchBody $ \_ actual ->
        if decode actual == Just expected
          then Nothing
          else Just ("expected JSON: " <> show expected <> "\nbut got: " <> show actual)
    }
