# Revision history for mini-brig

## 0.1.0.0 -- 2026-06-04

* First version. Released on an unsuspecting world.
* Servant `UserAPI` with 3 endpoints: `POST /register`, `POST /login`,
  `GET /users/:uid` (handlers return stub data).
* Domain types in `Types`: `User`, `NewUser`, `LoginRequest`, `TokenResponse`,
  and the `UserId`/`Email`/`Handle` newtypes (JSON via aeson Generic).
* `FromHttpApiData UserId` instance for `Capture "uid" UserId`.
* Executable served by Warp on port 8080; built with `-threaded -rtsopts
  -with-rtsopts=-N` (Warp requires the threaded RTS).
* Moved the WAI `Application` into the library as `API.Server` (exposing `app`)
  so both the executable and the test suite share it; `app/Main.hs` is now a thin
  wrapper that runs `app` with Warp.
* Test suite (`hspec` + `hspec-wai`) covering all endpoints in-process: happy
  paths for `/register`, `/login`, `/users/:uid`, plus 400 (bad body / invalid
  UUID) and 404 (unknown path). Bodies matched semantically by decoding to an
  aeson `Value` (key-order independent).
* Learning docs under `docs/` (roadmap, debug guide, glossary, session log,
  serve/Capture explainer, run + curl guide, test-suite setup guide).
