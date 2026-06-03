module Main where

import API.Server (app)
import Network.Wai.Handler.Warp (run)

main :: IO ()
main = do
  putStrLn "mini-brig listening on port 8080"
  run 8080 app
