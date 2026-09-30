// Builds a demo vault that looks like a student has been using the app for a
// month: course progress, personal notes, flashcards with review history,
// an imported deck and a saved quiz.
//
//   dart run tool/demo_vault.dart [đường\dẫn\vault]
//
// Diagrams are added by tool/make_demo_vault.ps1, which calls this script.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:fptu_brain/core/flashcards.dart';
import 'package:fptu_brain/core/markdown_utils.dart';
import 'package:fptu_brain/core/sample_vault.dart';
import 'package:fptu_brain/core/vault_repository.dart';
import 'package:path/path.dart' as p;

/// Course code -> status, for a student in the middle of semester 7.
final _statuses = <String, String>{
  for (final c in [
    'PRF192',
    'MAE101',
    'CEA201',
    'CSI106',
    'SSL101c',
    'PRO192',
    'MAD101',
    'OSG202',
    'NWC203c',
    'SSG104',
    'CSD201',
    'DBI202',
    'LAB211',
    'JPD113',
    'WED201c',
    'MAS291',
    'SWE201c',
    'JPD123',
    'IOT102',
    'PRJ301',
    'SWP391',
    'SWR302',
    'SWT301',
    'FER202',
    'ITE302c',
    'OJT202',
    'ENW492c',
  ])
    c: 'done',
  for (final c in ['PRM392', 'PRN212', 'SWD392', 'EXE101', 'MLN111']) c: 'learning',
};

/// Extra sections appended to a few course notes, so they look lived-in.
const _courseNotes = {
  'PRM392': '''

## Ghi chú buổi học
- Buổi 1: cấu trúc project Flutter, `pubspec.yaml`, hot reload vs hot restart.
- Buổi 2: [[Vòng đời Widget trong Flutter]], phân biệt Stateless và Stateful.
- Buổi 3: layout (Row, Column, Expanded), lỗi hay gặp là RenderFlex overflow.
- Buổi 4: [[State management trong Flutter]] — nhóm mình chọn Riverpod cho đồ án.
- Buổi 5: gọi API, [[Async và Future trong Dart]], xử lý lỗi mạng.

## Đồ án
- [[PRM392 — App ghi chú FPTU Second Brain]]

## Tài liệu & đề thi
- Slide của thầy trên LMS, phần Flutter Widget và State.
- Đề PE các kỳ trước: tập trung vào layout và gọi API.

## Flashcards
Hot reload khác hot restart thế nào?::Hot reload giữ nguyên state và nạp lại code UI; hot restart khởi động lại app và mất state
Widget nào dùng để chia phần không gian còn lại trong Row/Column?::Expanded (hoặc Flexible)
Lỗi RenderFlex overflow thường do đâu?::Nội dung rộng/cao hơn không gian của Row/Column; xử lý bằng Expanded, Flexible hoặc cho cuộn
''',
  'SWD392': '''

## Ghi chú buổi học
- Kiến trúc phân tầng: Presentation - Business - Data. So sánh với [[Clean Architecture]].
- Nguyên tắc [[SOLID]] là nền để chọn pattern cho đúng.
- Bài tập: vẽ class diagram cho module mượn sách của [[SWP391 — Đồ án Quản lý thư viện]].

## Flashcards
Nguyên tắc D trong SOLID là gì?::Dependency Inversion - module cấp cao không phụ thuộc module cấp thấp, cả hai phụ thuộc vào abstraction
Vì sao chia tầng lại dễ kiểm thử hơn?::Mỗi tầng phụ thuộc vào interface nên thay bằng mock được, test không cần database hay UI thật
''',
  'PRN212': '''

## Ghi chú buổi học
- C# cơ bản: property, LINQ, async/await (giống [[Async và Future trong Dart]]).
- WPF: XAML, data binding, MVVM — họ hàng gần của [[MVC]].
- Kết nối SQL Server bằng Entity Framework, nhắc lại [[SQL JOIN]].

## Flashcards
MVVM khác MVC ở điểm nào?::MVVM có ViewModel giữ state và binding hai chiều với View, thay cho Controller điều phối
LINQ dùng để làm gì?::Truy vấn dữ liệu (collection, database) bằng cú pháp thống nhất ngay trong C#
''',
  'CSD201': '''

## Ghi chú buổi học
- Ôn lại [[Độ phức tạp thuật toán (Big-O)]] trước khi thi FE, dạng bài hay ra nhất.
- [[Cây nhị phân tìm kiếm (BST)]]: duyệt in-order, xóa nút 2 con.
- Sắp xếp: merge sort ổn định, quick sort nhanh nhưng xấu nhất O(n²).

## Tài liệu & đề thi
- Đề FE mẫu: 40 câu trắc nghiệm, nhiều câu về độ phức tạp và duyệt cây.
''',
  'DBI202': '''

## Ghi chú buổi học
- [[Chuẩn hóa CSDL (Normalization)]] tới 3NF là đủ cho đồ án.
- [[SQL JOIN]]: hay nhầm giữa LEFT JOIN và INNER JOIN khi lọc ở mệnh đề WHERE.
- Transaction và ACID, mức cô lập mặc định của SQL Server là READ COMMITTED.

## Flashcards
ACID gồm những tính chất nào?::Atomicity, Consistency, Isolation, Durability
Vì sao đặt điều kiện của bảng phải vào WHERE lại làm LEFT JOIN thành INNER JOIN?::Vì dòng không khớp có giá trị NULL, điều kiện WHERE loại luôn các dòng đó
''',
  'SWP391': '''

## Ghi chú buổi học
- Nhóm 5 người, chạy [[Scrum]] với sprint 2 tuần, họp daily 15 phút.
- Dự án: [[SWP391 — Đồ án Quản lý thư viện]], backend Java Spring Boot, theo [[MVC]].
- Quản lý mã nguồn bằng [[Git và GitFlow]], mỗi tính năng một nhánh và một pull request.
''',
};

/// Standalone concept notes added on top of the sample vault.
const _concepts = {
  'SOLID': '''
Năm nguyên tắc thiết kế hướng đối tượng, học kỹ ở [[SWD392]].

- **S** – Single Responsibility: mỗi lớp chỉ có một lý do để thay đổi.
- **O** – Open/Closed: mở để mở rộng, đóng với sửa đổi.
- **L** – Liskov Substitution: lớp con thay được lớp cha mà chương trình vẫn đúng.
- **I** – Interface Segregation: nhiều interface nhỏ tốt hơn một interface to.
- **D** – Dependency Inversion: phụ thuộc vào abstraction, không phụ thuộc lớp cụ thể.

Liên quan: [[Lập trình hướng đối tượng (OOP)]], [[Design Patterns]].

## Flashcards
Nguyên tắc Open/Closed nghĩa là gì?::Mở để mở rộng, đóng với sửa đổi - thêm tính năng bằng cách mở rộng thay vì sửa code cũ
Vi phạm Liskov Substitution dẫn tới hậu quả gì?::Thay lớp con vào chỗ lớp cha làm chương trình sai, buộc phải kiểm tra kiểu cụ thể
''',
  'REST API': '''
Kiểu thiết kế API trên HTTP, dùng ở [[PRJ301]], [[PRN212]] và [[FER202]].

- Tài nguyên xác định bằng URL, thao tác bằng method: GET (đọc), POST (tạo), PUT/PATCH (sửa), DELETE (xóa).
- Mã trạng thái hay dùng: 200 OK, 201 Created, 400 Bad Request, 401 Unauthorized, 404 Not Found, 500 Internal Server Error.
- Stateless: mỗi request tự mang đủ thông tin, thường kèm token xác thực.

## Flashcards
201 Created khác 200 OK ở chỗ nào?::201 báo đã tạo mới tài nguyên, thường kèm header Location trỏ tới tài nguyên đó
401 khác 403 thế nào?::401 là chưa xác thực (chưa đăng nhập), 403 là đã xác thực nhưng không đủ quyền
Vì sao REST được gọi là stateless?::Máy chủ không lưu phiên giữa các request, mỗi request tự mang đủ thông tin
''',
  'State management trong Flutter': '''
Cách quản lý dữ liệu dùng chung giữa các widget, phần trọng tâm của [[PRM392]].

- `setState`: đơn giản, chỉ hợp trong một widget.
- `InheritedWidget` / `Provider`: đưa dữ liệu xuống cây widget.
- **Riverpod**: provider khai báo ở ngoài cây widget nên test được, có `Notifier` và `AsyncNotifier` cho dữ liệu bất đồng bộ.
- BLoC: tách event và state, hợp với dự án lớn và luồng phức tạp.

Đồ án [[PRM392 — App ghi chú FPTU Second Brain]] dùng Riverpod: dữ liệu vault nằm trong `AsyncNotifier`, UI chỉ đọc qua `ref.watch`.

## Flashcards
Vì sao Riverpod dễ test hơn Provider?::Provider của Riverpod không gắn vào cây widget, có thể đọc và ghi đè trong test thuần Dart
AsyncNotifier dùng khi nào?::Khi state cần nạp bất đồng bộ (đọc file, gọi API) và UI cần trạng thái loading/error
''',
  'Async và Future trong Dart': '''
Dart chạy đơn luồng với event loop, nên tác vụ chậm phải bất đồng bộ. Gặp ở [[PRM392]].

```dart
Future<String> readNote(String path) async {
  final content = await File(path).readAsString(); // không chặn UI
  return content;
}
```

- `Future`: một giá trị sẽ có trong tương lai. `Stream`: nhiều giá trị theo thời gian (ví dụ dữ liệu AI trả về từng đoạn).
- `await` chỉ dùng trong hàm `async`; quên `await` là lỗi hay gặp nhất.
- Tính toán nặng nên đẩy sang `Isolate` vì `async` không tạo luồng mới.

## Flashcards
Future khác Stream ở điểm nào?::Future trả về một giá trị duy nhất, Stream phát ra nhiều giá trị theo thời gian
async có tạo luồng mới không?::Không, vẫn chạy trên cùng một isolate; muốn chạy song song thật phải dùng Isolate
''',
  'Clean Architecture': '''
Chia ứng dụng thành các vòng đồng tâm, phụ thuộc luôn hướng vào trong. Bàn ở [[SWD392]].

- Trong cùng: entity và use case, không biết gì về UI hay database.
- Ngoài: UI, database, API — là chi tiết có thể thay thế.
- Nhờ [[SOLID]], nhất là Dependency Inversion, tầng trong không phụ thuộc tầng ngoài.

Ví dụ thực tế trong [[PRM392 — App ghi chú FPTU Second Brain]]: thư mục `core/` không import Flutter nên test được bằng unit test thuần.

## Flashcards
Quy tắc phụ thuộc của Clean Architecture là gì?::Mọi phụ thuộc hướng vào trong; tầng trong không biết gì về tầng ngoài
Vì sao database bị coi là "chi tiết"?::Vì nghiệp vụ không phụ thuộc vào nó, có thể đổi database mà use case không đổi
''',
  'Git và GitFlow': '''
Quản lý mã nguồn cho làm việc nhóm, áp dụng ở [[SWP391]] và [[SEP490]].

- Nhánh `main` luôn chạy được; mỗi tính năng làm ở nhánh `feature/...` rồi mở pull request.
- `git pull --rebase` giúp lịch sử thẳng, tránh commit merge rác.
- Xung đột xảy ra khi hai người sửa cùng vùng code; giải quyết thủ công rồi `git add` và tiếp tục.
- CI chạy test tự động trên mỗi pull request, đỏ thì không merge.

## Flashcards
Khác nhau giữa merge và rebase?::Merge tạo commit gộp và giữ nguyên lịch sử; rebase chép commit lên trên nhánh đích cho lịch sử thẳng
Vì sao không nên commit thẳng lên main khi làm nhóm?::Dễ làm hỏng nhánh chính và bỏ qua review; nên qua pull request để CI và người khác kiểm tra
''',
};

const _projects = {
  'SWP391 — Đồ án Quản lý thư viện': '''---
type: project
tags: [project, ky5]
---
# SWP391 — Đồ án Quản lý thư viện

Nhóm 5 người, 4 sprint theo [[Scrum]], backend Spring Boot theo [[MVC]], database SQL Server.

## Vai trò
- Mình: backend module mượn/trả sách và phần báo cáo.

## Bài học rút ra
- Thiết kế database sai từ đầu thì sửa rất tốn công, nên [[Chuẩn hóa CSDL (Normalization)]] kỹ trước khi code.
- Chia nhánh theo [[Git và GitFlow]] giúp nhóm không đụng code nhau.
- Viết test cho phần tính phí phạt tiết kiệm rất nhiều thời gian sửa lỗi về sau.
''',
  'PRM392 — App ghi chú FPTU Second Brain': '''---
type: project
tags: [project, ky7]
---
# PRM392 — App ghi chú FPTU Second Brain

Đồ án môn [[PRM392]]: ứng dụng desktop Flutter quản lý kiến thức, đọc ghi trực tiếp vault Obsidian.

## Kiến trúc
- `core/` Dart thuần (parse Markdown, [[Cây nhị phân tìm kiếm (BST)]] không dùng, nhưng có thuật toán SM-2 cho flashcard) → unit test được, theo tinh thần [[Clean Architecture]].
- `state/` dùng Riverpod, xem [[State management trong Flutter]].
- `ui/` các trang giao diện Material 3.

## Việc đã làm
- Đọc/ghi file `.md`, theo dõi thay đổi từ bên ngoài bằng watcher.
- Gợi ý `[[` khi gõ, đổi tên note tự cập nhật liên kết.
- Tích hợp Claude API: tóm tắt, sinh flashcard, hỏi đáp toàn vault.
- CI/CD bằng GitHub Actions, tự build và ký bản cài.

## Việc cần làm tiếp
- Tối ưu Graph view khi vault lớn.
- Viết slide demo cho buổi bảo vệ.

## Flashcards
Vì sao app đọc thẳng file .md thay vì dùng database?::Để dùng chung dữ liệu với Obsidian; file Markdown chính là nguồn dữ liệu
''',
};

String _journal(String date, String body) =>
    '''---
type: daily
tags: [journal]
---
# $date

$body
''';

Future<void> main(List<String> args) async {
  final dir = args.isNotEmpty ? args.first : r'D:\Project\FPT\FPTU-Demo-Vault';
  final repo = VaultRepository(dir);
  stdout.writeln('Tạo vault demo tại $dir');
  await SampleVault.create(dir);

  // 1. Course progress.
  for (final e in _statuses.entries) {
    final note = await repo.readNote('Courses/${e.key}.md');
    if (note == null) continue;
    await repo.writeNote(note.path, setFrontmatterField(note.content, 'status', e.value));
  }

  // 2. Lecture notes and extra flashcards on a few courses.
  for (final e in _courseNotes.entries) {
    final note = await repo.readNote('Courses/${e.key}.md');
    if (note == null) continue;
    await repo.writeNote(note.path, '${note.content.trimRight()}\n${e.value}');
  }

  // 3. Extra concept, project and journal notes.
  for (final e in _concepts.entries) {
    await repo.writeNote('Concepts/${e.key}.md', '---\ntype: concept\ntags: [concept]\n---\n# ${e.key}\n\n${e.value}');
  }
  for (final e in _projects.entries) {
    await repo.writeNote('Projects/${e.key}.md', e.value);
  }
  await repo.writeNote(
    'Journal/2026-09-28.md',
    _journal('2026-09-28', '''
- Ôn [[Độ phức tạp thuật toán (Big-O)]] 30 phút, phần merge sort vẫn hay quên.
- Làm xong phần gợi ý `[[` cho [[PRM392 — App ghi chú FPTU Second Brain]].
- Cần hỏi thầy [[SWD392]] về cách vẽ sequence diagram cho luồng đăng nhập.
'''),
  );
  await repo.writeNote(
    'Journal/2026-09-29.md',
    _journal('2026-09-29', '''
- Họp nhóm [[EXE101]], chốt ý tưởng và chia việc.
- Đọc lại [[SOLID]] trước buổi [[SWD392]] chiều nay.
- Ôn 24 thẻ, phần [[REST API]] nhớ khá tốt.
'''),
  );
  await repo.writeNote(
    'Journal/2026-09-30.md',
    _journal('2026-09-30', '''
- Chuẩn bị demo [[PRM392 — App ghi chú FPTU Second Brain]] cho thầy.
- Cần dựng sẵn dữ liệu mẫu và thử phần AI trước khi lên trình bày.
'''),
  );

  // 4. An imported deck and a saved quiz, so those folders aren't empty.
  await repo.writeNote('Flashcards/PRM392 - Nhập từ Quizlet.md', '''---
type: deck
tags: [flashcards, ky7]
---
# PRM392 - Nhập từ Quizlet

Nhập từ `prm392-widgets.csv`.

## Flashcards
StatelessWidget dùng khi nào?::Khi giao diện chỉ phụ thuộc cấu hình truyền vào và không tự thay đổi theo thời gian
BuildContext là gì?::Tham chiếu tới vị trí của widget trong cây widget, dùng để tra cứu Theme, Navigator, MediaQuery
Key trong Flutter dùng để làm gì?::Giúp Flutter nhận ra widget nào là widget nào khi danh sách thay đổi thứ tự
MediaQuery.sizeOf(context) trả về gì?::Kích thước vùng hiển thị hiện tại, dùng để bố trí giao diện theo kích thước cửa sổ
''');
  await repo.writeNote('Quizzes/Đề CSD201 2026-09-25 0930.md', '''---
type: quiz
scope: "CSD201 — Data Structures and Algorithms"
created: 2026-09-25 09:30
score: 8/10
tags: [quiz]
---
# Đề trắc nghiệm — CSD201 — Data Structures and Algorithms

## Câu 1. Duyệt cây nhị phân tìm kiếm theo thứ tự nào cho dãy khóa tăng dần?
- A. Pre-order
- B. In-order
- C. Post-order
- D. Level-order

> [!success]- Đáp án: B
> In-order thăm cây con trái, gốc rồi cây con phải nên khóa tăng dần.
> Nguồn: [[Cây nhị phân tìm kiếm (BST)]]

## Câu 2. Độ phức tạp trung bình của quick sort?
- A. O(n)
- B. O(n log n)
- C. O(n²)
- D. O(log n)

> [!success]- Đáp án: B
> Trung bình O(n log n); trường hợp xấu nhất mới là O(n²).
> Nguồn: [[Độ phức tạp thuật toán (Big-O)]]
''');

  // 5. Link the two diagrams drawn by the PowerShell wrapper.
  await _appendOnce(repo, 'Courses/PRM392.md', '\n![[vong-doi-widget.png|520]]\n');
  await _appendOnce(repo, 'Concepts/MVC.md', '\n![[mvc.png|520]]\n');

  // 6. Home page section for the current semester.
  await _appendOnce(repo, 'Home.md', '''
## Đang học (kỳ 7)
- [[PRM392]] — đồ án: [[PRM392 — App ghi chú FPTU Second Brain]]
- [[PRN212]], [[SWD392]], [[EXE101]], [[MLN111]]

## Nhật ký
- [[2026-09-30]] · [[2026-09-29]] · [[2026-09-28]]
''');

  // 7. Review history, so the stats page has something to show.
  final index = await repo.loadIndex();
  final cards = allFlashcards(index);
  final rnd = Random(7);
  final today = DateTime.now();
  final states = <String, CardState>{};
  final log = <Map<String, dynamic>>[];

  for (final card in cards) {
    // A quarter of the cards stay new, the rest have been reviewed before.
    if (rnd.nextDouble() < 0.25) continue;
    final reps = 1 + rnd.nextInt(5);
    final interval = [1, 3, 6, 10, 21, 35][rnd.nextInt(6)];
    final dueIn = rnd.nextInt(10) - 3; // a few are due today or overdue
    states[card.id] = CardState(
      ease: 2.2 + rnd.nextDouble() * 0.6,
      interval: interval,
      reps: reps,
      due: DateTime(today.year, today.month, today.day + dueIn),
    );
    // Spread this card's past reviews over the last five weeks.
    for (var i = 0; i < reps; i++) {
      final daysAgo = 1 + rnd.nextInt(34);
      final again = rnd.nextDouble() < 0.12;
      log.add({
        't': DateTime(
          today.year,
          today.month,
          today.day - daysAgo,
          19 + rnd.nextInt(3),
          rnd.nextInt(60),
        ).toIso8601String(),
        'id': card.id,
        'g': again ? 'again' : (rnd.nextDouble() < 0.25 ? 'easy' : 'good'),
        'p': again ? interval : max(1, interval - 2),
      });
    }
  }
  // Keep today's streak alive.
  for (var i = 0; i < 6 && i < cards.length; i++) {
    log.add({
      't': DateTime(today.year, today.month, today.day, 8, i * 3).toIso8601String(),
      'id': cards[i].id,
      'g': 'good',
      'p': 4,
    });
  }
  log.sort((a, b) => (a['t'] as String).compareTo(b['t'] as String));

  final appDir = Directory(p.join(dir, VaultRepository.appDir));
  await appDir.create(recursive: true);
  await File(p.join(appDir.path, 'srs.json')).writeAsString(
    const JsonEncoder.withIndent('  ').convert({'version': 1, 'cards': states.map((k, v) => MapEntry(k, v.toJson()))}),
  );
  await File(p.join(appDir.path, 'review_log.json')).writeAsString(jsonEncode({'version': 1, 'reviews': log}));

  final after = await repo.loadIndex();
  stdout
    ..writeln('  ${after.notes.length} note, ${after.linkCount} liên kết, ${allFlashcards(after).length} flashcard')
    ..writeln('  ${states.length} thẻ có lịch ôn, ${log.length} lượt ôn trong 5 tuần')
    ..writeln('Xong. Mở thư mục này trong app hoặc Obsidian.');
}

/// Appends [text] only if it isn't in the note yet, so re-running is safe.
Future<void> _appendOnce(VaultRepository repo, String path, String text) async {
  final note = await repo.readNote(path);
  if (note == null || note.content.contains(text.trim())) return;
  await repo.writeNote(path, '${note.content.trimRight()}\n$text');
}
