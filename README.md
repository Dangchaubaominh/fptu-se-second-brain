# FPTU SE Second Brain (Flutter Desktop)

Ứng dụng desktop quản lý kiến thức ngành **Kỹ thuật phần mềm – Đại học FPT**. Ứng dụng đọc và ghi trực tiếp một **Obsidian vault** (các file `.md` có `[[wikilink]]` và YAML frontmatter), nên dùng song song với Obsidian được.

| Yêu cầu | Đáp ứng bởi |
|---|---|
| Flutter Desktop App | Windows / macOS / Linux, NavigationRail, phím tắt, dark mode, bản cài `.msix` cho Windows |
| File handling | Quét vault, đọc/ghi `.md`, sửa frontmatter, tạo/đổi tên note (tự cập nhật link), chèn ảnh vào `attachments/`, chuyển vào `.trash/`, theo dõi thay đổi file (watcher), xuất/nhập bộ thẻ TSV/CSV, lưu lịch ôn và nhật ký trong `.fptu/` |
| AI Integration | Claude API (`claude-opus-5`): tóm tắt note, sinh flashcard, chat về note, hỏi đáp trên toàn vault có trích nguồn, sinh đề trắc nghiệm kiểu FE (structured JSON output + prompt caching) |
| UI/UX | Material 3, màu FPT, dashboard tiến độ, graph view tương tác, tìm kiếm không dấu, gợi ý `[[`, quick switcher, ôn tập bằng bàn phím, thống kê heatmap |

## Tính năng

- **Tổng quan**: số note, số liên kết, tiến độ từng kỳ, các môn đang học, note sửa gần đây, số thẻ đến hạn.
- **Môn học**: lộ trình 9 kỳ, đổi trạng thái (Chưa học / Đang học / Hoàn thành) và ghi thẳng vào `status:` trong frontmatter, cảnh báo khi chưa qua môn tiên quyết.
- **Ghi chú**
  - Cây thư mục, editor Markdown 3 chế độ (Soạn / Chia đôi / Xem), tự lưu sau 0,7 giây.
  - Gõ `[[` để được gợi ý note (không dấu, theo alias). Bấm `[[wikilink]]` để mở note, chưa có thì tự tạo.
  - **Đổi tên note** (menu ⋮): mọi `[[link]]` trỏ tới note trong vault được cập nhật theo, giữ nguyên `#heading` và `|alias`. Link viết bằng alias không bị đổi. Lịch ôn flashcard của note được giữ lại.
  - **Ảnh nhúng**: hiển thị `![[ảnh.png]]`, `![[ảnh.png|300]]` (rộng 300px) và `![](đường/dẫn.png)`. Nút "Chèn ảnh" chép ảnh vào `attachments/` rồi chèn link.
  - Callout, bảng Properties, backlinks, liên kết đi, tags.
- **Tìm kiếm**: full-text không phân biệt dấu ("con tro" ra "Con trỏ"), lọc theo `#tag`. **Ctrl+O** mở quick switcher để nhảy nhanh tới note hoặc tạo note mới.
- **Graph view**: layout force-directed, zoom/pan, di chuột để làm nổi các note lân cận, bấm vào nút để mở note, lọc "Chỉ môn học".
- **Ôn tập**
  - Flashcard viết theo cú pháp `Câu hỏi::Trả lời` (giống plugin Spaced Repetition của Obsidian), lịch ôn SM-2, chia bộ thẻ theo môn, phím Space / 1–4 / Esc.
  - **Thống kê**: chuỗi ngày ôn, số lượt hôm nay, tỉ lệ nhớ 30 ngày, số thẻ mới / đang học / thuộc lâu (≥ 21 ngày), heatmap 20 tuần, dự báo thẻ đến hạn 7 ngày.
  - **Xuất** bộ thẻ sang file TSV nhập thẳng vào Anki. **Nhập** từ TSV/CSV (Anki, Quizlet, Excel, kể cả CSV dùng dấu `;`) thành note mới trong `Flashcards/`.
- **Hỏi AI** (trang riêng)
  - Hỏi đáp trên **toàn bộ vault** hoặc **một môn** (note môn + các note liên kết). Claude trả lời kèm nguồn `[[Tên note]]` bấm được.
  - **Đề trắc nghiệm kiểu FE**: chọn 5/10/20 câu, làm bài, nộp để chấm điểm và xem giải thích. Lưu đề thành note trong `Quizzes/`, đáp án giấu trong callout thu gọn.
  - Ghi chú được gửi dưới dạng system prompt có **prompt caching**, nên các câu hỏi sau rẻ và nhanh hơn. Nếu vault vượt giới hạn (~600k ký tự), app chọn các note liên quan nhất và hiển thị rõ những note bị bỏ ra.
- **Trợ lý AI trong note**: tóm tắt để ôn thi (stream), sinh flashcard rồi chọn thẻ ghi vào mục `## Flashcards`, chat về note đang mở.

## Kiến trúc

```
lib/
├─ main.dart                   # ProviderScope, theme sáng/tối
├─ core/                       # Dart thuần, không phụ thuộc UI, có unit test
│  ├─ markdown_utils.dart      # wikilink, tag, frontmatter, callout, ảnh nhúng, bỏ dấu tiếng Việt
│  ├─ vault_index.dart         # Note, VaultIndex (resolve link/ảnh, backlinks, search)
│  ├─ vault_repository.dart    # toàn bộ dart:io: đọc/ghi/tạo/đổi tên/trash/watch, ảnh, .fptu/*.json
│  ├─ rename.dart              # kế hoạch đổi tên + viết lại link
│  ├─ wikilink_completion.dart # gợi ý [[ và xếp hạng note (dùng chung với quick switcher)
│  ├─ flashcards.dart          # parse Q::A, thuật toán SM-2
│  ├─ review_stats.dart        # nhật ký ôn tập, streak, retention, dự báo
│  ├─ deck_io.dart             # xuất TSV (Anki), nhập TSV/CSV
│  ├─ claude_client.dart       # Claude Messages API qua HTTP (SSE streaming, JSON schema, prompt caching)
│  ├─ ai_assistant.dart        # prompt tiếng Việt: tóm tắt / flashcard / chat / hỏi vault / đề trắc nghiệm
│  ├─ vault_ai.dart            # chọn ngữ cảnh gửi AI, mô hình câu hỏi, xuất đề ra Markdown
│  ├─ update_checker.dart      # hỏi GitHub Releases có bản mới không
│  └─ sample_vault.dart        # sinh vault mẫu FPTU SE
├─ state/providers.dart        # Riverpod: settings, vault, SRS, nhật ký ôn, AI, điều hướng
└─ ui/                         # shell + 8 trang, editor có gợi ý, quick switcher, AI panel, thống kê
```

Luồng dữ liệu: `VaultRepository` (file) → `VaultNotifier` (Riverpod, dựng `VaultIndex` bất biến) → các trang UI. Khi ghi file, app cập nhật index ngay mà không quét lại cả vault. Khi file bị sửa từ bên ngoài (ví dụ trong Obsidian), watcher chỉ đọc lại đúng file đó. Editor chỉ nạp lại nội dung khi không có thay đổi chưa lưu.

## Quy ước dữ liệu trong vault

```markdown
---
type: course          # course | concept | deck | quiz
code: PRM392
name: Mobile Programming
semester: 7
status: learning      # todo | learning | done
prerequisites: [PRO192]
tags: [course, ky7]
---
# PRM392 — Mobile Programming
- [[Vòng đời Widget trong Flutter]]
![[widget-lifecycle.png|400]]

## Flashcards
Nên khởi tạo TextEditingController ở đâu?::initState()
```

| Đường dẫn | Nội dung |
|---|---|
| `Courses/`, `Concepts/` | Note môn học và khái niệm (vault mẫu) |
| `attachments/` | Ảnh chèn từ app |
| `Flashcards/` | Bộ thẻ nhập từ TSV/CSV |
| `Quizzes/` | Đề trắc nghiệm đã lưu |
| `.fptu/srs.json` | Lịch ôn của từng thẻ |
| `.fptu/review_log.json` | Nhật ký các lượt ôn (dùng cho thống kê) |
| `.trash/` | Note đã xóa trong app |

- Obsidian bỏ qua các thư mục bắt đầu bằng dấu chấm.
- API key chỉ lưu trên máy (SharedPreferences), không nằm trong vault.

> Danh sách môn trong vault mẫu chỉ để tham khảo. Curriculum khác nhau giữa các khóa, hãy đối chiếu với FAP.

## Phím tắt

| Phím | Chức năng |
|---|---|
| Ctrl+O | Quick switcher: mở nhanh / tạo note |
| Ctrl+K | Tìm kiếm |
| Ctrl+G | Graph view |
| Ctrl+S | Lưu note (app cũng tự lưu) |
| `[[` trong editor | Gợi ý liên kết (↑↓, Enter/Tab, Esc) |
| Space · 1–4 · Esc | Lật thẻ · chấm điểm · dừng (khi ôn tập) |

## Phát hành & cập nhật

- **CI** (`.github/workflows/ci.yml`): mỗi lần push lên `main` hoặc mở pull request, GitHub chạy `flutter analyze` và `flutter test`.
- **Release** (`.github/workflows/release.yml`): đẩy tag phiên bản thì GitHub build bản Windows, nén zip và tạo Release. Nếu đã cấu hình chứng chỉ (xem bên dưới), Release có thêm bản cài `.msix`.
  1. Tăng `version:` trong `pubspec.yaml` (ví dụ `1.1.0+2`), commit và push.
  2. `git tag v1.1.0`, rồi `git push origin v1.1.0`. Tag phải trùng với version, nếu không workflow sẽ dừng.
- **Tự kiểm tra cập nhật**: mỗi lần mở, app hỏi GitHub có Release mới hơn không và hiện "Có bản x.y.z, tải về?". Có thể kiểm tra thủ công trong Cài đặt → Phiên bản. Chỉ hoạt động khi repo để Public.

### Bản cài MSIX (tùy chọn)

Bản cài `.msix` phải được ký. Dự án **không** dùng chứng chỉ thử nghiệm mặc định của package `msix`, vì mật khẩu của nó công khai: bảo người dùng tin cậy chứng chỉ đó là không an toàn. Thay vào đó bạn tạo chứng chỉ riêng một lần:

1. Chạy script (tạo chứng chỉ trong `%USERPROFILE%\fptu-brain-signing\`, không nằm trong repo):
   `powershell -ExecutionPolicy Bypass -File tool\create_msix_certificate.ps1`
2. Trên GitHub: **Settings → Secrets and variables → Actions**, thêm hai secret:
   - `MSIX_CERT_BASE64`: nội dung script đã copy sẵn vào clipboard.
   - `MSIX_CERT_PASSWORD`: mật khẩu bạn đặt khi chạy script.
3. Từ lần phát hành sau, Release có thêm `fptu-brain-vX.Y.Z.msix` và `fptu-brain.cer`.

Người dùng cài bản MSIX:
1. Tải `fptu-brain.cer`, mở file, chọn **Install Certificate → Local Machine → Place all certificates in the following store → Trusted People**. Chỉ cần làm một lần.
2. Mở file `.msix` và bấm **Install**. Các bản sau cài đè để cập nhật, dữ liệu vault không bị ảnh hưởng.

Không cần chứng chỉ thì cứ dùng bản `.zip`: giải nén rồi chạy `fptu_brain.exe`.

## Lộ trình phát triển

- [x] Đổi tên note và tự cập nhật mọi `[[link]]` trỏ tới nó
- [x] Gợi ý tự động khi gõ `[[` trong editor
- [x] Quick switcher (Ctrl+O)
- [x] Hiển thị ảnh nhúng `![[image.png]]` từ vault
- [x] AI: hỏi đáp trên toàn vault, sinh đề trắc nghiệm kiểu FE theo môn
- [x] Thống kê ôn tập (heatmap, retention), xuất/nhập bộ thẻ
- [x] Đóng gói bản cài `.msix` cho Windows
