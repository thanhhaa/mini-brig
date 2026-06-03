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

  -- ---- Edge cases ----

  describe "Edge: Content-Type của request" $ do
    it "thiếu Content-Type → 415" $
      request methodPost "/register" [] registerBody
        `shouldRespondWith` 415

    it "Content-Type sai (text/plain) → 415" $
      request methodPost "/register" [(hContentType, "text/plain")] registerBody
        `shouldRespondWith` 415

    it "Content-Type kèm charset vẫn được chấp nhận → 200" $
      request methodPost "/register" [(hContentType, "application/json;charset=utf-8")] registerBody
        `shouldRespondWith` jsonBody 200 stubProfileValue

  describe "Edge: body không hợp lệ" $ do
    it "body rỗng → 400" $
      request methodPost "/register" jsonHeaders ""
        `shouldRespondWith` 400

    it "JSON sai cú pháp → 400" $
      request methodPost "/register" jsonHeaders "{not valid json"
        `shouldRespondWith` 400

    it "JSON đúng cú pháp nhưng sai kiểu (mảng thay vì object) → 400" $
      request methodPost "/register" jsonHeaders "[1,2,3]"
        `shouldRespondWith` 400

    it "thiếu field bắt buộc (newUsername) → 400" $
      request methodPost "/register" jsonHeaders "{\"newUserEmail\":\"a@b.com\",\"newUserHandle\":null}"
        `shouldRespondWith` 400

    it "field bắt buộc sai kiểu (newUserEmail là số) → 400" $
      request methodPost "/register" jsonHeaders "{\"newUserEmail\":42,\"newUsername\":\"a\",\"newUserHandle\":null}"
        `shouldRespondWith` 400

    it "field thừa được aeson bỏ qua → 200" $
      request methodPost "/register" jsonHeaders registerBodyExtraField
        `shouldRespondWith` jsonBody 200 stubProfileValue

  describe "Edge: field tuỳ chọn (newUserHandle)" $ do
    it "có handle (không null) vẫn 200" $
      request methodPost "/register" jsonHeaders registerBodyWithHandle
        `shouldRespondWith` jsonBody 200 stubProfileValue

    it "thiếu hẳn field handle (Maybe ⇒ Nothing) vẫn 200" $
      request methodPost "/register" jsonHeaders registerBodyNoHandle
        `shouldRespondWith` jsonBody 200 stubProfileValue

  describe "Edge: method không khớp path" $ do
    it "GET /register (chỉ có POST) → 405" $
      get "/register" `shouldRespondWith` 405

    it "GET /login (chỉ có POST) → 405" $
      get "/login" `shouldRespondWith` 405

    it "POST /users/:uid (chỉ có GET) → 405" $
      request methodPost "/users/00000000-0000-0000-0000-000000000000" jsonHeaders ""
        `shouldRespondWith` 405

  describe "Edge: /login body" $
    it "thiếu loginPassword → 400" $
      request methodPost "/login" jsonHeaders "{\"loginEmail\":\"a@b.com\"}"
        `shouldRespondWith` 400

  describe "Edge: Capture UserId" $ do
    it "UUID có hex chữ HOA vẫn hợp lệ → 200" $
      get "/users/12345678-90AB-CDEF-1234-567890ABCDEF"
        `shouldRespondWith` jsonBody 200 stubProfileValue

    it "UUID thiếu segment (/users/) → 404" $
      get "/users/" `shouldRespondWith` 404

    it "UUID quá ngắn → 400" $
      get "/users/123" `shouldRespondWith` 400

-- hspec-wai `post` không gắn Content-Type, nhưng Servant ReqBody '[JSON] đòi
-- header "application/json" (thiếu thì 415). Vì vậy dùng `request` + header này.
jsonHeaders :: [Header]
jsonHeaders = [(hContentType, "application/json")]

registerBody :: ByteString
registerBody = "{\"newUserEmail\":\"alice@example.com\",\"newUsername\":\"alice\",\"newUserHandle\":null}"

loginBody :: ByteString
loginBody = "{\"loginEmail\":\"alice@example.com\",\"loginPassword\":\"secret\"}"

-- newUserHandle có giá trị (không null).
registerBodyWithHandle :: ByteString
registerBodyWithHandle = "{\"newUserEmail\":\"alice@example.com\",\"newUsername\":\"alice\",\"newUserHandle\":\"alice_h\"}"

-- Bỏ hẳn field newUserHandle: vì là Maybe nên aeson coi như Nothing.
registerBodyNoHandle :: ByteString
registerBodyNoHandle = "{\"newUserEmail\":\"alice@example.com\",\"newUsername\":\"alice\"}"

-- Có thêm field lạ "extra": aeson Generic mặc định bỏ qua field không khai báo.
registerBodyExtraField :: ByteString
registerBodyExtraField = "{\"newUserEmail\":\"alice@example.com\",\"newUsername\":\"alice\",\"newUserHandle\":null,\"extra\":\"ignored\"}"

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
