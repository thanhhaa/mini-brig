# Web & HTTP — Lộ trình học theo chiều sâu (qua mini-brig)

> Mục tiêu: hiểu **chuyện gì thực sự xảy ra** khi một request đi từ `curl`/app
> tới server và quay về — từ TCP, HTTP, JSON, auth, tới TLS và proxy.
> Mỗi module gắn vào một giai đoạn build mini-brig và **luôn có thí nghiệm tay**.
>
> Khác với [[mini-brig-roadmap]] (thiên về Haskell/kiến trúc), file này thiên
> về **khái niệm web**. Hai roadmap chạy song song — xem bảng ánh xạ bên dưới.

---

## Cách học trong roadmap này

Mỗi module có 4 phần cố định:

1. **Khái niệm** — ý tưởng web cốt lõi, giải thích cho người mới hoàn toàn.
2. **Trong mini-brig** — nó nằm ở đâu trong code bạn đang viết.
3. **Thí nghiệm** — lệnh chạy được ngay để *nhìn thấy* khái niệm đó.
4. **Câu hỏi tự kiểm** — nếu trả lời được là bạn đã hiểu, chưa thì đọc lại.

Nguyên tắc vàng: **không đọc lý thuyết suông**. Chạy `curl`, nhìn byte thật,
rồi mới đối chiếu với khái niệm. Web là thứ học bằng cách quan sát.

---

## Ánh xạ Build ↔ Web

| Build phase (mini-brig-roadmap) | Web module (file này) | Khái niệm web trọng tâm |
|---|---|---|
| Phase 1 — Types | **M0, M1** | TCP/port/socket, vòng đời 1 request |
| Phase 2 — Servant routing | **M2, M3** | Anatomy của request/response, method & status |
| Phase 2 (mở rộng) | **M4** | Content-Type, JSON, content negotiation |
| Phase 3 — App monad | **M5** | Statelessness, vì sao mỗi request độc lập |
| Phase 5 — Auth | **M6, M7** | Cookie vs token, JWT, Authorization header |
| (song song Phase 5) | **M8** | HTTPS/TLS: mã hoá, certificate, handshake |
| Phase 6 — Gọi service khác | **M9** | REST, client HTTP, proxy, 502/504, timeout |
| Bất kỳ lúc nào | **M10** | Caching, CORS, HTTP/2-3, observability |

> Bạn đang ở cuối **Phase 2** → bắt đầu đọc nghiêm túc từ **M2**, nhưng nên
> chạy qua M0–M1 một lượt vì đó là nền móng mọi thứ phía sau.

---

## M0 — Trước khi có HTTP: máy nói chuyện với nhau thế nào

**Khái niệm.**
Internet ở tầng dưới cùng chỉ là các máy gửi cho nhau từng gói byte qua **IP**
(địa chỉ máy, vd `127.0.0.1`) và **TCP** (kênh truyền tin cậy, đảm bảo byte tới
đủ và đúng thứ tự). Một **port** là con số (0–65535) để phân biệt nhiều chương
trình cùng chạy trên một máy. Một **socket** = (IP + port) ở mỗi đầu; hai socket
nối lại thành một "ống" để hai bên đẩy byte qua.

HTTP **không phải** thứ thần kỳ — nó chỉ là **quy ước về định dạng văn bản** mà
hai bên đồng ý gửi qua cái ống TCP đó. Bỏ HTTP đi, cái ống vẫn còn.

**Trong mini-brig.**
`run 8080 app` trong [app/Main.hs](app/Main.hs#L9) bảo Warp: "mở port 8080, lắng
nghe TCP, ai kết nối vào thì parse byte theo luật HTTP rồi đưa cho `app`".

**Thí nghiệm.**
```bash
# Terminal 1: chạy server
cabal run mini-brig

# Terminal 2: xem có gì đang nghe trên port 8080
lsof -iTCP:8080 -sTCP:LISTEN          # macOS: thấy process "mini-brig"

# Nói chuyện TCP "thô" — tự gõ HTTP bằng tay, không cần curl:
printf 'GET /users/123 HTTP/1.1\r\nHost: localhost\r\n\r\n' | nc localhost 8080
```
Cái `nc` (netcat) chỉ mở ống TCP và đẩy đúng những byte bạn gõ. Việc server trả
về response chứng minh: **HTTP chỉ là text gửi qua TCP**.

**Tự kiểm.**
- Port khác địa chỉ IP ở điểm nào? Vì sao cần cả hai?
- Nếu hai chương trình cùng nghe port 8080 thì sao?
- Vì sao `\r\n\r\n` (dòng trống) lại quan trọng trong thí nghiệm `nc`?

---

## M1 — Vòng đời một request (bức tranh tổng thể)

**Khái niệm.**
Một lần gọi API đi qua các trạm:
```
curl/app → DNS (tên → IP) → TCP handshake → [TLS handshake nếu HTTPS]
        → gửi HTTP request → server route → handler chạy → HTTP response
        → đóng/giữ kết nối → client parse response
```
Hiểu được từng trạm này thì mọi lỗi ("connection refused", "timeout", "404",
"SSL error") đều quy được về **một trạm cụ thể bị hỏng**, thay vì "mạng lỗi".

**Trong mini-brig.**
Hiện mini-brig chạy `http://localhost` nên *bỏ qua* trạm DNS (đã là IP) và TLS
(chưa bật). Bạn đang sống ở phiên bản đơn giản nhất của vòng đời — hoàn hảo để
học. M8 sẽ thêm trạm TLS, M9 thêm trạm proxy.

**Thí nghiệm.**
```bash
# -v cho thấy TỪNG trạm: kết nối, request gửi đi (>), response nhận về (<)
curl -v http://localhost:8080/users/123
```
Đọc kỹ output: dòng `* Connected to localhost` = TCP xong; `> GET ...` = request
bạn gửi; `< HTTP/1.1 200 OK` = response. Đây là bản đồ bạn sẽ tra suốt roadmap.

**Tự kiểm.**
- "Connection refused" xảy ra ở trạm nào? Còn "404" ở trạm nào?
- Vì sao gọi `localhost` thì không có trạm DNS?

---

## M2 — Anatomy của HTTP message

**Khái niệm.**
Cả request và response đều có cấu trúc **3 phần** giống nhau:
```
<dòng đầu>                 ← request: METHOD PATH VERSION │ response: VERSION STATUS
<các header>              ← metadata, mỗi dòng "Key: Value"
<dòng trống>             ← ranh giới header/body (chính là \r\n\r\n)
<body>                   ← dữ liệu (có thể rỗng)
```
Chỉ vậy thôi. Mọi request/response trên đời đều theo khuôn này.

**Trong mini-brig.**
Servant tách 3 phần này cho bạn: `Capture`/path → từ dòng đầu; `ReqBody '[JSON]`
→ từ body; `Post '[JSON]` → quyết định status & header response. Xem
[[serve-capture-fromhttpapidata]] để biết từng mảnh map vào type ra sao.

**Thí nghiệm.**
```bash
# Nhìn response đầy đủ cả header (-i = include headers)
curl -i http://localhost:8080/users/123

# Nhìn cả request LẪN response ở mức byte (-v đã làm ở M1) và so sánh 3 phần
curl -v -X POST http://localhost:8080/login \
  -H 'Content-Type: application/json' \
  -d '{"loginEmail":"a@b.com"}'
```
Chỉ ra bằng mắt: đâu là dòng đầu, đâu là header, dòng trống nằm ở đâu, body là gì.

**Tự kiểm.**
- Header `Server: Warp/...` đến từ phía nào, client hay server?
- GET có body không? Vì sao thường không?

→ Đối chiếu bảng đầy đủ trong [[http-web-glossary]] phần *Cấu trúc HTTP Request*.

---

## M3 — Method & Status code: ngữ nghĩa, không chỉ con số

**Khái niệm.**
**Method** nói *ý định*: `GET` (đọc, không đổi gì — gọi là **safe**), `POST`
(tạo mới), `PUT` (thay toàn bộ), `PATCH` (sửa một phần), `DELETE` (xoá). Hai
tính chất quan trọng: **safe** (không đổi state) và **idempotent** (gọi 1 hay 10
lần kết quả như nhau — GET/PUT/DELETE có, POST thì không).

**Status code** nói *kết quả*, theo nhóm trăm: `2xx` ok, `3xx` đi chỗ khác,
`4xx` **client sai**, `5xx` **server sai**. Phân biệt 4xx/5xx là kỹ năng debug
nền tảng: lỗi của tôi hay của server?

**Trong mini-brig.**
Servant **tự** sinh 404 (sai path), 405 (sai method), 400 (body JSON hỏng) —
bạn không viết dòng nào. Hiện handler luôn trả 200; sau này khi thêm DB và auth
bạn sẽ chủ động trả 201 (Created), 401, 404, 409…

**Thí nghiệm.**
```bash
curl -i http://localhost:8080/users/123          # 200 — đúng
curl -i http://localhost:8080/khong-ton-tai       # 404 — Servant tự lo
curl -i -X DELETE http://localhost:8080/users/123 # 405 — path đúng, method sai
curl -i -X POST http://localhost:8080/login \
  -H 'Content-Type: application/json' -d '{ hỏng json'   # 400 — client sai
```
Chú ý: bạn *không viết code* cho mấy lỗi này, framework suy ra từ **type** của
API. Đó là sức mạnh của Servant.

**Tự kiểm.**
- Vì sao gọi `DELETE` hai lần nên cho cùng kết quả (idempotent), còn `POST`
  hai lần thì tạo ra hai resource?
- Một API trả `500` — lỗi nằm ở bên nào? Bạn (client) sửa được không?

→ Bảng status đầy đủ + ghi chú "gặp ở đâu trong mini-brig": [[http-web-glossary]].

---

## M4 — Content-Type, serialization & content negotiation

**Khái niệm.**
Qua dây TCP chỉ có **byte**. Để hai bên hiểu nhau, request/response khai báo
**Content-Type** (vd `application/json`) — "đống byte này hãy đọc như JSON".
**Serialization** = biến object trong bộ nhớ → byte (JSON) để gửi;
**deserialization** = chiều ngược lại. **Content negotiation**: client nói
"tôi muốn nhận kiểu gì" qua header `Accept`, server chọn kiểu phù hợp.

**Trong mini-brig.**
`'[JSON]` trong route type chính là khai báo content-type ở tầng type. Instance
`ToJSON`/`FromJSON` trong [Types.hs](src/Types.hs) là luật serialize. Nếu client
gửi `Content-Type` sai hoặc Accept kiểu server không hỗ trợ → Servant trả lỗi
tự động (415 / 406).

**Thí nghiệm.**
```bash
# Đúng content-type → server parse được
curl -i -X POST http://localhost:8080/login \
  -H 'Content-Type: application/json' -d '{"loginEmail":"a@b.com"}'

# Bỏ Content-Type hoặc khai sai → quan sát server phản ứng
curl -i -X POST http://localhost:8080/login -d '{"loginEmail":"a@b.com"}'

# Xem JSON server trả về có cấu trúc khớp Types.hs không
curl -s http://localhost:8080/users/123 | jq .
```
Mở [test/TypesJSONSpec.hs](test/TypesJSONSpec.hs) — đó chính là test kiểm tra
serialize/deserialize round-trip, tức là kiểm tra "byte trên dây" có đúng không.

**Tự kiểm.**
- Khác nhau giữa `Content-Type` (request) và `Accept` (request)?
- Vì sao server cần biết content-type thay vì tự đoán?

---

## M5 — HTTP là stateless (và vì sao điều đó định hình kiến trúc)

**Khái niệm.**
Mỗi HTTP request là **độc lập** — server *không tự nhớ* gì về request trước.
Đây là lựa chọn thiết kế cốt lõi của web: dễ scale (request nào đập vào server
nào cũng được), nhưng đổi lại — muốn "nhớ bạn là ai" thì **mỗi request phải tự
mang theo bằng chứng** (token/cookie). Đó là lý do M6–M7 (auth) tồn tại.

**Trong mini-brig.**
`AppM = ReaderT Env (ExceptT AppError IO)` ở [[mini-brig-roadmap]] Phase 3: `Env`
là state *dùng chung, bất biến* (pool DB, secret) — **không phải** state per-user.
Mỗi request vẫn bắt đầu từ con số 0 về "ai đang gọi". Hiểu statelessness giúp
bạn hiểu vì sao không thể "lưu user đang đăng nhập" trong một biến toàn cục.

**Thí nghiệm.**
```bash
# Gọi /users/123 nhiều lần — kết quả không phụ thuộc lần trước. Đó là statelessness.
for i in 1 2 3; do curl -s http://localhost:8080/users/123 | jq -c .; done
```
Suy nghĩ: nếu server không nhớ gì, làm sao nó biết request thứ 2 là "cùng người"
với request thứ 1? (→ câu trả lời ở M6.)

**Tự kiểm.**
- Stateless giúp scale ngang (thêm server) dễ hơn ở điểm nào?
- `Env` trong mini-brig có phải "state của một user" không? Vì sao không?

---

## M6 — Định danh & phiên: cookie vs token

**Khái niệm.**
Vì HTTP stateless (M5), client phải **đính kèm bằng chứng** vào *mỗi* request.
Hai trường phái:
- **Cookie + session**: server cấp một id phiên, lưu state ở server, client gửi
  lại qua header `Cookie`. Trình duyệt tự động đính kèm.
- **Token (vd JWT)**: bằng chứng *tự chứa* mọi thông tin & chữ ký, client gửi
  qua header `Authorization: Bearer <token>`. Server **không cần lưu** gì.

Mini-brig (và brig thật) đi hướng **token** vì hợp với API/mobile và scale tốt.

**Trong mini-brig.**
[API/Server.hs](src/API/Server.hs#L43) đang trả `TokenResponse "stub-token"` —
một token *giả*. Phase 5 sẽ thay bằng JWT thật. Header `Authorization` là nơi
client gửi token đó ngược lên cho các route cần bảo vệ.

**Thí nghiệm.**
```bash
# Lấy token (hiện là stub)
curl -s -X POST http://localhost:8080/login \
  -H 'Content-Type: application/json' -d '{"loginEmail":"a@b.com"}' | jq .

# Gửi token kèm theo ở request sau (chuẩn Bearer)
curl -i http://localhost:8080/users/123 \
  -H 'Authorization: Bearer stub-token'
```
Hiện route chưa kiểm token nên gửi hay không cũng 200 — nhưng hãy *tập thói quen*
nhìn header `Authorization` là "cái thẻ ra vào" của mỗi request.

**Tự kiểm.**
- Vì sao token cho phép server **không lưu** session mà vẫn biết bạn là ai?
- `Bearer` nghĩa là gì? ("ai cầm token này thì được coi là chủ" — nên token rò
  rỉ là nguy hiểm.)

---

## M7 — JWT mổ xẻ: header.payload.signature

**Khái niệm.**
JWT là một chuỗi `xxxxx.yyyyy.zzzzz` gồm 3 phần Base64URL:
- **Header**: thuật toán ký (vd `HS256`/`RS256`).
- **Payload (claims)**: dữ liệu — `sub` (ai), `exp` (hết hạn), `iat` (cấp lúc nào).
- **Signature**: chữ ký mật mã trên (header+payload) bằng secret/khoá riêng.

Điểm mấu chốt người mới hay nhầm: **payload KHÔNG mã hoá**, chỉ *encode* — ai
cũng đọc được. Chữ ký không giấu nội dung, nó chỉ **chống sửa đổi** (đổi payload
thì chữ ký sai). Vì vậy đừng để mật khẩu trong JWT, và bắt buộc dùng HTTPS (M8)
để token không bị nghe lén.

**Trong mini-brig.**
Phase 5 dùng thư viện `jose` ký JWT với `exp` ~1h. Route bảo vệ khai báo
`Auth '[JWT] UserClaims :> ...` — Servant tự verify chữ ký & hạn trước khi gọi
handler; sai → tự trả **401**.

**Thí nghiệm.**
```bash
# Một JWT mẫu (chưa cần server) — tự giải mã payload để thấy nó "trần trụi":
TOKEN='eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1c2VyLTEyMyIsImV4cCI6MTcwMDAwMDAwMH0.x'
echo "$TOKEN" | cut -d. -f2 | base64 --decode 2>/dev/null; echo
# → thấy {"sub":"user-123","exp":...} — KHÔNG mã hoá, chỉ encode!
```
Bài học rút ra bằng mắt: bất kỳ ai chặn được token đều đọc được payload → **phải
có TLS** → dẫn thẳng sang M8.

**Tự kiểm.**
- JWT "không mã hoá nhưng chống giả mạo" — giải thích bằng vai trò của signature.
- Vì sao `exp` (hết hạn) quan trọng? Token không hết hạn nguy hiểm ở đâu?

---

## M8 — HTTPS & TLS: mã hoá đường truyền

**Khái niệm.**
HTTPS = HTTP chạy *bên trong* một kênh **TLS** đã mã hoá. TLS giải 3 bài toán:
- **Bí mật (confidentiality)**: kẻ nghe lén chỉ thấy byte rác.
- **Toàn vẹn (integrity)**: dữ liệu không bị sửa giữa đường.
- **Xác thực (authentication)**: **certificate** chứng minh "server này đúng là
  example.com", do một **CA** (Certificate Authority) đáng tin ký.

Cơ chế lõi: **mã hoá bất đối xứng** (khoá công khai/riêng) dùng lúc *handshake*
để hai bên thoả thuận một **khoá đối xứng** chung, rồi dùng khoá đối xứng (nhanh)
mã hoá toàn bộ dữ liệu sau đó. Đây là ý tưởng đẹp nhất của web bảo mật — hiểu nó
là hiểu vì sao HTTPS vừa an toàn vừa nhanh.

**Trong mini-brig.**
mini-brig chạy HTTP thuần (local nên chấp nhận được). `ca-certificates` trong
[Dockerfile](Dockerfile) tồn tại để khi mini-brig *làm client* gọi HTTPS service
khác (M9) nó có sẵn danh sách CA tin cậy để verify cert đối phương. Production
thật thì TLS thường do **reverse proxy** (M9) đảm nhiệm, không phải Warp.

**Thí nghiệm.**
```bash
# Xem handshake TLS của một site thật, từng bước (cert, cipher, version):
curl -v https://example.com -o /dev/null

# Soi certificate: ai cấp, cho domain nào, hạn đến bao giờ:
echo | openssl s_client -connect example.com:443 -servername example.com 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates
```
So sánh output `curl -v` này với `curl -v http://localhost:8080` ở M1: HTTPS có
thêm hẳn một khối `* TLS handshake` mà HTTP không có — đó chính là "trạm TLS".

**Tự kiểm.**
- Vì sao dùng bất đối xứng để *trao khoá* rồi chuyển sang đối xứng để *truyền dữ
  liệu*, thay vì bất đối xứng suốt? (gợi ý: tốc độ)
- Certificate ngăn được kiểu tấn công nào mà chỉ mã hoá không ngăn được?
  (gợi ý: man-in-the-middle giả danh server)

---

## M9 — REST, gọi service khác & hạ tầng trung gian

**Khái niệm.**
- **REST**: phong cách thiết kế API quanh **resource** (danh từ: `/users/123`)
  và dùng **method** làm động từ (GET/POST/…). URL chỉ *vật*, method chỉ *hành
  động* — đó là vì sao `/users/123` + `DELETE` đọc tự nhiên.
- **HTTP client**: server cũng có thể *là client* gọi server khác (mini-brig gọi
  service notification). Lúc này nó phải tự lo timeout, retry, parse lỗi.
- **Hạ tầng trung gian**: thực tế giữa client và backend thường có **reverse
  proxy / load balancer / API gateway**. Đây là nguồn của các mã `502` (proxy
  không gọi được backend), `503` (quá tải), `504` (backend trả lời quá chậm).

**Trong mini-brig.**
Phase 6 ([[mini-brig-roadmap]]) bạn viết `sendNotification` dùng `http-client` —
lần đầu mini-brig đóng vai **client**. Đây là lúc `ca-certificates` (M8) và xử lý
timeout/lỗi cross-service trở nên thật.

**Thí nghiệm.**
```bash
# Mô phỏng backend "chậm/chết" để hiểu timeout phía client:
curl -m 2 https://httpbin.org/delay/5 ; echo "exit=$?"   # -m 2 = timeout 2s → exit 28

# Nhìn một resource REST điển hình & các method khác nhau trên cùng URL:
curl -s https://httpbin.org/anything/users/123 -X GET    | jq .method
curl -s https://httpbin.org/anything/users/123 -X DELETE | jq .method
```
Quan sát: cùng một URL (cùng *resource*), method khác nhau = ý định khác nhau.
Còn timeout cho thấy vì sao client phải *chủ động* đặt giới hạn chờ.

**Tự kiểm.**
- 502 vs 504 khác nhau ở chỗ nào? (proxy không *gọi được* backend vs backend
  *quá chậm*)
- Vì sao server đóng vai client lại cần `ca-certificates`?

---

## M10 — Mở rộng: caching, CORS, HTTP/2-3, observability

Học sau khi đã vững M0–M9. Mỗi mục là một nhánh đào sâu độc lập:

| Chủ đề | Một câu cốt lõi | Thí nghiệm mồi |
|---|---|---|
| **Caching** | `Cache-Control`/`ETag` cho phép client tái dùng response cũ, đỡ gọi lại server. | `curl -i https://example.com` → soi header `Cache-Control`, `ETag` |
| **CORS** | Cơ chế **trình duyệt** chặn JS gọi cross-origin trừ khi server cho phép qua header `Access-Control-Allow-Origin`. Chỉ ảnh hưởng browser, `curl` miễn nhiễm. | `curl -i -X OPTIONS http://localhost:8080/login -H 'Origin: http://x.com'` |
| **Keep-alive / chunked** | HTTP/1.1 giữ 1 kết nối TCP cho nhiều request; `Transfer-Encoding: chunked` gửi body khi chưa biết tổng kích thước. | tìm `Connection:` và `Transfer-Encoding:` trong `curl -v` ở M1 |
| **HTTP/2 & HTTP/3** | H2 ghép nhiều request song song trên 1 kết nối; H3 chạy trên QUIC/UDP. Ngữ nghĩa HTTP (method/status) **giữ nguyên**. | `curl -sI --http2 https://www.cloudflare.com -o /dev/null -w '%{http_version}\n'` |
| **Observability** | Log mỗi request (method, path, status, thời gian) + `X-Request-Id` để truy vết qua nhiều service. | thêm WAI logger middleware vào [app/Main.hs](app/Main.hs) và xem log |

---

## Lịch học gợi ý (8 tuần, ~3–4 buổi/tuần)

| Tuần | Web module | Làm song song trên mini-brig |
|---|---|---|
| 1 | M0, M1 | Đọc lại Phase 1–2, chạy hết thí nghiệm `nc`/`curl -v` |
| 2 | M2, M3 | Thêm vài route, cố tình tạo 404/405/400 và quan sát |
| 3 | M4 | Viết thêm test JSON round-trip ([test/TypesJSONSpec.hs](test/TypesJSONSpec.hs)) |
| 4 | M5 | Build Phase 3 (App monad), suy ngẫm statelessness |
| 5 | M6, M7 | Build Phase 5 phần JWT, mổ token bằng tay |
| 6 | M8 | Bật TLS local thử (mkcert) hoặc đọc handshake site thật |
| 7 | M9 | Build Phase 6 (gọi service), nghịch timeout/502/504 |
| 8 | M10 | Thêm logging middleware; chọn 1 nhánh đào sâu |

---

## Nguyên tắc xuyên suốt

1. **Quan sát trước, lý thuyết sau.** Mỗi khái niệm phải *nhìn thấy* qua `curl -v`
   trước khi tin.
2. **Mỗi lỗi quy về một trạm** (M1). "Không chạy được" không phải câu trả lời —
   "TCP ok nhưng trả 404" mới là.
3. **HTTP chỉ là text trên TCP** (M0). Khi bí, quay về sự thật trần trụi này.
4. **Một module — một khái niệm.** Đừng nhảy cóc; web xây tầng trên tầng.

---

## Liên kết

- [[mini-brig-roadmap]] — roadmap thiên về Haskell/kiến trúc (chạy song song)
- [[mini-brig-learning-path]] — bản tóm tắt 7 phase
- [[http-web-glossary]] — từ điển tra cứu HTTP/status code khi cần chi tiết
- [[serve-capture-fromhttpapidata]] — cách Servant map request vào type
- [[run-build-curl-threaded]] — build, chạy server và curl thực tế
- [[haskell-glossary]] — thuật ngữ Haskell tổng quát
