# FPTU SE Second Brain (Flutter Desktop)

Ứng dụng desktop quản lý kiến thức ngành **Kỹ thuật phần mềm – Đại học FPT**. Ứng dụng đọc và ghi trực tiếp một **Obsidian vault** (các file `.md` có `[[wikilink]]` và YAML frontmatter), nên dùng song song với Obsidian được.

| Yêu cầu | Đáp ứng bởi |
|---|---|
| Flutter Desktop App | Windows / macOS / Linux, NavigationRail, phím tắt, dark mode |
| File handling | Quét vault, đọc/ghi `.md`, sửa frontmatter, tạo note, chuyển vào `.trash/`, theo dõi thay đổi file (watcher), lưu lịch ôn trong `.fptu/srs.json` |
| AI Integration | Claude API (`claude-opus-5`): tóm tắt note, sinh flashcard (structured JSON output), chat hỏi đáp dựa trên note |
| UI/UX | Material 3, màu FPT, dashboard tiến độ, graph view tương tác, tìm kiếm không dấu, ôn tập bằng bàn phím |

## Tính năng

- **Tổng quan**: số note, số liên kết, tiến độ từng kỳ, các môn đang học, note sửa gần đây, số thẻ đến hạn.
- **Môn học**: lộ trình 9 kỳ, đổi trạng thái (Chưa học / Đang học / Hoàn thành) và ghi thẳng vào `status:` trong frontmatter, cảnh báo khi chưa qua môn tiên quyết.
- **Ghi chú**: cây thư mục, editor Markdown có 3 chế độ (Soạn / Chia đôi / Xem), tự lưu sau 0,7 giây, bấm `[[wikilink]]` để mở note (chưa có thì tự tạo), hiển thị callout, bảng Properties, backlinks, liên kết đi, tags.
- **Tìm kiếm**: full-text không phân biệt dấu ("con tro" ra "Con trỏ"), lọc theo `#tag`.
- **Graph view**: layout force-directed, zoom/pan, di chuột để làm nổi các note lân cận, bấm vào nút để mở note, lọc "Chỉ môn học".
- **Ôn tập**: flashcard viết theo cú pháp `Câu hỏi::Trả lời` (giống plugin Spaced Repetition của Obsidian), lịch ôn theo SM-2, chia bộ thẻ theo môn, phím Space / 1–4 / Esc.
- **Trợ lý AI**: tóm tắt để ôn thi (stream), sinh flashcard rồi chọn thẻ để ghi vào mục `## Flashcards` của note, chat về note đang mở.

## Kiến trúc

```
lib/
├─ main.dart                 # ProviderScope, theme sáng/tối
├─ core/                     # Dart thuần, không phụ thuộc UI, có unit test
│  ├─ markdown_utils.dart    # wikilink, tag, frontmatter, callout, bỏ dấu tiếng Việt
│  ├─ vault_index.dart       # Note, VaultIndex (resolve link, backlinks, search)
│  ├─ vault_repository.dart  # toàn bộ dart:io: đọc/ghi/tạo/trash/watch, srs.json
│  ├─ flashcards.dart        # parse Q::A, thuật toán SM-2
│  ├─ claude_client.dart     # Claude Messages API qua HTTP (SSE streaming + JSON schema)
│  ├─ ai_assistant.dart      # prompt tiếng Việt: tóm tắt / flashcard / chat
│  └─ sample_vault.dart      # sinh vault mẫu FPTU SE
├─ state/providers.dart      # Riverpod: settings, vault, SRS, AI, điều hướng
└─ ui/                       # shell + 7 trang + AI panel
```

Luồng dữ liệu: `VaultRepository` (file) → `VaultNotifier` (Riverpod, dựng `VaultIndex` bất biến) → các trang UI. Khi ghi file, app cập nhật index ngay mà không quét lại cả vault. Khi file bị sửa từ bên ngoài (ví dụ trong Obsidian), watcher chỉ đọc lại đúng file đó. Editor chỉ nạp lại nội dung khi không có thay đổi chưa lưu.

## Quy ước dữ liệu trong vault

```markdown
---
type: course          # course | concept
code: PRM392
name: Mobile Programming
semester: 7
status: learning      # todo | learning | done
prerequisites: [PRO192]
tags: [course, ky7]
---
# PRM392 — Mobile Programming
- [[Vòng đời Widget trong Flutter]]

## Flashcards
Nên khởi tạo TextEditingController ở đâu?::initState()
```

- `.fptu/srs.json`: lịch ôn của từng thẻ. Obsidian bỏ qua thư mục bắt đầu bằng dấu chấm.
- `.trash/`: note đã xóa trong app.
- API key chỉ lưu trên máy (SharedPreferences), không nằm trong vault.

> Danh sách môn trong vault mẫu chỉ để tham khảo. Curriculum khác nhau giữa các khóa, hãy đối chiếu với FAP.

## Phát hành & cập nhật

- **CI** (`.github/workflows/ci.yml`): mỗi lần push lên `main` hoặc mở pull request, GitHub chạy `flutter analyze` và `flutter test`.
- **Release** (`.github/workflows/release.yml`): đẩy tag phiên bản thì GitHub build bản Windows, nén zip và tạo Release.
  1. Tăng `version:` trong `pubspec.yaml` (ví dụ `1.1.0+2`), commit và push.
  2. `git tag v1.1.0`, rồi `git push origin v1.1.0`. Tag phải trùng với version, nếu không workflow sẽ dừng.
- **Tự kiểm tra cập nhật**: mỗi lần mở, app hỏi GitHub có Release mới hơn không và hiện "Có bản x.y.z, tải về?". Có thể kiểm tra thủ công trong Cài đặt → Phiên bản. Chỉ hoạt động khi repo để Public.

## Lộ trình phát triển tiếp

- [ ] Đổi tên note và tự cập nhật mọi `[[link]]` trỏ tới nó
- [x] Gợi ý tự động khi gõ `[[` trong editor
- [ ] Quick switcher (Ctrl+O)
- [ ] Hiển thị ảnh nhúng `![[image.png]]` từ vault
- [ ] AI: hỏi đáp trên toàn vault (RAG), sinh đề trắc nghiệm kiểu FE theo môn
- [ ] Thống kê ôn tập (heatmap, retention), xuất/nhập bộ thẻ
- [ ] Đóng gói bản cài `.msix` cho Windows
