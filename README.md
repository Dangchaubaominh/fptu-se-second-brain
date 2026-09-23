# FPTU SE Second Brain (Flutter Desktop)

Ứng dụng desktop quản lý kiến thức ngành **Kỹ thuật phần mềm – Đại học FPT**. Ứng dụng đọc và ghi trực tiếp một **Obsidian vault** (các file `.md` có `[[wikilink]]` và YAML frontmatter), nên dùng song song với Obsidian được.

| Yêu cầu | Đáp ứng bởi |
|---|---|
| Flutter Desktop App | Windows / macOS / Linux, NavigationRail, phím tắt, dark mode, bản cài `.msix` cho Windows |
| File handling | Quét vault, đọc/ghi `.md`, sửa frontmatter, tạo/đổi tên note (tự cập nhật link), chèn ảnh vào `attachments/`, chuyển vào `.trash/`, theo dõi thay đổi file (watcher), xuất/nhập bộ thẻ TSV/CSV, lưu lịch ôn và nhật ký trong `.fptu/` |
| AI Integration | Claude API (`claude-opus-5`): tóm tắt note, sinh flashcard, chat về note, hỏi đáp trên toàn vault có trích nguồn, sinh đề trắc nghiệm kiểu FE (structured JSON output + prompt caching) |
| UI/UX | Material 3, màu FPT, dashboard tiến độ, graph view tương tác, tìm kiếm không dấu, gợi ý `[[`, quick switcher, ôn tập bằng bàn phím, thống kê heatmap |

## Cài đặt

**Yêu cầu:** Windows 10 hoặc 11 (64-bit). Tính năng AI cần kết nối Internet và một Anthropic API key. Các tính năng còn lại chạy offline.

Tải bản mới nhất ở trang [Releases](https://github.com/Dangchaubaominh/fptu-se-second-brain/releases/latest), chọn **một** trong hai cách:

### Cách 1: Bản cài đặt `.msix` (khuyên dùng)

App có trong Start Menu, gỡ được như các app khác.

1. Tải `fptu-brain.cer` và `fptu-brain-vX.Y.Z.msix`.
2. **Chỉ lần đầu trên mỗi máy:** bấm đúp `fptu-brain.cer` → **Install Certificate** → chọn **Local Machine** → **Next** → **Place all certificates in the following store** → **Browse** → **Trusted People** → **OK** → **Next** → **Finish**. Windows sẽ hỏi quyền Admin.
3. Bấm đúp file `.msix` → **Install**. Mở app từ Start Menu với tên "FPTU SE Second Brain".

Nếu Windows báo không tin cậy được nhà phát hành, hãy kiểm tra lại bước 2: chứng chỉ phải nằm trong **Trusted People** của **Local Machine**, không phải Current User.

### Cách 2: Bản giải nén `.zip`

Không cần cài chứng chỉ và không cần quyền Admin.

1. Tải `fptu-brain-windows-vX.Y.Z.zip` và giải nén vào một thư mục, ví dụ `D:\Apps\FPTU Brain`.
2. Chạy `fptu_brain.exe`. Có thể chuột phải → **Send to → Desktop (create shortcut)** để tạo lối tắt.
3. Nếu Windows SmartScreen cảnh báo, chọn **More info → Run anyway**. App chưa được ký bằng chứng chỉ thương mại nên SmartScreen chưa nhận diện được.

Giữ nguyên cả thư mục sau khi giải nén: `fptu_brain.exe` cần các file `.dll` và thư mục `data` nằm cạnh nó.

### Cập nhật

Khi có bản mới, app hiện thông báo **"Có bản x.y.z, tải về?"** lúc khởi động. Bạn cũng có thể vào **Cài đặt → Phiên bản → Kiểm tra cập nhật**.
- Bản `.msix`: tải file `.msix` mới rồi mở để cài đè. Không cần cài lại chứng chỉ.
- Bản `.zip`: đóng app, giải nén bản mới đè lên thư mục cũ.

Ghi chú, flashcard và lịch ôn nằm trong vault của bạn, không nằm trong thư mục app, nên cập nhật không làm mất dữ liệu.

### Gỡ cài đặt

- Bản `.msix`: **Settings → Apps → Installed apps → FPTU SE Second Brain → Uninstall**.
- Bản `.zip`: xóa thư mục đã giải nén.

Vault không bị xóa theo. Muốn gỡ luôn chứng chỉ thì mở `certlm.msc` → **Trusted People → Certificates** → xóa "FPTU SE Second Brain".

## Hướng dẫn sử dụng

### 1. Mở hoặc tạo vault

Lần đầu mở app, chọn một trong hai:
- **Mở Obsidian vault có sẵn**: chọn thư mục vault bạn đang dùng với Obsidian. App đọc và ghi trực tiếp các file `.md` trong đó.
- **Tạo vault mẫu FPTU SE**: chọn nơi lưu, app tạo thư mục `FPTU-SE-Brain` gồm lộ trình 9 kỳ, khoảng 40 môn, các note khái niệm và flashcard mẫu.

Muốn dùng song song với Obsidian: mở Obsidian → **Open folder as vault** → chọn cùng thư mục. Sửa ở bên nào thì bên kia tự cập nhật. Đổi vault khác trong **Cài đặt → Vault**.

### 2. Bật trợ lý AI (tùy chọn)

1. Tạo API key tại [console.anthropic.com](https://console.anthropic.com) (mục API Keys). Việc gọi API có tính phí theo lượng sử dụng của tài khoản Anthropic.
2. Trong app vào **Cài đặt → Trợ lý AI (Claude)**, dán key, bấm **Lưu** rồi **Kiểm tra kết nối**.

Key chỉ lưu trên máy của bạn, không ghi vào vault. Cũng có thể đặt biến môi trường `ANTHROPIC_API_KEY` thay vì nhập trong app.

### 3. Theo dõi môn học

- Trang **Môn học** liệt kê các môn theo kỳ. Bấm vào nhãn trạng thái trên thẻ môn để đổi giữa **Chưa học / Đang học / Hoàn thành**. Tiến độ hiện ở trang **Tổng quan**.
- Biểu tượng ổ khóa đỏ nghĩa là còn môn tiên quyết chưa hoàn thành.
- **Thêm môn** tạo note mới trong `Courses/`. Một note có sẵn cũng thành môn học nếu frontmatter có `type: course` (xem mục Quy ước dữ liệu).

### 4. Viết ghi chú

- Trang **Ghi chú**: chọn note ở cây thư mục bên trái. Chuyển chế độ **Soạn / Chia đôi / Xem** bằng nút trên thanh công cụ. App tự lưu sau 0,7 giây, hoặc nhấn **Ctrl+S**.
- **Liên kết:** gõ `[[` để hiện gợi ý, dùng ↑↓ chọn rồi **Enter**. Gõ tên chưa có note cũng được, bấm vào link đó sẽ tạo note mới.
- **Ảnh:** bấm nút **Chèn ảnh** trên thanh công cụ và chọn file. Ảnh được chép vào `attachments/`. Viết `![[ảnh.png|300]]` để đặt độ rộng 300px.
- **Đổi tên / xóa:** menu **⋮** trên thanh công cụ. Đổi tên tự sửa mọi link trỏ tới note. Note bị xóa được chuyển vào `.trash/`; bấm biểu tượng **Thùng rác** trên cây file để khôi phục ngay trong app.
- **Dùng đồng thời với Obsidian:** app phát hiện khi note đang soạn bị thay đổi từ bên ngoài và dừng autosave để tránh ghi đè. Bạn có thể nạp bản trên đĩa, giữ bản đang soạn để xử lý hoặc chủ động ghi đè.
- Bảng bên phải: tab **Liên kết** (backlinks, liên kết đi, tags, flashcard trong note) và tab **Trợ lý AI**.

### 5. Tìm và di chuyển nhanh

- **Ctrl+O**: gõ vài chữ tên note (không cần dấu) rồi Enter để mở. Nếu chưa có note trùng tên, chọn dòng **Tạo note mới**.
- **Ctrl+K**: tìm trong nội dung mọi note. Gõ `#tên-tag` để lọc theo tag.
- **Ctrl+G**: Graph view. Cuộn chuột để zoom, kéo để di chuyển, di chuột lên một nút để làm nổi các note liên quan, bấm để mở.

### 6. Ôn tập bằng flashcard

1. Viết thẻ trong bất kỳ note nào, mỗi thẻ một dòng dạng `Câu hỏi::Trả lời`. Có thể dùng Trợ lý AI → **Tạo flashcard** để sinh thẻ từ note.
2. Trang **Ôn tập**: chọn bộ thẻ (tất cả, hoặc theo môn) rồi bấm **Bắt đầu ôn**.
3. Nhấn **Space** để xem đáp án, rồi chấm điểm bằng phím **1** Quên · **2** Khó · **3** Nhớ · **4** Dễ. Thẻ "Quên" sẽ hiện lại ngay trong phiên. App tự xếp lịch ôn lần sau.
4. Phần **Thống kê** bên dưới cho biết chuỗi ngày ôn, tỉ lệ nhớ, heatmap và số thẻ đến hạn trong 7 ngày tới.
5. **Xuất (Anki)** tạo file `.txt` để nhập vào Anki (File → Import). **Nhập bộ thẻ** đọc file TSV/CSV có ít nhất 2 cột (câu hỏi, trả lời) từ Anki, Quizlet hoặc Excel. Với Excel, hãy lưu dạng **CSV UTF-8** để giữ dấu tiếng Việt.

### 7. Học cùng AI

- **Trong một note:** tab **Trợ lý AI** ở bảng bên phải có **Tóm tắt**, **Tạo flashcard** (chọn thẻ muốn giữ rồi bấm **Thêm**) và ô chat hỏi về nội dung note.
- **Trang Hỏi AI:** chọn **Phạm vi** là toàn bộ vault hoặc một môn.
  - **Hỏi đáp:** đặt câu hỏi, Claude trả lời dựa trên ghi chú của bạn và dẫn nguồn `[[Tên note]]`, bấm vào để mở note đó. Nút **Cuộc trò chuyện mới** để bắt đầu lại.
  - **Trắc nghiệm:** chọn 5/10/20 câu → **Tạo đề** → chọn đáp án → **Nộp bài** để xem điểm và giải thích. **Lưu đề vào vault** tạo note trong `Quizzes/`, mở được cả trong Obsidian.

## Tính năng

- **Tổng quan**: số note, số liên kết, tiến độ từng kỳ, các môn đang học, note sửa gần đây, số thẻ đến hạn.
- **Môn học**: lộ trình 9 kỳ, đổi trạng thái (Chưa học / Đang học / Hoàn thành) và ghi thẳng vào `status:` trong frontmatter, cảnh báo khi chưa qua môn tiên quyết.
- **Ghi chú**
  - Cây thư mục, editor Markdown 3 chế độ (Soạn / Chia đôi / Xem), tự lưu sau 0,7 giây.
  - Ghi file an toàn qua file tạm; phát hiện xung đột khi Obsidian hoặc ứng dụng khác sửa cùng note.
  - Gõ `[[` để được gợi ý note (không dấu, theo alias). Bấm `[[wikilink]]` để mở note, chưa có thì tự tạo.
  - **Đổi tên note** (menu ⋮): mọi `[[link]]` trỏ tới note trong vault được cập nhật theo, giữ nguyên `#heading` và `|alias`. Link viết bằng alias không bị đổi. Lịch ôn flashcard của note được giữ lại.
  - **Thùng rác có khôi phục**: giữ lại đường dẫn thư mục cũ; nếu đường dẫn đã có note mới, bản khôi phục được đổi tên thay vì ghi đè.
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

### Ký bản cài MSIX

Bản cài `.msix` phải được ký. Dự án **không** dùng chứng chỉ thử nghiệm mặc định của package `msix`, vì mật khẩu của nó công khai: bảo người dùng tin cậy chứng chỉ đó là không an toàn. Thay vào đó bạn tạo chứng chỉ riêng một lần:

1. Chạy script (tạo chứng chỉ trong `%USERPROFILE%\fptu-brain-signing\`, không nằm trong repo):
   `powershell -ExecutionPolicy Bypass -File tool\create_msix_certificate.ps1`
2. Trên GitHub: **Settings → Secrets and variables → Actions**, thêm hai secret:
   - `MSIX_CERT_BASE64`: nội dung script đã copy sẵn vào clipboard.
   - `MSIX_CERT_PASSWORD`: mật khẩu bạn đặt khi chạy script.
3. Từ lần phát hành sau, Release có thêm `fptu-brain-vX.Y.Z.msix` và `fptu-brain.cer`. Với tag đã phát hành trước khi thêm secret, mở lần chạy **Release Windows** của tag đó trong tab Actions và chọn **Re-run all jobs**.
