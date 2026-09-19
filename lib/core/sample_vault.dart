import 'dart:io';

import 'package:path/path.dart' as p;

/// Generates a starter Obsidian vault for the FPTU Software Engineering curriculum.
/// The course list is a reference roadmap; curricula differ between intakes
/// ("khóa"), so users should adjust it to match FAP.
class SampleVault {
  static const _courses = <(String, String, int, List<String>, List<String>)>[
    // (code, name, semester, prerequisites, concept notes)
    ('PRF192', 'Programming Fundamentals', 1, [], ['Con trỏ (Pointer)', 'Đệ quy (Recursion)']),
    ('MAE101', 'Mathematics for Engineering', 1, [], []),
    ('CEA201', 'Computer Organization and Architecture', 1, [], []),
    ('CSI106', 'Introduction to Computer Science', 1, [], []),
    ('SSL101c', 'Academic Skills for University Success', 1, [], []),
    ('PRO192', 'Object-Oriented Programming', 2, ['PRF192'], ['Lập trình hướng đối tượng (OOP)']),
    ('MAD101', 'Discrete Mathematics', 2, [], []),
    ('OSG202', 'Operating Systems', 2, [], ['Tiến trình và luồng (Process vs Thread)']),
    ('NWC203c', 'Computer Networking', 2, [], ['Mô hình OSI']),
    ('SSG104', 'Communication and In-Group Working Skills', 2, [], []),
    ('CSD201', 'Data Structures and Algorithms', 3, ['PRO192'],
        ['Độ phức tạp thuật toán (Big-O)', 'Cây nhị phân tìm kiếm (BST)', 'Đệ quy (Recursion)']),
    ('DBI202', 'Database Systems', 3, [], ['Chuẩn hóa CSDL (Normalization)', 'SQL JOIN']),
    ('LAB211', 'OOP with Java Lab', 3, ['PRO192'], ['Lập trình hướng đối tượng (OOP)']),
    ('JPD113', 'Elementary Japanese 1-A1.1', 3, [], []),
    ('WED201c', 'Web Design', 3, [], []),
    ('MAS291', 'Statistics and Probability', 4, [], []),
    ('SWE201c', 'Introduction to Software Engineering', 4, [], ['Scrum']),
    ('JPD123', 'Elementary Japanese 1-A1.2', 4, ['JPD113'], []),
    ('IOT102', 'Internet of Things', 4, [], []),
    ('PRJ301', 'Java Web Application Development', 4, ['PRO192', 'DBI202'], ['MVC']),
    ('SWP391', 'Software Development Project', 5, ['PRJ301'], ['Scrum', 'MVC']),
    ('SWR302', 'Software Requirements', 5, ['SWE201c'], []),
    ('SWT301', 'Software Testing', 5, ['SWE201c'], ['Kiểm thử hộp đen và hộp trắng']),
    ('FER202', 'Front-End Web Development with React', 5, ['WED201c'], ['React Hooks']),
    ('ITE302c', 'Ethics in IT', 5, [], []),
    ('OJT202', 'On-the-Job Training', 6, [], []),
    ('ENW492c', 'Writing Research Papers', 6, [], []),
    ('PRN212', 'Basic Cross-Platform Application Programming with .NET', 7, ['PRO192'], []),
    ('PRM392', 'Mobile Programming', 7, ['PRO192'], ['Vòng đời Widget trong Flutter']),
    ('SWD392', 'Software Architecture and Design', 7, ['SWE201c'], ['Design Patterns', 'MVC']),
    ('EXE101', 'Experiential Entrepreneurship 1', 7, [], []),
    ('MLN111', 'Philosophy of Marxism-Leninism', 7, [], []),
    ('PRU213', 'C# Programming and Unity', 8, ['PRO192'], []),
    ('EXE201', 'Experiential Entrepreneurship 2', 8, ['EXE101'], []),
    ('MLN122', 'Political Economics of Marxism-Leninism', 8, ['MLN111'], []),
    ('WDU203c', 'UI/UX Design', 8, [], []),
    ('PMG201c', 'Project Management', 8, [], ['Scrum']),
    ('SEP490', 'SE Capstone Project', 9, ['SWP391'], ['Scrum', 'Design Patterns']),
    ('MLN131', 'Scientific Socialism', 9, ['MLN122'], []),
    ('VNR202', 'History of Vietnam Communist Party', 9, [], []),
    ('HCM202', 'Ho Chi Minh Ideology', 9, [], []),
  ];

  static const _concepts = <String, String>{
    'Con trỏ (Pointer)': '''
Con trỏ là biến lưu **địa chỉ bộ nhớ** của một biến khác. Học trong [[PRF192]] với ngôn ngữ C.

```c
int x = 10;
int *p = &x;   // p trỏ tới x
*p = 20;       // x bây giờ bằng 20
```

- `&` lấy địa chỉ, `*` truy cập giá trị tại địa chỉ (dereference).
- Truyền con trỏ vào hàm để hàm sửa được biến gốc (pass by reference).
- Mảng và con trỏ liên quan chặt: `a[i]` tương đương `*(a + i)`.
- Cấp phát động với `malloc` / `free`; quên `free` gây rò rỉ bộ nhớ (memory leak).

## Flashcards
Toán tử nào lấy địa chỉ của một biến trong C?::Toán tử `&`
Biểu thức `a[i]` tương đương với biểu thức con trỏ nào?::`*(a + i)`
Hậu quả khi cấp phát bằng malloc mà không free?::Rò rỉ bộ nhớ (memory leak)
''',
    'Đệ quy (Recursion)': '''
Đệ quy là kỹ thuật một hàm **tự gọi lại chính nó** để giải bài toán con nhỏ hơn. Gặp ở [[PRF192]] và dùng nhiều trong [[CSD201]].

Mỗi hàm đệ quy cần:
1. **Điều kiện dừng** (base case).
2. **Bước đệ quy** tiến dần về base case.

```java
int factorial(int n) {
    if (n <= 1) return 1;       // base case
    return n * factorial(n - 1);
}
```

Mỗi lần gọi chiếm một frame trên call stack; đệ quy quá sâu gây **StackOverflowError**. Duyệt cây ([[Cây nhị phân tìm kiếm (BST)]]) là ví dụ điển hình. Độ phức tạp phân tích bằng [[Độ phức tạp thuật toán (Big-O)]].

## Flashcards
Hai thành phần bắt buộc của một hàm đệ quy?::Điều kiện dừng (base case) và bước đệ quy
Lỗi gì xảy ra khi đệ quy quá sâu trong Java?::StackOverflowError
''',
    'Lập trình hướng đối tượng (OOP)': '''
OOP tổ chức chương trình thành các **đối tượng** gồm dữ liệu (field) và hành vi (method). Học trong [[PRO192]], thực hành ở [[LAB211]].

## 4 tính chất
- **Đóng gói (Encapsulation)**: ẩn dữ liệu bằng `private`, truy cập qua getter/setter.
- **Kế thừa (Inheritance)**: lớp con dùng lại lớp cha (`extends`).
- **Đa hình (Polymorphism)**: cùng một lời gọi, hành vi khác nhau (overriding lúc chạy, overloading lúc biên dịch).
- **Trừu tượng (Abstraction)**: chỉ lộ ra những gì cần thiết (`abstract class`, `interface`).

Nền tảng cho [[Design Patterns]] và kiến trúc [[MVC]].

## Flashcards
Bốn tính chất của OOP là gì?::Đóng gói, kế thừa, đa hình, trừu tượng
Overloading khác overriding thế nào?::Overloading: cùng tên khác tham số, quyết định lúc biên dịch; overriding: lớp con định nghĩa lại method của lớp cha, quyết định lúc chạy
Java có hỗ trợ đa kế thừa lớp không?::Không, một lớp chỉ extends một lớp nhưng có thể implements nhiều interface
''',
    'Tiến trình và luồng (Process vs Thread)': '''
Kiến thức trọng tâm của [[OSG202]].

| | Process | Thread |
|---|---|---|
| Bộ nhớ | Không gian địa chỉ riêng | Dùng chung bộ nhớ của process |
| Tạo/chuyển ngữ cảnh | Tốn kém | Nhẹ hơn |
| Giao tiếp | IPC (pipe, socket, shared memory) | Qua biến dùng chung, cần đồng bộ |

Nhiều thread dùng chung dữ liệu dễ gây **race condition** → dùng mutex/semaphore. Bốn điều kiện deadlock: mutual exclusion, hold and wait, no preemption, circular wait.

## Flashcards
Khác biệt chính về bộ nhớ giữa process và thread?::Mỗi process có không gian địa chỉ riêng, các thread trong một process dùng chung bộ nhớ
Bốn điều kiện cần để xảy ra deadlock?::Mutual exclusion, hold and wait, no preemption, circular wait
''',
    'Mô hình OSI': '''
Mô hình tham chiếu 7 tầng trong [[NWC203c]] (từ dưới lên):

1. Physical
2. Data Link (MAC, switch)
3. Network (IP, router)
4. Transport (TCP, UDP)
5. Session
6. Presentation
7. Application (HTTP, DNS, SMTP)

Mẹo nhớ: **P**lease **D**o **N**ot **T**hrow **S**ausage **P**izza **A**way.

## Flashcards
TCP và UDP thuộc tầng nào của mô hình OSI?::Tầng 4 - Transport
Router hoạt động chủ yếu ở tầng nào?::Tầng 3 - Network
''',
    'Độ phức tạp thuật toán (Big-O)': '''
Big-O mô tả **tốc độ tăng** của thời gian/bộ nhớ theo kích thước đầu vào n, trong trường hợp xấu nhất. Trọng tâm của [[CSD201]].

| Độ phức tạp | Ví dụ |
|---|---|
| O(1) | Truy cập phần tử mảng |
| O(log n) | Binary search, thao tác trên [[Cây nhị phân tìm kiếm (BST)]] cân bằng |
| O(n) | Duyệt mảng |
| O(n log n) | Merge sort, quick sort (trung bình) |
| O(n²) | Bubble sort, selection sort |

## Flashcards
Độ phức tạp của binary search?::O(log n)
Độ phức tạp trung bình của quick sort? Trường hợp xấu nhất?::Trung bình O(n log n), xấu nhất O(n²)
Merge sort có độ phức tạp thời gian bao nhiêu?::O(n log n) trong mọi trường hợp
''',
    'Cây nhị phân tìm kiếm (BST)': '''
BST là cây nhị phân mà với mọi nút: **khóa ở cây con trái < nút < khóa ở cây con phải**. Học trong [[CSD201]].

- Tìm kiếm/chèn/xóa: O(h), với h là chiều cao cây → O(log n) nếu cân bằng, O(n) nếu suy biến thành danh sách.
- Duyệt **in-order** (trái - gốc - phải) cho dãy khóa tăng dần.
- Xóa nút có 2 con: thay bằng nút nhỏ nhất của cây con phải (hoặc lớn nhất của cây con trái).
- Cây AVL tự cân bằng bằng các phép xoay.

Các thao tác thường cài đặt bằng [[Đệ quy (Recursion)]].

## Flashcards
Duyệt BST theo thứ tự nào để được dãy tăng dần?::In-order (trái - gốc - phải)
Độ phức tạp tìm kiếm trên BST suy biến?::O(n)
Khi xóa nút có hai con trong BST, thay bằng nút nào?::Nút nhỏ nhất của cây con phải (hoặc lớn nhất của cây con trái)
''',
    'Chuẩn hóa CSDL (Normalization)': '''
Chuẩn hóa giảm dư thừa dữ liệu và dị thường khi cập nhật. Trọng tâm của [[DBI202]].

- **1NF**: mọi thuộc tính là nguyên tố (không có nhóm lặp, đa trị).
- **2NF**: 1NF + mọi thuộc tính không khóa phụ thuộc **đầy đủ** vào khóa chính.
- **3NF**: 2NF + không có phụ thuộc **bắc cầu** vào khóa.
- **BCNF**: mọi phụ thuộc hàm X → Y thì X là siêu khóa.

Sau khi chuẩn hóa, truy vấn dữ liệu từ nhiều bảng bằng [[SQL JOIN]].

## Flashcards
Điều kiện của dạng chuẩn 2NF?::Đạt 1NF và mọi thuộc tính không khóa phụ thuộc đầy đủ vào khóa chính
3NF loại bỏ loại phụ thuộc nào?::Phụ thuộc bắc cầu vào khóa
''',
    'SQL JOIN': '''
JOIN kết hợp dòng từ nhiều bảng theo điều kiện. Dùng hằng ngày ở [[DBI202]] và [[PRJ301]].

- `INNER JOIN`: chỉ dòng khớp ở cả hai bảng.
- `LEFT JOIN`: mọi dòng bảng trái, bảng phải không khớp thì NULL.
- `RIGHT JOIN`: ngược lại với LEFT.
- `FULL OUTER JOIN`: mọi dòng của cả hai bảng.
- `CROSS JOIN`: tích Descartes.

```sql
SELECT s.name, c.code
FROM Student s
LEFT JOIN Enrollment e ON e.student_id = s.id
LEFT JOIN Course c ON c.id = e.course_id;
```

## Flashcards
LEFT JOIN trả về gì khi bảng phải không có dòng khớp?::Vẫn trả về dòng của bảng trái, các cột bảng phải là NULL
Loại JOIN nào tạo ra tích Descartes?::CROSS JOIN
''',
    'MVC': '''
**Model - View - Controller** tách ứng dụng thành 3 phần. Dùng trong [[PRJ301]] (Servlet/JSP), [[SWP391]] và bàn sâu ở [[SWD392]].

- **Model**: dữ liệu và nghiệp vụ (DAO, entity).
- **View**: giao diện (JSP).
- **Controller**: nhận request, gọi Model, chọn View (Servlet).

Luồng: Request → Controller → Model → Controller → View → Response.

## Flashcards
Trong Java Web (PRJ301), thành phần nào thường đóng vai trò Controller?::Servlet
Ba thành phần của MVC?::Model, View, Controller
''',
    'Scrum': '''
Framework Agile phát triển phần mềm theo vòng lặp ngắn. Gặp ở [[SWE201c]], áp dụng thật ở [[SWP391]], [[SEP490]], quản lý trong [[PMG201c]].

- **Vai trò**: Product Owner, Scrum Master, Developers.
- **Sự kiện**: Sprint (1–4 tuần), Sprint Planning, Daily Scrum (15 phút), Sprint Review, Sprint Retrospective.
- **Artifact**: Product Backlog, Sprint Backlog, Increment.

## Flashcards
Ba vai trò trong Scrum?::Product Owner, Scrum Master, Developers
Daily Scrum kéo dài tối đa bao lâu?::15 phút
Ai chịu trách nhiệm sắp xếp ưu tiên Product Backlog?::Product Owner
''',
    'Kiểm thử hộp đen và hộp trắng': '''
Hai hướng tiếp cận kiểm thử trong [[SWT301]].

- **Hộp đen (black-box)**: kiểm tra theo đặc tả, không nhìn code. Kỹ thuật: phân vùng tương đương, phân tích giá trị biên, bảng quyết định.
- **Hộp trắng (white-box)**: dựa trên cấu trúc code. Kỹ thuật: statement coverage, branch/decision coverage, path coverage.

## Flashcards
Phân tích giá trị biên thuộc kỹ thuật kiểm thử hộp đen hay hộp trắng?::Hộp đen
Branch coverage đo điều gì?::Tỉ lệ nhánh (true/false của mỗi điều kiện) đã được thực thi
''',
    'React Hooks': '''
Hooks cho phép function component có state và side effect. Học trong [[FER202]].

- `useState`: state cục bộ.
- `useEffect`: side effect (gọi API, subscription); mảng dependency quyết định khi nào chạy lại.
- `useContext`: đọc context, tránh prop drilling.
- `useMemo` / `useCallback`: ghi nhớ giá trị/hàm để tránh tính lại.

Quy tắc: chỉ gọi hook ở **top level** của component, không gọi trong vòng lặp/điều kiện.

## Flashcards
useEffect với mảng dependency rỗng chạy khi nào?::Một lần sau lần render đầu tiên (mount)
Quy tắc quan trọng khi gọi hooks?::Chỉ gọi ở top level của function component hoặc custom hook, không trong vòng lặp/điều kiện
''',
    'Vòng đời Widget trong Flutter': '''
Kiến thức nền cho [[PRM392]].

- **StatelessWidget**: không có state thay đổi, chỉ có `build()`.
- **StatefulWidget** → `State` có vòng đời:
  1. `createState()`
  2. `initState()` — chạy một lần, khởi tạo controller/subscription.
  3. `didChangeDependencies()`
  4. `build()` — gọi lại mỗi khi `setState()`.
  5. `didUpdateWidget()` — widget cha rebuild với cấu hình mới.
  6. `dispose()` — giải phóng controller, hủy subscription.

## Flashcards
Nên khởi tạo TextEditingController ở phương thức nào của State?::initState()
Phương thức nào dùng để giải phóng tài nguyên của State?::dispose()
Gọi setState() dẫn tới điều gì?::Đánh dấu State cần rebuild, build() được gọi lại
''',
    'Design Patterns': '''
Giải pháp đã được kiểm chứng cho các vấn đề thiết kế lặp lại, dựa trên [[Lập trình hướng đối tượng (OOP)]]. Học trong [[SWD392]].

- **Creational**: Singleton, Factory Method, Builder.
- **Structural**: Adapter, Decorator, Facade.
- **Behavioral**: Observer, Strategy, Command.

[[MVC]] kết hợp nhiều pattern: Observer (Model–View), Strategy (Controller).

## Flashcards
Singleton đảm bảo điều gì?::Một lớp chỉ có duy nhất một instance và có điểm truy cập toàn cục
Observer thuộc nhóm pattern nào?::Behavioral
''',
  };

  /// Writes the vault into [dir]. Existing files are never overwritten.
  static Future<void> create(String dir) async {
    Future<void> write(String rel, String content) async {
      final f = File(p.joinAll([dir, ...rel.split('/')]));
      if (await f.exists()) return;
      await f.parent.create(recursive: true);
      await f.writeAsString(content);
    }

    final semesters = <int, List<(String, String, int, List<String>, List<String>)>>{};
    for (final c in _courses) {
      (semesters[c.$3] ??= []).add(c);
    }

    for (final (code, name, sem, prereqs, concepts) in _courses) {
      await write('Courses/$code.md', '''
---
type: course
code: $code
name: $name
semester: $sem
status: todo
prerequisites: [${prereqs.join(', ')}]
tags: [course, ky$sem]
aliases: [$name]
---
# $code — $name

> [!info] Kỳ $sem
> Môn tiên quyết: ${prereqs.isEmpty ? 'không' : prereqs.map((e) => '[[$e]]').join(', ')}

## Khái niệm chính
${concepts.isEmpty ? '- ' : concepts.map((e) => '- [[$e]]').join('\n')}

## Ghi chú buổi học
-

## Tài liệu & đề thi
-

## Flashcards
''');
    }

    for (final e in _concepts.entries) {
      await write('Concepts/${e.key}.md', '---\ntype: concept\ntags: [concept]\n---\n# ${e.key}\n\n${e.value}');
    }

    final home = StringBuffer('''
# 🧠 FPTU SE Second Brain

Vault kiến thức ngành **Kỹ thuật phần mềm – Đại học FPT**, dùng được cả trong Obsidian lẫn ứng dụng FPTU Brain.

> [!warning] Lộ trình tham khảo
> Danh sách môn khác nhau giữa các khóa. Hãy đối chiếu với curriculum trên FAP và sửa file trong `Courses/` cho khớp.

## Cách dùng
- Mỗi môn là một note trong `Courses/`, trạng thái nằm ở property `status` (todo / learning / done).
- Khái niệm dùng chung giữa các môn đặt trong `Concepts/` và nối với nhau bằng `[[wikilink]]`.
- Viết flashcard theo cú pháp `Câu hỏi::Trả lời` ở bất kỳ note nào.

''');
    for (final s in semesters.keys.toList()..sort()) {
      home.writeln('## Kỳ $s');
      for (final c in semesters[s]!) {
        home.writeln('- [[${c.$1}]] — ${c.$2}');
      }
      home.writeln();
    }
    await write('Home.md', home.toString());
  }
}
