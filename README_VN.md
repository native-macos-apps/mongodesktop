# MongoDesktop

[English](README.md) | [Tiếng Việt](README_VN.md)

Một ứng dụng khách (client) MongoDB native, nhẹ nhàng cho hệ điều hành macOS, được xây dựng bằng SwiftUI và MongoDB C Driver.

## Ảnh Chụp Màn Hình

| | | |
|---|---|---|
| <img width="267" alt="Screenshot 2026-06-17 at 17 20 33" src="https://github.com/user-attachments/assets/27e87ff5-9618-4dbc-b1e5-ee464c02c62a" /> | <img width="437" alt="Screenshot 2026-06-17 at 17 21 49" src="https://github.com/user-attachments/assets/f1d657c1-8b3e-42ff-93c6-870bccb2a6a3" /> | <img width="437" alt="Screenshot 2026-06-17 at 17 21 58" src="https://github.com/user-attachments/assets/2bdc2b23-3270-4187-aa61-48aff67c2810" /> |

## Các Tính Năng Chính

- **🚀 Hiệu Suất Native**: Được xây dựng hoàn toàn bằng SwiftUI giúp trải nghiệm mượt mà và tối ưu nhất trên macOS.
- **🔌 Kết Nối Linh Hoạt**: Hỗ trợ đầy đủ các chuỗi kết nối `mongodb://` và `mongodb+srv://` (DNS seed list).
- **📁 Trình Duyệt Database**: Dễ dàng duyệt qua danh sách các database và collection.
- **🔍 Bộ Máy Truy Vấn**: Chạy các truy vấn (query) với hỗ trợ đầy đủ các bộ lọc (filter), sắp xếp (sort) và lựa chọn trường (projection).
- **📑 Giao Diện Thẻ (Tabs)**: Làm việc với nhiều collection hoặc truy vấn cùng một lúc thông qua bố cục thẻ quen thuộc.
- **🛡️ Bảo Mật**: Thông tin kết nối được quản lý an toàn (trong tương lai sẽ tích hợp macOS Keychain).
- **🛠️ Chẩn Đoán DNS**: Tích hợp `DNSDebugService` giúp chẩn đoán các lỗi kết nối phổ biến liên quan đến bản ghi SRV.

## Yêu Cầu Hệ Thống

- macOS 13.0 trở lên (Ventura+)
- Xcode 14.0+ (nếu build từ mã nguồn)
- Thư viện `libmongoc` và `libbson` (MongoDB C Driver)

## Kiến Trúc Kỹ Thuật

MongoDesktop sử dụng kiến trúc Swift hiện đại:
- **SwiftUI**: Cho toàn bộ giao diện người dùng, đảm bảo giao diện chuẩn native.
- **Actors**: Sử dụng mô hình `actor` của Swift trong `MongoService` để đảm bảo an toàn luồng (thread-safe) khi tương tác với trình điều khiển C bên dưới.
- **MongoDB C Driver**: Tận dụng thư viện mạnh mẽ để giao tiếp giao thức ở mức thấp với các máy chủ MongoDB.
- **Bridging**: Cầu nối hiệu suất cao giữa cấu trúc dữ liệu Swift và C (BSON/JSON).

## Bắt Đầu

### Cài Đặt

1. Clone repository:
   ```bash
   git clone https://github.com/yourusername/MongoDesktop.git
   ```
2. Mở `MongoDesktop.xcodeproj` trong Xcode.
3. Build và Chạy (**Cmd + R**).

*Lưu ý: Đảm bảo bạn đã liên kết các phụ thuộc (dependencies) của MongoDB C Driver đúng cách nếu đây là lần đầu tiên build.*

### Sử Dụng

1. **Thêm Kết Nối**: Nhấn nút "+" để thêm một hồ sơ kết nối MongoDB mới.
2. **Kiểm Tra & Lưu**: Nhập URI kết nối của bạn, nhấn "Test" để kiểm tra và lưu lại.
3. **Khám Phá**: Nhấp đúp vào một kết nối đã lưu để mở cửa sổ trình duyệt database.
4. **Truy Vấn**: Chọn một collection và sử dụng thanh truy vấn để tìm kiếm tài liệu.

## Đóng Góp

Mọi đóng góp đều được chào đón! Vui lòng tạo Pull Request hoặc mở Issue nếu bạn phát hiện lỗi hoặc muốn đề xuất tính năng mới.

## Giấy Phép

Dự án này được cấp phép theo Giấy phép MIT - xem tệp [LICENSE](LICENSE) để biết thêm chi tiết.
