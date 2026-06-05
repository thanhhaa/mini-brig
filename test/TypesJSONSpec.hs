{-# LANGUAGE OverloadedStrings #-}

-- Test JSON serialization của các kiểu trong Types: kiểm tra (1) round-trip
-- decode . encode == id, (2) wire format đúng — đặc biệt newtype "trong suốt"
-- (positional ⇒ JSON trần, không bị bọc object), và (3) record encode đúng key.
module TypesJSONSpec (spec) where

import Data.Aeson (FromJSON, ToJSON, Value, decode, encode, object, toJSON, (.=))
import Data.Maybe (fromJust)
import Data.Text (Text)
import Data.UUID (UUID)
import qualified Data.UUID as UUID
import Test.Hspec (Expectation, Spec, describe, it, shouldBe)
import Types
  ( Email (Email),
    Handle (Handle),
    LoginRequest (..),
    NewUser (..),
    TokenResponse (..),
    User (..),
    UserId (UserId),
  )

spec :: Spec
spec = describe "Types JSON serialization" $ do
  describe "newtype trong suốt (positional ⇒ JSON trần)" $ do
    it "UserId ⇒ chuỗi UUID (không bọc object)" $
      toJSON (UserId sampleUuid) `shouldBe` toJSON (UUID.toText sampleUuid)

    it "Email ⇒ chuỗi" $
      toJSON (Email "a@b.com") `shouldBe` toJSON ("a@b.com" :: Text)

    it "Handle ⇒ chuỗi" $
      toJSON (Handle "h") `shouldBe` toJSON ("h" :: Text)

    it "decode chuỗi UUID ⇒ UserId" $
      decode (encode (UUID.toText sampleUuid)) `shouldBe` Just (UserId sampleUuid)

  describe "round-trip (decode . encode == id)" $ do
    it "UserId" $ roundTrips (UserId sampleUuid)
    it "Email" $ roundTrips (Email "a@b.com")
    it "Handle" $ roundTrips (Handle "h")
    it "User (handle = Just)" $ roundTrips sampleUser
    it "User (handle = Nothing)" $ roundTrips sampleUser {userHandle = Nothing}
    it "NewUser" $ roundTrips sampleNewUser
    it "LoginRequest" $ roundTrips sampleLogin
    it "TokenResponse" $ roundTrips sampleToken

  describe "record ⇒ object đúng key/value" $ do
    it "User (handle = Just)" $
      toJSON sampleUser `shouldBe` expectedUserValue

    it "User (handle = Nothing) ⇒ userHandle: null" $
      toJSON sampleUser {userHandle = Nothing}
        `shouldBe` object
          [ "userId" .= UUID.toText sampleUuid,
            "userEmail" .= ("alice@example.com" :: Text),
            "userName" .= ("Alice" :: Text),
            "userHandle" .= (Nothing :: Maybe Text)
          ]

    it "NewUser" $
      toJSON sampleNewUser
        `shouldBe` object
          [ "newUserEmail" .= ("alice@example.com" :: Text),
            "newUsername" .= ("alice" :: Text),
            "newUserHandle" .= ("alice_h" :: Text)
          ]

    it "LoginRequest" $
      toJSON sampleLogin
        `shouldBe` object
          [ "loginEmail" .= ("alice@example.com" :: Text),
            "loginPassword" .= ("secret" :: Text)
          ]

    it "TokenResponse" $
      toJSON sampleToken
        `shouldBe` object
          [ "token" .= ("tok-123" :: Text),
            "tokenUserId" .= UUID.toText sampleUuid
          ]

  describe "decode từ JSON cố định (wire format được chấp nhận)" $ do
    it "object ⇒ User" $
      decode
        "{\"userId\":\"12345678-90ab-cdef-1234-567890abcdef\",\"userEmail\":\"alice@example.com\",\"userName\":\"Alice\",\"userHandle\":\"alice_h\"}"
        `shouldBe` Just sampleUser

    it "thiếu userHandle (Maybe) ⇒ Nothing" $
      decode
        "{\"userId\":\"12345678-90ab-cdef-1234-567890abcdef\",\"userEmail\":\"alice@example.com\",\"userName\":\"Alice\"}"
        `shouldBe` Just sampleUser {userHandle = Nothing}

-- | decode . encode phải trả về chính giá trị ban đầu.
roundTrips :: (Eq a, Show a, FromJSON a, ToJSON a) => a -> Expectation
roundTrips x = decode (encode x) `shouldBe` Just x

sampleUuid :: UUID
sampleUuid = fromJust (UUID.fromText "12345678-90ab-cdef-1234-567890abcdef")

sampleUser :: User
sampleUser =
  User
    { userId = UserId sampleUuid,
      userEmail = Email "alice@example.com",
      userName = "Alice",
      userHandle = Just (Handle "alice_h")
    }

sampleNewUser :: NewUser
sampleNewUser =
  NewUser
    { newUserEmail = Email "alice@example.com",
      newUsername = "alice",
      newUserHandle = Just (Handle "alice_h")
    }

sampleLogin :: LoginRequest
sampleLogin =
  LoginRequest
    { loginEmail = Email "alice@example.com",
      loginPassword = "secret"
    }

sampleToken :: TokenResponse
sampleToken =
  TokenResponse
    { token = "tok-123",
      tokenUserId = UserId sampleUuid
    }

expectedUserValue :: Value
expectedUserValue =
  object
    [ "userId" .= UUID.toText sampleUuid,
      "userEmail" .= ("alice@example.com" :: Text),
      "userName" .= ("Alice" :: Text),
      "userHandle" .= ("alice_h" :: Text)
    ]
