---
phase: 4
title: "Đóng gói, docs, evals, kiểm thử end-to-end"
status: completed
priority: P1
effort: "4h"
dependencies: [3]
---

# Phase 4: Đóng gói và kiểm thử end-to-end

## Goal

Đưa `envoy-peer` vào bộ phân phối (skills.sh.json, README), viết evals, rồi chạy một run thật từ Claude Code với envoy codex và reviewer claude để chứng minh 8 acceptance criteria, kể cả kiểm tra portable từ pane codex, mà không để lại pane, tiến trình hay file rác.

## Context

- Yêu cầu 10, 11 và "Acceptance criteria của bộ skill" trong `docs/brainstorms/envoy.md`.
- `skills.sh.json:5-9` (grouping "Session Orchestration", mảng `skills`); `README.md` có các chỗ cần đổi: `:5` "three skills", `:7-13` bảng skill, `:18` "Install both skills", `:69-93` layout, `:73` "discovers both", `:95-100` Development, `:109` lệnh update.
- Định dạng evals: `skills/head-chief/evals/evals.json:1-20` (`skill_name`, `evals[]` với `id`, `prompt`, `expected_output`, `files`, `assertions[]`).
- `skills/head-chief/scripts/quick_validate.py:24` chỉ quét head-chief; envoy-peer không được quét secret-hygiene tự động, nên bước review cuối phải `grep` thủ công.

## Files to Create / Modify

- Modify: `skills.sh.json` (thêm `"envoy-peer"` vào `skills` của grouping; cập nhật `description` để nhắc peer session khác loại)
- Modify: `README.md` (đổi "three skills" thành bốn; bảng skill thêm dòng envoy-peer; Install ví dụ `--skill envoy-peer` và sửa "both"; Repository layout thêm `skills/envoy-peer/` và `install.sh`; Requirements thêm `jq` và các CLI envoy; Development thêm `./install.sh --project` và ghi chú symlink theo HEAD; lệnh update thêm `envoy-peer`)
- Create: `skills/envoy-peer/evals/evals.json`
- Create: `plans/reports/tester-261028-<hhmm>-envoy-peer-e2e.md` (báo cáo kiểm thử, có bằng chứng lệnh/kết quả)

## Tasks & Steps

1. **`skills.sh.json`**: thêm `envoy-peer` vào mảng; `jq . skills.sh.json` hợp lệ.

2. **`README.md`**: giữ văn phong hiện có; mỗi mục một đoạn ngắn; không dán nội dung SKILL.md. Ghi rõ: envoy chạy full permission trong cùng cây, credential do từng CLI giữ, run dir `.envoy/` tự ignore, `install.sh` symlink chạy theo checkout hiện tại.

3. **`evals/evals.json`** với `skill_name: envoy-peer`, tối thiểu 7 case: (1) gọi không nêu kind → options từ `probe.sh list`, không có kind controller; (2) `--kind codex` → không hỏi kind; (3) kind chưa cài → báo và dừng, không thay thế; (4) brief thiếu acceptance criteria → không dispatch; (5) reviewer FINDINGS rồi ACCEPT ở round 2 → message cuối chỉ status/tóm tắt/round/đường dẫn; (6) `--cleanup --all` → dry-run trước, chỉ đóng run của controller này hoặc controller đã chết; (7) pane `blocked` trong onboarding → không đọc pane, chỉ bảo user mở pane theo label; (8) sau compaction → đọc `run.json` trước khi tiếp tục. Mỗi case 3–4 assertions theo mẫu head-chief.

4. **E2E thật** (chạy từ pane Claude Code này; sandbox là một repo tạm để không làm bẩn head-chief; mọi lệnh chờ gọi với timeout tool 600000; `export XDG_CONFIG_HOME=<scratch>` để không chạm state thật):
   1. `herdr pane list | jq -r '.result.panes[].pane_id' | sort > <scratch>/panes-before.txt`.
   2. Tạo repo tạm trong scratchpad: `git init`, một script `greet.sh` in sai, một test `test.sh` so sánh output và đang đỏ, commit "init". Thêm một file untracked và một sửa chưa commit ngoài scope để kiểm baseline (reviewer không được quy cho envoy).
   3. Gọi skill theo SKILL.md với `--kind codex --cwd <repo tạm>`, task "make test.sh pass without changing test.sh", reviewer mặc định (claude). Ghi lại: options có được hỏi không (AC2: không), run dir và file (AC4), số round và message cuối (AC5), hai pane đóng (AC6), guard `clean`, Baseline check của reviewer không nêu file ngoài scope đã bẩn từ trước.
   4. AC1: gọi lại không nêu kind trong repo tạm → ghi lại options hiển thị (không có `claude`, chỉ kind `selectable`); hủy sau khi thấy options (`cleanup.sh --run` cho run vừa tạo nếu đã tạo).
   5. AC3: `state.sh clear codex`, chạy lại flow với `--kind codex` → probe ready nên không onboarding nhưng `state.sh get codex` được ghi (Step 3 của SKILL.md); `cd` sang thư mục khác chạy `probe.sh auth codex` + `state.sh get codex` → verified. Với grok (no-probe): chạy nhánh onboarding smoke một lần; nếu grok chưa login thì ghi lại rằng `start.sh` trả 4/11 và SKILL.md chỉ in label pane, không in nội dung (bằng chứng cho nhánh onboarding), rồi `cleanup.sh --run`.
   6. AC6 orphan: `new-run.sh` + `start.sh` một envoy, không stop; `/envoy-peer --cleanup --all` → dry-run liệt kê, rồi `--yes` đóng; `herdr pane list` chỉ khác pane đó.
   7. AC7 portable (không dùng `start.sh`, không tạo run): mở một pane shell: `P=$(herdr pane split --current --direction down --cwd "$PWD" --no-focus | jq -r '.result.pane.pane_id')`; `herdr agent start portable-codex --kind codex --pane $P -- --dangerously-bypass-approvals-and-sandbox`; `herdr agent prompt $P "Run exactly this command and reply done: <abs>/skills/envoy-peer/scripts/probe.sh list --json > <scratch>/portable.json; <abs>/skills/envoy-peer/scripts/prompt-wait.sh --help > <scratch>/portable-help.txt" --wait --timeout 300000`; kiểm `jq -r '.[].kind' <scratch>/portable.json` không có `codex`, có `claude`; `herdr pane close $P`. (Script lấy kind controller từ `HERDR_PANE_ID` của pane codex, nên kết quả chứng minh portable; chạy được `--help` chứng minh script khởi động trên host codex.)
   8. AC8: lặp lại verification install của Phase 1 với `--project` trong repo tạm (sau khi thêm `.claude/` vào `.gitignore` của nó) và với `~/.claude/skills` thật (rồi `--uninstall`).
   9. Dọn: `cleanup.sh --all --root <repo tạm>/.envoy --yes`, rồi mới xóa `.envoy/` của repo tạm và của head-chief nếu có; `herdr pane list … | diff - panes-before.txt` phải rỗng; `ps` không còn tiến trình codex/claude do test mở.

5. **Báo cáo** `plans/reports/tester-261028-<hhmm>-envoy-peer-e2e.md`: bảng AC1–AC8 với lệnh, kết quả, pane id đã mở/đóng; những gì không chạy được và lý do; Status protocol cuối (`DONE | DONE_WITH_CONCERNS | BLOCKED`).

6. **Tự review**: dùng skill review có sẵn trên host (ví dụ `ak:code-review` hoặc `code-review`) trên diff; `grep -rnE 'sk-|xai-|eyJ|auth\.json' skills/envoy-peer install.sh` phải rỗng; sửa findings thật; không commit (user quyết định commit; khi commit dùng conventional commit, ví dụ `feat: envoy-peer skill for cross-kind peer sessions`).

## Verification

```bash
cd /Users/onedayin20902/personal/head-chief
jq -e '.groupings[0].skills | index("envoy-peer")' skills.sh.json
jq -e '.skill_name=="envoy-peer" and (.evals|length) >= 7' skills/envoy-peer/evals/evals.json
grep -n 'envoy-peer' README.md | head; grep -nE 'three skills|Install both|discovers both' README.md   # dòng thứ hai phải rỗng
test -f plans/reports/tester-261028-*-envoy-peer-e2e.md
jq -r '.[].kind' <scratch>/portable.json | grep -vq '^codex$' && jq -r '.[].kind' <scratch>/portable.json | grep -q '^claude$'
herdr pane list | jq -r '.result.panes[].pane_id' | sort | diff - <scratch>/panes-before.txt && echo "no leftover panes"
ls .envoy 2>/dev/null; echo "no leftover runs expected"
grep -rnE 'sk-[A-Za-z0-9]|xai-|eyJ|auth\.json' skills/envoy-peer install.sh; echo "no secrets expected"
git status --short     # chỉ các file của skill, install.sh, README, skills.sh.json, .gitignore, plan, report
```

## Todo

- [x] `skills.sh.json` có envoy-peer
- [x] `README.md` cập nhật bảng, install, layout, requirements, development, update; không còn "three skills"/"both"
- [x] `evals/evals.json` ≥ 7 case (8 case)
- [x] E2E AC1–AC8 có bằng chứng trong [report](../reports/tester-261028-1723-envoy-peer-e2e.md), gồm lần chạy lại live với grok và agy; pane list trước/sau khớp. `Status: DONE`; còn lại: codex chưa chạy được việc vì 9Router trả `401 Missing API key` (cấu hình provider của codex không truyền key, user chọn giữ nguyên), omp chưa có model
- [x] Review diff bằng skill review trên host (10 findings, đã sửa và kiểm lại); grep secret chỉ còn 3 false positive ("Task-specific", 2 regex của `redact`)
- [x] Không còn pane/run/tiến trình mồ côi do skill mở; chưa commit. Hai daemon `codex app-server` (PID 70857, 70885) do codex 0.165.0 tự cập nhật để lại, không bị kill

## Success Criteria

- Report ghi `Status: DONE` với 8/8 AC có bằng chứng, hoặc `DONE_WITH_CONCERNS` nêu rõ AC nào chưa chứng minh được và vì sao (ví dụ grok chưa login).
- `npx skills add duylongpro99/head-chief --skill envoy-peer` sẽ thấy skill nhờ `skills/envoy-peer/SKILL.md` (kiểm cục bộ bằng `npx skills use . --skill envoy-peer 2>/dev/null | head` nếu CLI hỗ trợ đường dẫn local; không thì ghi nhận là kiểm sau khi push).

## Risk

- Codex trong repo tạm có thể hỏi trust lần đầu → exit 4, xử lý tay một lần và ghi vào report (đây cũng là bằng chứng cho nhánh onboarding).
- E2E tốn token của codex và claude; brief giữ nhỏ (một file, một test).
- Bash tool của host có thể reset cwd giữa các lần gọi; luôn truyền `--cwd` và đường dẫn tuyệt đối.
