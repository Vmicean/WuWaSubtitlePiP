# Hướng Dẫn Cài Đặt WuWaSubtitlePiP Lên iPhone 14 Pro Max Từ Windows (100% Miễn Phí & Ngoại Tuyến)

Ứng dụng **WuWa Dịch PiP (WuWaSubtitlePiP)** giúp dịch phụ đề tiếng Anh sang tiếng Việt theo thời gian thực khi chơi **Wuthering Waves** trên **iPhone 14 Pro Max (iOS 18.0+)** — hoàn toàn miễn phí, không cần máy Mac, không cần API key, và chạy **100% ngoại tuyến** nhờ Apple Vision OCR + Apple Translation (iOS 18+).

---

## 1. Chuẩn bị trước khi bắt đầu

1. **Máy tính Windows 10/11** có kết nối Internet và trình duyệt web.
2. **Tài khoản GitHub miễn phí** tại [github.com](https://github.com) (dùng để chạy GitHub Actions `macos-15` biên dịch tự động sang tệp `.ipa`).
3. **iPhone 14 Pro Max chạy iOS 18.0 trở lên** đã cài sẵn **SideStore** (hoặc AltStore / Sideloadly) bằng Apple ID miễn phí.
   - *Lưu ý Free Apple ID:* Apple cho phép tối đa **3 App ID hoạt động cùng lúc**. **WuWa Dịch PiP** dùng đúng **2 App ID** (1 cho ứng dụng chính + 1 cho `WuWaBroadcastExtension`), vì vậy hãy chắc chắn bạn còn ít nhất 2 slot trống trong SideStore.

---

## 2. Đưa mã nguồn dự án lên GitHub từ Windows

### Cách A: Tải thẳng trên web GitHub (Không cần gõ lệnh)
1. Đăng nhập [github.com](https://github.com) → bấm dấu **+** góc trên bên phải → chọn **New repository**.
2. Đặt tên kho là `WuWaSubtitlePiP`, chọn **Private** hoặc **Public**, rồi bấm **Create repository**.
3. Giải nén toàn bộ thư mục dự án `WuWaSubtitlePiP` trên máy Windows của bạn, đảm bảo bên trong có đầy đủ:
   - `project.yml`
   - `.github/workflows/build-ipa.yml`
   - Thư mục `Shared/`
   - Thư mục `BroadcastExtension/`
   - Thư mục `WuWaSubtitlePiP/`
   - Thư mục `Tests/`
4. Chọn **uploading an existing file**, kéo thả toàn bộ tệp và thư mục (bao gồm cả thư mục ẩn `.github`) lên rồi bấm **Commit changes**.

### Cách B: Dùng Git trên Windows PowerShell (Khuyên dùng — không bị sót thư mục ẩn `.github`)
Mở **PowerShell** bên trong thư mục `WuWaSubtitlePiP` và chạy:

```powershell
git init
git add .
git commit -m "Initial WuWaSubtitlePiP iOS 18 project"
git branch -M main
git remote add origin https://github.com/<TEN-GITHUB-CUA-BAN>/WuWaSubtitlePiP.git
git push -u origin main
```

---

## 3. Tự động biên dịch & tải tệp `WuWaSubtitlePiP-unsigned.ipa`

1. Vào kho lưu trữ `WuWaSubtitlePiP` trên GitHub → chọn tab **Actions**.
2. Bấm vào workflow **Build WuWaSubtitlePiP Unsigned IPA**.
   - Nếu workflow chưa tự chạy, bấm nút **Run workflow** → **Run workflow**.
3. Chờ khoảng **4–6 phút** để máy chủ `macos-15` của GitHub thực hiện tự động:
   - Cài `XcodeGen` và sinh `WuWaSubtitlePiP.xcodeproj`.
   - Chạy toàn bộ bộ kiểm thử `WuWaSubtitlePiPTests` trên iOS 18 Simulator.
   - Biên dịch bản Release `iphoneos` và kiểm tra `WuWaBroadcastExtension.appex` nằm trong `PlugIns/`.
   - Đóng gói thành tệp `WuWaSubtitlePiP-unsigned.ipa`.
4. Khi thấy dấu tích xanh lá, kéo xuống mục **Artifacts** ở cuối trang và bấm tải **`WuWaSubtitlePiP-unsigned-ipa`**.
5. Giải nén tệp `.zip` vừa tải để lấy tệp **`WuWaSubtitlePiP-unsigned.ipa`**.

---

## 4. Cài đặt lên iPhone 14 Pro Max bằng SideStore

1. Gửi tệp `WuWaSubtitlePiP-unsigned.ipa` sang iPhone (qua iCloud Drive, Google Drive, Telegram Saved Messages, LocalSend hoặc cáp USB) và lưu vào ứng dụng **Tệp (Files)**.
2. Bật **WireGuard VPN** của SideStore trên iPhone.
3. Mở **SideStore** → chuyển sang tab **My Apps** → bấm dấu **+** ở góc trên bên trái → chọn tệp `WuWaSubtitlePiP-unsigned.ipa`.
4. **BƯỚC CỰC KỲ QUAN TRỌNG:**
   Khi SideStore hiện hộp thoại hỏi về phần mở rộng ứng dụng (**App Extensions**):
   > **BẮT BUỘC CHỌN: `Keep App Extensions` (Giữ lại App Extensions)**
   
   *Nếu bạn lỡ bấm Remove App Extensions, thành phần `WuWaBroadcastExtension` sẽ bị xóa và iPhone sẽ không thể quét màn hình Wuthering Waves!*
5. Chờ SideStore ký lại bằng Apple ID của bạn và cài đặt hoàn tất (biểu tượng **WuWa Dịch PiP** sẽ xuất hiện trên màn hình chính).

---

## 5. Thiết lập lần đầu & Chơi Wuthering Waves có phụ đề tiếng Việt nổi

### Bước 1: Tải gói ngôn ngữ ngoại tuyến (Chỉ cần làm 1 lần duy nhất)
1. Mở ứng dụng **WuWa Dịch PiP** trên iPhone.
2. Tại **Bước 1**, bấm nút **Tải gói dịch ngoại tuyến Anh – Việt**.
3. Khi iOS 18 hiện bảng tải ngôn ngữ miễn phí của Apple (English + Tiếng Việt), bấm **Tải về (Download)**.
4. Chờ trạng thái chuyển sang chấm xanh **Sẵn sàng** (*Đã cài đặt gói ngoại tuyến Anh → Việt*). Từ lúc này bạn có thể dịch hoàn toàn ngoại tuyến!

### Bước 2: Thử & Bật cửa sổ phụ đề nổi (PiP)
1. Bấm **Chạy thử phụ đề trên PiP** để xem trước kiểu chữ tiếng Việt, tên nhân vật màu vàng kim và độ mờ nền.
   - Bạn có thể sang tab **Lịch sử & Cài đặt** để tăng/giảm cỡ chữ, độ mờ nền hoặc bật/tắt câu gốc tiếng Anh.
   - Sang tab **Vùng quét** nếu muốn chọn **Khung thoại + Lựa chọn** thay vì **Khung thoại WuWa mặc định**.
2. Bấm **Bật cửa sổ phụ đề PiP**. Cửa sổ phụ đề nổi sẽ xuất hiện ngay lập tức.

### Bước 3: Bắt đầu quét màn hình & Mở Wuthering Waves
1. Tại **Bước 3**, chạm vào biểu tượng **Phát màn hình** màu vàng.
2. Chọn **WuWaBroadcastExtension** → bấm **Bắt đầu phát sóng (Start Broadcast)** và chờ đếm ngược `3 - 2 - 1`.
3. Vuốt về màn hình chính và mở **Wuthering Waves**.
4. Xoay ngang iPhone 14 Pro Max:
   - Cửa sổ phụ đề PiP tự động thu gọn nổi gọn gàng trên góc màn hình.
   - Bạn có thể **kéo thả** cửa sổ PiP lên góc trên (tránh che hộp thoại game) và **chụm/phóng hai ngón tay** để chỉnh kích thước to nhỏ tùy ý.
   - Âm thanh trong Wuthering Waves phát hoàn toàn bình thường (không bị tắt tiếng nhờ cấu hình `.mixWithOthers`).

---

## 6. Mẹo khắc phục sự cố thường gặp

- **Không thấy `WuWaBroadcastExtension` trong danh sách Phát màn hình:**
  Bạn đã chọn nhầm *Remove App Extensions* khi cài bằng SideStore. Hãy gỡ ứng dụng, cài lại từ tệp `.ipa` và chọn **Keep App Extensions**.
- **Mục Chẩn đoán báo "Loopback nội bộ 127.0.0.1:47891":**
  Đây là cơ chế dự phòng thông minh dành riêng cho Free Apple ID khi App Group không được cấp. Ứng dụng vẫn truyền phụ đề bình thường theo thời gian thực — bạn không cần chỉnh sửa gì thêm!
- **Bản dịch chưa khớp vị trí hộp thoại khi có nhánh lựa chọn:**
  Mở tab **Vùng quét** → chọn mẫu **Khung thoại + Lựa chọn** (hoặc kéo thanh trượt **Cạnh trên** lên khoảng `44%`).
- **Hết hạn 7 ngày của Free Apple ID:**
  Bật WireGuard và bấm **Refresh All** trong SideStore (hoặc đặt phím tắt tự động làm mới) trước ngày thứ 7 để giữ ứng dụng hoạt động liên tục.
