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
* Learning docs under `docs/` (roadmap, debug guide, glossary, session log,
  serve/Capture explainer, run + curl guide).
