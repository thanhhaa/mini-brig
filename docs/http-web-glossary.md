# HTTP & Web — Thuật ngữ và mã trạng thái

> Tổng hợp các khái niệm HTTP/HTTPS gặp khi build và test mini-brig,
> từ góc nhìn Android developer tiếp cận backend lần đầu.

---

## Kiến trúc HTTP cơ bản

| Thuật ngữ | Định nghĩa |
|-----------|-----------|
| **HTTP** (HyperText Transfer Protocol) | Giao thức giao tiếp giữa client và server. Client gửi **request**, server trả **response**. Mọi curl bạn chạy đều là một HTTP request. |
| **HTTPS** | HTTP + **TLS** (mã hoá). Data truyền qua mạng được mã hoá, không ai nghe lén được. mini-brig dùng HTTP thuần (không có TLS) vì chạy local — production thì cần HTTPS. |
| **TLS** (Transport Layer Security) | Lớp mã hoá bên dưới HTTPS. Certificate (`ca-certificates` trong Dockerfile) dùng để xác thực server là thật, không phải kẻ giả mạo. |
| **Client** | Bên gửi request — curl, Postman, app mobile, trình duyệt. |
| **Server** | Bên nhận request và trả response — mini-brig chạy trong container là một server. |
| **Port** | "Cửa" trên máy để phân biệt nhiều service. mini-brig dùng port `8080`. Một máy có 65535 port; HTTP mặc định 80, HTTPS mặc định 443. |
| **localhost** | Địa chỉ trỏ về chính máy bạn (`127.0.0.1`). `curl localhost:9090` = gọi service đang chạy trên máy bạn, không ra internet. |

---

## Cấu trúc HTTP Request

```
POST /login HTTP/1.1          ← Request line: method + path + version
Host: localhost:9090           ← Header
Content-Type: application/json ← Header
                               ← Dòng trống ngăn header và body
{"loginEmail":"a@b.com"}       ← Body (chỉ có ở POST/PUT/PATCH)
```

| Thành phần | Ý nghĩa |
|-----------|---------|
| **Method** | Hành động: GET, POST, PUT, PATCH, DELETE (xem bảng bên dưới) |
| **Path** | Đường dẫn resource: `/login`, `/users/123` |
| **Headers** | Metadata của request: kiểu dữ liệu, auth token, encoding… |
| **Body** | Dữ liệu gửi kèm. GET không có body; POST/PUT có. |

---

## HTTP Methods

| Method | Dùng để | Body? | Analogy Android |
|--------|---------|-------|-----------------|
| **GET** | Lấy dữ liệu | Không | Đọc SharedPreferences |
| **POST** | Tạo mới | Có | Insert vào Room DB |
| **PUT** | Thay thế toàn bộ | Có | Update toàn bộ record |
| **PATCH** | Cập nhật một phần | Có | Update một vài field |
| **DELETE** | Xoá | Không | Delete khỏi Room DB |

---

## HTTP Headers thường gặp

| Header | Ý nghĩa | Ví dụ |
|--------|---------|-------|
| **Content-Type** | Kiểu dữ liệu của body | `application/json`, `text/html` |
| **Accept** | Client muốn nhận kiểu dữ liệu nào | `application/json` |
| **Authorization** | Token xác thực | `Bearer stub-token` |
| **Transfer-Encoding** | Cách truyền body | `chunked` = gửi từng mảnh, không biết trước kích thước |
| **Date** | Thời điểm server tạo response | `Mon, 08 Jun 2026 17:05:54 GMT` |
| **Server** | Phần mềm HTTP server | `Warp/3.4.13.1` |

---

## Mã trạng thái HTTP (Status Codes)

### 2xx — Thành công

| Code | Tên | Ý nghĩa |
|------|-----|---------|
| **200** | OK | Request thành công, có data trả về. Mọi API của mini-brig đang trả 200. |
| **201** | Created | Tạo resource mới thành công (POST /register lý tưởng nên trả 201). |
| **204** | No Content | Thành công nhưng không có gì để trả (vd DELETE). |

### 3xx — Chuyển hướng

| Code | Tên | Ý nghĩa |
|------|-----|---------|
| **301** | Moved Permanently | URL đã đổi vĩnh viễn, dùng URL mới. |
| **302** | Found | Chuyển hướng tạm thời. |
| **304** | Not Modified | Resource chưa thay đổi, dùng cache. |

### 4xx — Lỗi từ phía client

| Code | Tên | Ý nghĩa | Gặp ở mini-brig |
|------|-----|---------|-----------------|
| **400** | Bad Request | Request sai — sai JSON format, thiếu field bắt buộc. | Gửi sai body JSON |
| **401** | Unauthorized | Chưa xác thực — thiếu hoặc sai token. | Chưa implement |
| **403** | Forbidden | Đã xác thực nhưng không có quyền. | Chưa implement |
| **404** | Not Found | Path không tồn tại. | Gọi `/loginnnnn` |
| **405** | Method Not Allowed | Đúng path nhưng sai method (GET thay vì POST). | |
| **409** | Conflict | Xung đột — vd email đã tồn tại khi register. | Chưa implement |
| **422** | Unprocessable Entity | Đúng format JSON nhưng dữ liệu không hợp lệ về nghĩa. | |
| **429** | Too Many Requests | Gửi request quá nhiều, bị rate limit. | |

### 5xx — Lỗi từ phía server

| Code | Tên | Ý nghĩa |
|------|-----|---------|
| **500** | Internal Server Error | Server crash hoặc bug không xử lý được. |
| **502** | Bad Gateway | Server trung gian (proxy/load balancer) không liên lạc được backend. |
| **503** | Service Unavailable | Server quá tải hoặc đang bảo trì. |
| **504** | Gateway Timeout | Backend không phản hồi kịp thời. |

---

## Warp và WAI

| Thuật ngữ | Định nghĩa |
|-----------|-----------|
| **Warp** | HTTP server của Haskell — thư viện nhận kết nối TCP, parse HTTP request, rồi chuyển cho ứng dụng xử lý. Tương tự Netty (Android/Java) hay Nginx. Dòng `Server: Warp/3.4.13.1` trong response header cho biết server đang dùng Warp. |
| **WAI** (Web Application Interface) | Interface chuẩn của Haskell định nghĩa `Application = Request -> (Response -> IO ResponseReceived) -> IO ResponseReceived`. Servant tạo ra một `Application`, Warp chạy nó. Tương tự interface `HttpHandler` trong Java Servlet. |
| **`run 8080 app`** | Lệnh trong `Main.hs`: bảo Warp lắng nghe port 8080 và chuyển mọi request vào `app` (WAI Application do Servant tạo). |

---

## Servant (Haskell web framework)

| Thuật ngữ | Định nghĩa |
|-----------|-----------|
| **Servant** | Web framework của Haskell. Định nghĩa API **ở tầng type** — compiler kiểm tra handler đúng kiểu tại compile time, không phải runtime. |
| **Route matching** | Servant so khớp path + method + Content-Type trước khi gọi handler. Không khớp → 404 hoặc 405 tự động, không cần code. |
| **ReqBody** | Khai báo trong route type: "endpoint này nhận JSON body và deserialize thành kiểu T". Nếu parse fail → Servant tự trả 400 với error message. |
| **Handler** | Hàm Haskell xử lý một endpoint, kiểu `Handler a`. Hiện tại toàn bộ là stub — trả data cứng, chưa có logic thật. |

---

## Liên kết

- [[haskell-glossary]] — thuật ngữ Haskell tổng quát
- [[serve-capture-fromhttpapidata]] — Servant route type, Capture, FromHttpApiData
- [[run-build-curl-threaded]] — build, chạy server và curl thực tế
