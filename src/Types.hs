-- DeriveAnyClass: cho phép `deriving` bất kỳ typeclass nào có default method
--   mà không cần viết thân instance. Nhờ nó có thể viết
--   `deriving (FromJSON, ToJSON)` trực tiếp trên dòng deriving.
-- DeriveAnyClass: allows `deriving` any typeclass that provides default method
--   implementations, without writing an explicit instance body. This lets us
--   write `deriving (FromJSON, ToJSON)` directly on the deriving clause.
{-# LANGUAGE DeriveAnyClass #-}
-- DeriveGeneric: cho phép `deriving Generic`. Generic mô tả "cấu trúc tổng
--   quát" (constructor, field) của kiểu dưới dạng compiler đọc được — nền
--   tảng cho generic programming. Aeson dùng nó để tự suy ra cách
--   serialize/deserialize JSON mà không cần viết tay.
-- DeriveGeneric: enables `deriving Generic`. Generic exposes the "shape"
--   (constructors, fields) of a type in a form the compiler can inspect —
--   the foundation of generic programming. Aeson uses it to automatically
--   derive JSON serialization without hand-written instances.
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE InstanceSigs #-}

-- DerivingStrategies: cho phép chỉ định rõ "cách" derive bằng các từ khoá
--   stock / newtype / anyclass ngay sau `deriving`. Nhờ đó tránh việc GHC
--   tự đoán strategy (với DeriveAnyClass bật, mặc định nó chọn anyclass và
--   sinh ra instance rỗng).
-- DerivingStrategies: lets you state explicitly *how* to derive via the
--   stock / newtype / anyclass keywords after `deriving`, instead of letting
--   GHC guess (with DeriveAnyClass on, it would pick anyclass and generate an
--   empty instance).
-- {-# LANGUAGE DerivingStrategies #-}
-- GeneralizedNewtypeDeriving: với `deriving newtype`, instance của kiểu bên
--   trong (UUID) được "mượn" lại cho newtype (UserId). Dùng cho
--   FromHttpApiData/ToHttpApiData: cách parse text URL của UUID tái sử dụng y
--   nguyên cho UserId.
-- GeneralizedNewtypeDeriving: with `deriving newtype`, the inner type's
--   (UUID) instance is reused for the newtype (UserId). Used here for
--   FromHttpApiData/ToHttpApiData so UUID's URL-text parsing is reused as-is.
-- {-# LANGUAGE GeneralizedNewtypeDeriving #-}

module Types where

import Data.Aeson (FromJSON, ToJSON)
import Data.Text (Text)
import Data.UUID (UUID)
import GHC.Generics (Generic)
import Web.HttpApiData (FromHttpApiData (parseUrlPiece))

-- FromHttpApiData: dạy Servant cách biến một đoạn text trong URL thành UserId.
--   Cần cho `Capture "uid" UserId` ở route /users/:uid — Servant phải parse
--   đoạn path (Text) ra UserId trước khi gọi handler.
-- FromHttpApiData: teaches Servant how to turn a URL text segment into a
--   UserId. Required by `Capture "uid" UserId` on the /users/:uid route —
--   Servant must parse the path segment (Text) into a UserId before calling
--   the handler.
--
-- Vì sao thiếu instance này thì LỖI lại hiện ở `serve` (trong app/Main.hs)?
--   `serve :: HasServer api '[] => Proxy api -> Server api -> Application`.
--   Khi GHC kiểm tra ràng buộc `HasServer UserAPI '[]`, nó bung API ra từng
--   endpoint; tới `Capture "uid" UserId` thì sinh ra yêu cầu
--   `FromHttpApiData UserId`. Không có instance → ràng buộc không thoả → GHC
--   gắn lỗi ngay tại chỗ gọi `serve`, dù gốc rễ nằm ở kiểu UserId này. Định
--   nghĩa instance ở đây chính là để lấp đúng ràng buộc đó.
-- Why does a MISSING instance surface as an error at `serve` (in app/Main.hs)?
--   `serve :: HasServer api '[] => Proxy api -> Server api -> Application`.
--   When GHC discharges the `HasServer UserAPI '[]` constraint it expands the
--   API endpoint by endpoint; reaching `Capture "uid" UserId` it demands a
--   `FromHttpApiData UserId`. With no instance the constraint is unsatisfied,
--   so GHC pins the error at the `serve` call site even though the real cause
--   is this UserId type. Defining the instance here is what satisfies it.
instance FromHttpApiData UserId where
  -- parseUrlPiece nhận đoạn path dạng Text, trả về Either: Left là thông báo
  --   lỗi parse, Right là giá trị parse thành công. (Chữ ký này hiện ra được
  --   nhờ extension InstanceSigs.)
  -- parseUrlPiece takes the path segment as Text and returns Either: Left is a
  --   parse-error message, Right is the parsed value. (Writing this signature
  --   inside the instance is enabled by the InstanceSigs extension.)
  parseUrlPiece :: Text -> Either Text UserId
  -- `parseUrlPiece t` bên vế phải dùng instance của UUID (vì UserId bọc UUID),
  --   cho ra Either Text UUID; `UserId <$>` map qua Either để bọc kết quả
  --   thành UserId. Nhánh Left (lỗi) được giữ nguyên. Không cần định nghĩa
  --   parseQueryParam vì class đã có default `parseQueryParam = parseUrlPiece`.
  -- On the right, `parseUrlPiece t` uses UUID's instance (UserId wraps UUID),
  --   producing Either Text UUID; `UserId <$>` maps over Either to wrap the
  --   result into a UserId. The Left (error) branch is passed through. No need
  --   to define parseQueryParam: the class defaults `parseQueryParam =
  --   parseUrlPiece`.
  parseUrlPiece t = UserId <$> parseUrlPiece t

newtype UserId = UserId UUID
  deriving (Show, Eq, Generic, FromJSON, ToJSON)

newtype Email = Email Text
  deriving (Show, Eq, Generic, FromJSON, ToJSON)

newtype Handle = Handle Text
  deriving (Show, Eq, Generic, FromJSON, ToJSON)

data User = User
  { userId :: UserId,
    userEmail :: Email,
    userName :: Text,
    userHandle :: Maybe Handle
  }
  deriving (Show, Eq, Generic, FromJSON, ToJSON)

data NewUser = NewUser
  { newUserEmail :: Email,
    newUsername :: Text,
    newUserHandle :: Maybe Handle
  }
  deriving (Show, Eq, Generic, FromJSON, ToJSON)

type UserProfile = User

data LoginRequest = LoginRequest
  { loginEmail :: Email,
    loginPassword :: Text
  }
  deriving (Show, Eq, Generic, FromJSON, ToJSON)

data TokenResponse = TokenResponse
  { token :: Text,
    tokenUserId :: UserId
  }
  deriving (Show, Eq, Generic, FromJSON, ToJSON)
