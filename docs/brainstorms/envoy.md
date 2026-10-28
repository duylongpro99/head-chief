# Định nghĩa Envoy peer session & skill `envoy-peer`

Trạng thái: yêu cầu đã review và chốt quyết định ngày 2026-10-28, sẵn sàng lên kế hoạch.

## Mục tiêu

Từ một session đang chạy trong Herdr, giao một công việc có tiêu chí nghiệm thu rõ ràng cho một agent **khác loại** chạy trong pane Herdr riêng (`envoy`), để một reviewer độc lập chấm kết quả theo tiêu chí đó, lặp đến khi đạt, rồi chỉ đưa kết quả cuối về session chính. Session chính không bị ảnh hưởng bởi quá trình làm việc của envoy lẫn quá trình review.

## Thuật ngữ

- **controller**: session chính, nơi người dùng gọi skill. Chỉ điều phối: dựng brief, mở pane, giao việc, chờ, chuyển findings, đóng pane, báo cáo.
- **envoy**: peer session làm việc, là một pane Herdr chạy agent ngoài (codex, pi, grok, hermes, claude, ...). Không phải subagent; không dùng cơ chế subagent của bất kỳ host nào.
- **reviewer**: peer session thứ hai trong pane Herdr riêng, chấm kết quả của envoy theo brief. Không sửa code.
- **envoy-peer**: skill cài vào host, cung cấp toàn bộ flow trên.
- **run**: một lần giao việc, có thư mục riêng chứa brief, result, review và trạng thái.

## Yêu cầu

### 1. Loại envoy và cách chọn

- Loại envoy luôn **khác loại với controller**. Loại của controller lấy từ Herdr, không đoán từ env:

```bash
herdr agent get "$HERDR_PANE_ID" | jq -r '.result.agent.agent'   # ví dụ: claude
```

- Danh sách loại khả dụng = loại Herdr hỗ trợ (`herdr agent start --help`) giao với binary có trên PATH, trừ loại của controller. Không hard-code danh sách.
- Người dùng không nêu loại: skill đưa options (chỉ loại khả dụng) để chọn rồi tiếp tục. Nêu loại (`--kind codex`): đi thẳng. Loại không cài: báo và dừng, không tự thay thế.
- `claude` là loại envoy hợp lệ khi controller không phải Claude Code.

### 2. Authentication và global config state

- Credential do từng CLI tự giữ trong kho riêng của nó (ví dụ `~/.codex/auth.json`, `~/.grok/auth.json`). Skill **không lưu, không đọc, không in** credential.
- Mỗi loại có một lệnh probe không in secret (ví dụ `codex login status`, `pi auth check --no-refresh`). Loại chưa có lệnh như vậy thì plan xác minh khi hiện thực; fallback là một prompt smoke-test ngắn trong pane.
- Chưa sẵn sàng: skill mở pane Herdr và hướng dẫn người dùng tự login (skill không nhập credential), rồi probe lại.
- Global state tại `~/.config/envoy-peer/state.json`, dùng chung mọi project: loại đã verify kèm thời điểm và version; preference (loại mặc định, loại reviewer, model, timeout, max rounds). State chỉ để bỏ qua bước hướng dẫn setup; mỗi run vẫn probe nhanh vì token có thể hết hạn.

### 3. Brief đầu vào (dispatch contract)

Pane envoy bị đóng sau khi xong và envoy không được hỏi lại, nên brief phải đủ để envoy tự quyết các điểm ẩn. Brief ghi thành file `brief.md` trong thư mục run; prompt gửi vào pane chỉ trỏ tới file đó.

Các mục bắt buộc:

- **Mission**: outcome mong muốn và định nghĩa "xong".
- **Acceptance criteria**: kiểm chứng được (lệnh test, hành vi quan sát được). Trống thì không dispatch.
- **Context**: đường dẫn file/doc liên quan, quyết định đã chốt, convention của repo. Trỏ đường dẫn, không dump nội dung.
- **Scope**: file/thư mục được sửa và cấm sửa.
- **Constraints**: mặc định không commit, không push, không xóa hay ghi đè ngoài scope, không hành động có side effect ngoài repo (deploy, gọi API ghi) trừ khi brief cho phép.
- **Verification**: lệnh envoy phải chạy và phải xanh trước khi báo xong (test, lint, build của repo).
- **Hidden points**: edge case, rủi ro, câu hỏi có thể phát sinh cùng câu trả lời hoặc giả định đã chốt. Skill scout repo để điền; chỉ hỏi người dùng khi là quyết định không tự suy ra được.
- **Output contract**: theo mục 4.
- **Autonomy contract**: envoy không được dừng để hỏi. Gặp điểm chưa rõ thì chọn giả định hợp lý nhất, ghi vào `Assumptions`, làm tiếp.

Trước khi dispatch, skill chạy completeness check theo đúng danh sách trên; thiếu mục nào thì bổ sung hoặc hỏi người dùng. Tham khảo cấu trúc chín mục của `ak:handoff` (artifact-schema) làm mẫu, không gọi skill đó.

### 4. Output contract

- Envoy ghi kết quả vào `result.md` trong thư mục run, rồi trả lời trong pane **chỉ bằng đường dẫn file**. Không dựa vào `herdr agent read` để lấy kết quả vì chỉ lấy được vài trăm dòng terminal.
- `result.md` gồm: Summary; Changes (file đã sửa); Verification (lệnh đã chạy, kết quả); Assumptions; Unresolved/Concerns; Status `DONE | DONE_WITH_CONCERNS | BLOCKED`.
- Message cuối đưa vào session chính gồm: status, tóm tắt vài dòng, số vòng review, đường dẫn `result.md` và `review-<n>.md`. Không gì khác.

### 5. Review loop

- Reviewer là peer session riêng, mở sau khi envoy trả kết quả lần đầu. Mặc định cùng loại với controller (controller Claude Code thì reviewer Claude Code); chọn loại khác bằng `--reviewer <kind>`. Reviewer không bao giờ là chính session envoy.
- Reviewer nhận đường dẫn brief, result và baseline (HEAD và `git status` trước dispatch). Reviewer đọc diff so với baseline, chạy lại verification, đối chiếu từng acceptance criterion, ghi `review-<n>.md` với verdict `ACCEPT` hoặc danh sách findings (mức độ, bằng chứng file:line, cách kiểm chứng). Khi công việc là code, reviewer dùng skill review có sẵn trên host (ví dụ `ak:code-review`) nếu được cài.
- Có findings: controller gửi đường dẫn `review-<n>.md` vào **cùng session envoy** với yêu cầu đọc file, xử lý mọi finding, chạy lại verification và cập nhật `result.md`. Controller không chép nội dung findings vào context của mình.
- Dừng khi ACCEPT, hoặc hết max rounds (mặc định 3), hoặc envoy/reviewer báo BLOCKED. Hết round mà chưa ACCEPT thì trả `DONE_WITH_CONCERNS` kèm findings còn lại, không im lặng.
- Finding mâu thuẫn với brief hoặc quyết định người dùng đã chốt: controller hỏi người dùng thay vì để hai bên lặp.

### 6. Context management

- Controller chỉ đọc `run.json`, `result.md` lần cuối và status JSON của Herdr. Không đọc transcript pane trừ khi chẩn đoán lỗi, và khi đó chỉ đọc bounded qua `herdr agent read --lines`.
- Quá trình làm việc của envoy và quá trình review nằm hoàn toàn trong pane riêng và file trong thư mục run.
- Chờ bằng `herdr agent prompt --wait` hoặc `herdr agent wait` theo từng khoảng bounded (mỗi lần gọi tối đa 10 phút vì giới hạn tool của host), lặp đến khi settled hoặc hết timeout tổng (mặc định 60 phút, cấu hình được).

### 7. Lifecycle và process management

- Mỗi run có một envoy và một reviewer. Nhiều envoy song song nằm ngoài scope bản đầu.
- Tên agent Herdr: `envoy-<kind>-<slug>` và `reviewer-<kind>-<slug>` (theo regex tên của Herdr). Mở pane bằng `herdr pane split` hoặc `herdr tab create` với `--no-focus`, rồi `herdr agent start <name> --kind <kind> --pane <id> -- <args>`.
- `run.json` ghi pane id, agent name, kind, cwd, baseline, trạng thái, timestamp, để cleanup được khi controller chết giữa chừng (`envoy-peer --cleanup <run>`).
- Kết thúc, thành công hay thất bại, đều đóng cả hai pane và giữ nguyên file trong thư mục run. Muốn hỏi tiếp thì mở envoy mới với brief mới, có thể trỏ tới run cũ làm context.
- Trạng thái `blocked` (dialog approval, trust, onboarding): controller đọc dialog và đưa cho người dùng quyết; không tự trả lời dialog lạ. Timeout coi như BLOCKED: đọc pane để chẩn đoán rồi báo người dùng.
- Chỉ đóng pane do run này tạo.

### 8. Workspace và permission

- Envoy làm việc **trong cùng cây** với controller, cwd bằng cwd của controller. Trong lúc chờ, controller không sửa cây; skill nhắc điều này khi dispatch.
- Trước dispatch ghi baseline: `git rev-parse HEAD` và `git status --short`. Cây bẩn không chặn, nhưng baseline ghi lại để reviewer phân biệt thay đổi của envoy.
- Envoy chạy **full permission**: bỏ mọi approval và sandbox của CLI. Flag từng loại nằm ở một bảng duy nhất trong skill (ví dụ claude `--dangerously-skip-permissions`, codex `--dangerously-bypass-approvals-and-sandbox`); các loại còn lại plan xác minh qua `--help` thật khi hiện thực. Reviewer chạy cùng mode để chạy được verification.
- Mặc định envoy không commit, không push; brief có thể cho phép.

### 9. Dependency

- Herdr: `HERDR_ENV=1` và binary `herdr` trên PATH. Ngoài Herdr thì báo và dừng, không fallback.
- `jq`, `bash`, `git`.
- Skill `herdr` tại `~/personal/agent/general-cc-kit/skills/herdr` là tài liệu tham chiếu CLI. Script của envoy-peer viết và kiểm chứng trực tiếp với binary đã cài, vì CLI Herdr từng lệch khỏi doc (xem ghi chú trong `managed-session`).

### 10. Đóng gói và install

- Thư mục `skills/envoy-peer/` gồm `SKILL.md`, `references/` (brief-template, result-template, review-template, bảng kinds và flags), `scripts/` (probe, start, prompt-wait, stop, cleanup, state) và `evals/`. Không có file agent.
- Thêm vào `skills.sh.json` (grouping Session Orchestration) và README.
- `install.sh` tại root: symlink `skills/<name>` (mặc định envoy-peer) vào thư mục skill của host (`~/.claude/skills`, `~/.agents/skills`, hoặc `--target <dir>`); `--project` link vào `.claude/skills` của project hiện tại (đã gitignore); idempotent; có `--uninstall`. Dùng để dev và test; phân phối vẫn qua `npx skills add` (copy, không symlink).
- Script tái dùng pattern của `managed-session` nhưng generic theo `--kind`; không sửa managed-session.

### 11. Tích hợp agentkit

- Tái dùng ý tưởng: schema brief từ `ak:handoff`, nguyên tắc reviewer độc lập từ `ak:orchestrate`, `ak:code-review` cho reviewer khi công việc là code.
- Không wrap hay gọi `ak:orchestrate` (headless, YAML job spec, không dùng Herdr).

## Non-goals

- Không dùng cơ chế subagent của host.
- Không lưu, đọc hay nhập credential.
- Không tự trả lời approval hay trust dialog.
- Không chạy ngoài Herdr.
- Không thay thế `ak:orchestrate`, `ak:handoff --dispatch` hay `head-chief`.
- Không giữ pane sau khi xong; không nhiều envoy song song trong bản đầu.
- Không worktree mặc định (có thể thêm `--worktree` sau).

## Acceptance criteria của bộ skill

1. Từ Claude Code trong Herdr, gọi skill không nêu loại: options chỉ gồm loại đã cài và khác `claude`.
2. Nêu `--kind codex`: dispatch thẳng, không hỏi loại.
3. Loại chưa verify: hướng dẫn setup và lưu state global; gọi lại ở project khác không hỏi lại.
4. Mỗi run tạo thư mục run với `brief.md`, `result.md`, `review-<n>.md`, `run.json`; brief thiếu acceptance criteria thì không dispatch.
5. Loop chạy đến ACCEPT hoặc max rounds; message cuối chỉ gồm status, tóm tắt, số vòng và đường dẫn.
6. Cả hai pane đóng khi kết thúc, kể cả khi lỗi; `--cleanup` dọn được run bỏ dở.
7. Từ host codex, options loại trừ `codex` và chấp nhận `claude` (kiểm tra portable).
8. `install.sh` tạo symlink, chạy lại không lỗi, `--uninstall` gỡ sạch.

## Quyết định đã chốt (2026-10-28)

- Envoy là peer session trong pane Herdr, không phải subagent.
- Envoy chạy full permission.
- Reviewer mặc định cùng loại với controller, chọn được loại khác, luôn là peer session riêng.
- Đóng pane sau khi xong; hỏi tiếp là mở envoy mới. Vì vậy brief phải đủ và output phải đạt tiêu chí trước khi trả về.
- Làm việc trong cùng cây, không worktree.

## Câu hỏi còn mở (plan xác minh)

- Flag full-permission và lệnh probe auth của grok, pi, hermes.
- Vị trí thư mục run: `.envoy/runs/<ts>-<slug>/` ở project root (theo precedent `.orchestrator/` của head-chief) hay `plans/reports/envoy-<ts>-<slug>/`. Đề xuất `.envoy/` vì portable sang project không có `plans/`.
- Mặc định max rounds 3 và timeout tổng 60 phút.
