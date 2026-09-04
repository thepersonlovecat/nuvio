# 📖 Hướng Dẫn Phát Triển Manga Add-on Cho Nuvio iOS

Tài liệu này cung cấp đặc tả kỹ thuật và hướng dẫn chi tiết để các nhà phát triển cộng đồng có thể tự viết và phân phối **Manga Add-on (Extension)** dành riêng cho tính năng đọc truyện tranh trên **Nuvio iOS**.

---

## 🌟 1. Tổng Quan Kiến Trúc

Hệ sinh thái Nuvio iOS áp dụng cơ chế **Decoupled Add-on (Add-on Độc lập)**:
- **Tính cách ly tuyệt đối**: Manga Add-on chỉ xuất hiện và hoạt động trong tab **"Truyện Tranh"**, hoàn toàn không ảnh hưởng hay hiển thị ở trang **Home** (Trang chủ phim).
- **Phân phối không chạm**: Người dùng chỉ cần dán đường dẫn link URL file `manifest.json` (từ GitHub, Vercel, Cloudflare...) là ứng dụng tự động tải và kích hoạt nguồn truyện ngay lập tức.
- **2 phương thức phát triển**:
  1. **REST API Endpoint**: Máy chủ của bạn trả về dữ liệu chuẩn JSON.
  2. **JavaScriptCore Script (Provider-Z compatible)**: Chạy file `.js` trực tiếp trên thiết bị để crawl/parse dữ liệu từ web.

---

## 📋 2. Cấu Trúc Manifest (`manifest.json`)

Mỗi Add-on truyện bắt buộc phải có một file manifest dạng JSON:

```json
{
  "id": "my-manga-source",
  "name": "Nguồn Truyện Của Tôi",
  "version": "1.0.0",
  "description": "Cập nhật các bộ manga, manhwa, manhua vietsub mới nhất mỗi ngày.",
  "author": "YourName",
  "baseUrl": "https://api.example.com",
  "icon": "https://example.com/icon.png",
  "type": "provider_z_json",
  "endpoints": {
    "home": "/v1/home",
    "search": "/v1/search?q={query}",
    "detail": "/v1/manga/{id}",
    "chapter": "/v1/chapter/{id}"
  }
}
```

### Giải thích các trường:
| Trường | Bắt buộc | Kiểu | Mô tả |
| :--- | :---: | :--- | :--- |
| `id` | Có | String | Mã định danh duy nhất (chữ thường, gạch nối, không dấu). Ví dụ: `truyenhay-vn`. |
| `name` | Có | String | Tên hiển thị của Add-on trên giao diện Nuvio. |
| `version` | Có | String | Phiên bản (Semantic Versioning: `1.0.0`). |
| `baseUrl` | Có | String | Địa chỉ gốc của server API (bắt buộc `https://`). |
| `description`| Không | String | Mô tả ngắn gọn về nguồn truyện hoặc nhóm dịch. |
| `icon` | Không | String | Link ảnh đại diện vuông cho Add-on (khuyến nghị 128x128). |
| `type` | Có | String | `built_in`, `provider_z_json`, hoặc `custom_rest`. |

---

## 📡 3. Đặc Tả Các API Endpoint

Để Nuvio iOS hiển thị và đọc được truyện, API của bạn cần hỗ trợ các route sau:

### 3.1. Danh Sách Trang Chủ (`GET /home`)
Trả về danh sách truyện mới nhất hoặc thịnh hành.

**Response (JSON):**
```json
[
  {
    "id": "one-piece",
    "title": "One Piece (Đảo Hải Tặc)",
    "cover": "https://cdn.example.com/covers/one-piece.jpg",
    "url": "https://api.example.com/v1/manga/one-piece",
    "status": "Đang tiến hành",
    "genres": ["Hành động", "Phiêu lưu", "Hài hước"],
    "authors": ["Eiichiro Oda"]
  }
]
```

---

### 3.2. Tìm Kiếm Truyện (`GET /search?q={keyword}`)
Được gọi khi người dùng nhập từ khóa vào thanh tìm kiếm.

**Response (JSON):** Tương tự danh sách trang chủ (Mảng các `MangaItem`).

---

### 3.3. Chi Tiết Truyện & Danh Sách Chương (`GET /manga/{id}`)
Cung cấp thông tin chi tiết của bộ truyện cùng danh sách tất cả các chapter để người dùng chọn đọc.

**Response (JSON):**
```json
{
  "id": "one-piece",
  "title": "One Piece (Đảo Hải Tặc)",
  "cover": "https://cdn.example.com/covers/one-piece.jpg",
  "description": "Câu chuyện về Monkey D. Luffy và giấc mơ trở thành Vua Hải Tặc.",
  "status": "Đang tiến hành",
  "genres": ["Hành động", "Phiêu lưu"],
  "authors": ["Eiichiro Oda"],
  "chapters": [
    {
      "id": "1110",
      "title": "Chương 1110: Ngũ Lão Tinh Xuất Hiện",
      "chapter_name": "1110",
      "url": "https://api.example.com/v1/chapter/1110",
      "date": "2026-04-01"
    },
    {
      "id": "1109",
      "title": "Chương 1109: Thông Điệp Toàn Cầu",
      "chapter_name": "1109",
      "url": "https://api.example.com/v1/chapter/1109",
      "date": "2026-03-20"
    }
  ]
}
```

---

### 3.4. Danh Sách Trang Ảnh Của Chapter (`GET /chapter/{id}`)
Trả về danh sách URL các trang ảnh để trình đọc `MangaReaderView` hiển thị (hỗ trợ cuộn dọc Webtoon và lật trang Manga).

**Response (JSON):**
```json
{
  "data": {
    "domain_cdn": "https://cdn.example.com",
    "item": {
      "chapter_path": "one-piece/1110",
      "chapter_image": [
        { "image_file": "page_01.jpg" },
        { "image_file": "page_02.jpg" },
        { "image_file": "page_03.jpg" }
      ]
    }
  }
}
```
*Lưu ý: Nuvio iOS cũng tự động hỗ trợ mảng chuỗi URL trực tiếp:*
```json
{
  "pages": [
    "https://cdn.example.com/pages/01.jpg",
    "https://cdn.example.com/pages/02.jpg"
  ]
}
```

---

## ⚡ 4. Hướng Dẫn Viết Provider Bằng JavaScript (Chuẩn Provider-Z)

Nếu bạn không có server API riêng mà muốn crawl trực tiếp từ web truyện tranh, bạn có thể tạo file `provider.js` và nhúng vào Add-on. Nuvio sẽ thực thi qua engine `JavaScriptCore` native:

```javascript
// provider.js

function getHome() {
    // 1. Tải HTML hoặc gọi API
    // 2. Trả về mảng JSON
    return [
        {
            id: "manga-slug",
            title: "Tên Truyện",
            cover: "https://.../cover.jpg",
            url: "https://.../manga-slug"
        }
    ];
}

function search(keyword) {
    // Tìm kiếm theo từ khóa
    return [];
}

function getDetail(mangaId) {
    // Lấy danh sách chapters
    return {
        id: mangaId,
        title: "...",
        chapters: [
            { id: "1", title: "Chapter 1", url: "..." }
        ]
    };
}

function getPages(chapterUrl) {
    // Trả về danh sách link ảnh
    return [
        { index: 0, url: "https://.../page1.jpg" },
        { index: 1, url: "https://.../page2.jpg" }
    ];
}
```

---

## 🚀 5. Phân Phối Và Cài Đặt Lên App

1. **Đăng tải file Manifest**:
   - Tải file `manifest.json` lên bất kỳ dịch vụ hosting nào hỗ trợ HTTPS công khai (ví dụ: GitHub Repository, GitHub Gist Raw, Vercel, Cloudflare Pages, Pastebin).
   - Ví dụ link: `https://raw.githubusercontent.com/username/my-nuvio-addon/main/manifest.json`

2. **Cài đặt vào Nuvio iOS**:
   - Mở ứng dụng **Nuvio** trên iPhone / iPad.
   - Chuyển sang tab **"Truyện Tranh"**.
   - Bấm vào biểu tượng **Mảnh ghép Add-on (🧩)** ở góc trên bên phải thanh điều hướng.
   - Dán link URL file `manifest.json` vào ô và bấm **"Cài đặt Add-on"**.
   - Nguồn truyện của bạn sẽ xuất hiện ngay trong danh sách và sẵn sàng đọc!

---

## 🛡️ 6. Bảo Mật & Best Practices
- **Bắt buộc HTTPS**: Tất cả các URL ảnh và API phải sử dụng chứng chỉ SSL hợp lệ.
- **Tối ưu ảnh (CDN)**: Khuyến khích sử dụng định dạng WebP hoặc JPEG nén để tối ưu tốc độ đọc trên thiết bị di động.
- **Xử lý Anti-hotlinking / Referer**: Nếu nguồn truyện yêu cầu `Referer Header`, bạn có thể chỉ định trong thuộc tính `headers` của từng trang ảnh để app tự động đính kèm khi tải.
