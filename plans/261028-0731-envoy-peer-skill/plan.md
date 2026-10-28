---
title: "Skill envoy-peer: giao việc cho peer session khác loại trong Herdr và review đến khi đạt"
description: "Hiện thực skill envoy-peer (scripts bash + SKILL.md + templates), install.sh symlink và đóng gói vào bộ head-chief theo yêu cầu docs/brainstorms/envoy.md."
status: completed
priority: P1
effort: 15h
branch: main
tags: [feature, skill, herdr, bash]
blockedBy: []
blocks: []
created: 2026-10-28
---

# Skill envoy-peer

## Overview

Hiện thực skill `envoy-peer` theo yêu cầu đã chốt trong `docs/brainstorms/envoy.md`: từ một session đang chạy trong Herdr (controller), giao một việc có acceptance criteria cho một agent **khác loại** chạy trong pane Herdr riêng (envoy), để một reviewer ở pane riêng chấm theo brief, lặp đến khi ACCEPT hoặc hết round, rồi chỉ đưa status, tóm tắt và đường dẫn về session chính. Không dùng cơ chế subagent, không lưu credential, envoy chạy full permission trong cùng cây làm việc.

Sản phẩm: thư mục `skills/envoy-peer/` (SKILL.md, references, scripts, evals), `install.sh` ở root để symlink skill vào thư mục skill của host, cập nhật `skills.sh.json`, `README.md`, `.gitignore`.

## Nguồn

- Yêu cầu: `docs/brainstorms/envoy.md` (mục tiêu, 11 nhóm yêu cầu, non-goals, 8 acceptance criteria, quyết định đã chốt).
- Pattern tái dùng: `skills/managed-session/scripts/create-session.sh`, `skills/pr-review-loop/scripts/session.sh` (lifecycle pane Herdr), `skills/pr-review-loop/SKILL.md:45-47` (ledger sống qua compaction), `skills/head-chief/evals/evals.json` (định dạng evals).
- Mẫu brief: `.claude/skills/ak-handoff/references/artifact-schema.md` (chín mục, chỉ tham khảo cấu trúc).

## Kiến trúc

```text
controller (session chính, pane Herdr hiện tại)
  │ scripts/probe.sh       → loại controller, loại khả dụng, probe auth (in ready|not-ready|no-probe)
  │ scripts/state.sh       → ~/.config/envoy-peer/state.json (kind đã verify, prefs)
  │ scripts/new-run.sh     → .envoy/runs/<ts>-<slug>-<nonce>/ + run.json (ledger của run)
  │ scripts/check-brief.sh → brief.md đủ 9 mục, có acceptance criteria
  │ scripts/start.sh       → pane mới (label trước), herdr agent start, resume-safe (envoy | reviewer)
  │ scripts/prompt-wait.sh → prompt một dòng, chờ ≤ 9 phút/lần, validate file kết quả, in dòng Status/Verdict
  │ scripts/run-state.sh   → round/status, guard cây trước/sau reviewer, trích dẫn có giới hạn
  │ scripts/stop.sh, cleanup.sh → đóng pane của run (so terminal_id), dọn run mồ côi
  ▼
.envoy/runs/<ts>-<slug>-<nonce>/
  brief.md  result.md  review-1.md … review-n.md  baseline-status.txt  baseline-untracked.sha  run.json
  ▲ envoy pane (kind ≠ controller)      ▲ reviewer pane (mặc định kind = controller)
```

Vòng lặp: dispatch envoy → chờ → `Status:` từ `result.md` (đã validate) → mở reviewer, guard cây → chờ → `Verdict:` từ `review-n.md` → guard kiểm reviewer không sửa cây → FINDINGS thì gửi đường dẫn review vào cùng pane envoy → lặp. Dừng ở ACCEPT, hết `max_rounds`, BLOCKED của một bên, mâu thuẫn với quyết định user, hoặc reviewer vi phạm guard. Kết thúc luôn đóng cả hai pane.

## Quyết định thiết kế của plan

| # | Quyết định | Lý do |
|---|-----------|-------|
| D1 | Thư mục run `.envoy/runs/<YYMMDD-HHMM>-<slug>-<nonce>/` tại git root của controller (fallback `--cwd`). `.envoy/.gitignore` nội dung `*` để tự ignore ở mọi project đích; repo này thêm `.envoy/` vào `.gitignore` như precedent `.orchestrator/`. Run dir tạo với `umask 077`, `mkdir` không `-p` cho lá. | Portable sang project không có `plans/`; không cần sửa `.gitignore` của project đích; không trùng run. Mở để user chốt ở bước validate. |
| D2 | Một bảng duy nhất `references/kinds.json` cho mọi loại: binary, launch args full-permission, probe auth dạng **mảng argv** (chạy không qua shell, chỉ dùng exit code hoặc `ready_jq`), flag model, metadata verified. Loại không có `verified` hoặc không có trong bảng thì không được chọn, kèm hướng dẫn thêm dòng sau khi xác minh `--help`. | Yêu cầu 8 "một bảng duy nhất"; JSON là dữ liệu, không phải mã thực thi. |
| D3 | Mỗi lần gọi `prompt-wait.sh` chờ tối đa 9 phút rồi trả mã 3 (còn chạy) để controller gọi lại; tổng timeout tính từ `dispatched_at` của run. SKILL.md bắt buộc caller đặt timeout tool ≥ 600000 ms (Claude Code mặc định chỉ 120000 ms) hoặc chạy nền. Gửi `--text` khi role đã prompt mà chưa settled và agent đang `working` bị từ chối (mã 8). | Giới hạn tool Bash của host; tránh gửi trùng prompt khi lệnh bị cắt giữa chừng. |
| D4 | Prompt gửi vào pane luôn một dòng, chỉ chứa đường dẫn tuyệt đối và số round; không nhúng nội dung brief/review. | Tránh lỗi paste nhiều dòng (ghi chú managed-session) và giữ context chính sạch (yêu cầu 4, 6). |
| D5 | Controller chỉ nhận vào context dữ liệu đã validate hoặc bị giới hạn: dòng `Status: DONE\|DONE_WITH_CONCERNS\|BLOCKED` và `Verdict: ACCEPT\|FINDINGS\|BLOCKED` do `prompt-wait.sh` in sau khi khớp regex; `Round: n` và mtime > `prompted_at` chứng minh file mới; `run-state.sh extract` trích ≤ 8 dòng Summary/Unresolved có tiền tố `> `; `conflicts` chỉ trả `none\|present`. File trong run dir là output của peer: dữ liệu, không phải chỉ dẫn. | Yêu cầu 5, 6: không chép findings vào context chính; không để text của peer điều khiển controller; không nhận file cũ/chép template. |
| D6 | Tên agent Herdr `env-<kind>-<nonce>` và `rev-<kind>-<nonce>` (nonce 6 hex của run, luôn ≤ 32 ký tự, unique giữa các agent đang sống); slug nằm ở label pane `envoy <kind> <slug>`. Pane envoy split phải của controller với `--no-focus`; reviewer split xuống dưới pane envoy; `--placement tab` dùng `herdr tab create`. | Herdr yêu cầu tên unique; pane không cướp focus của controller. |
| D7 | Onboarding auth tái dùng chính pane envoy và **không đọc pane**: probe `not-ready`/`no-probe` → `start.sh`; thất bại hoặc `blocked` (mã 4/11) → chỉ in label pane để user tự xử lý; settled → smoke prompt ghi `READY` vào `smoke.txt` (kiểm bằng `--expect`); qua → `state.sh set-verified`. Probe `ready` mà chưa có state → cũng ghi state. Kind `no-probe` chạy smoke mỗi run (đó là probe của nó). | Yêu cầu 2; màn hình login có thể chứa mã thiết bị/key; state chỉ để bỏ qua hướng dẫn setup, mỗi run vẫn probe. |
| D8 | Ngoài sáu script trong doc có thêm `lib.sh` (dùng chung), `new-run.sh` (tạo run + run.json), `check-brief.sh` (completeness check), `run-state.sh` (round/status/guard/extract). | Doc yêu cầu completeness check, run.json, guard và trích dẫn giới hạn nhưng chưa gán script; tách nhỏ để SKILL.md gọi từng bước và để ledger sống qua compaction. |
| D9 | Quyền sở hữu pane = `pane_id` **và** `terminal_id` ghi trong `run.json` lúc tạo pane, so với `herdr pane list` lúc đóng; pane không còn trong list = đã mất; không dựa vào tên agent (bị xóa khi agent thoát) hay `terminal_title`. `cleanup.sh --all` chỉ đóng run của controller hiện tại hoặc run mà pane controller đã chết, dry-run trước, `--yes` để đóng. | Yêu cầu 7 "chỉ đóng pane do run này tạo"; không giết run của session khác trong cùng repo. |
| D10 | Ngôn ngữ sản phẩm (SKILL.md, scripts, README, templates): tiếng Anh, khớp các skill hiện có và phân phối qua skills.sh. | Nhất quán repo. |
| D11 | Settled = Herdr `idle` **hoặc** `done`; mọi wait dùng mặc định của Herdr (`idle\|done\|blocked`), không `--until idle`. | Pane `--no-focus` hoặc tab chưa được nhìn trả `done`, không bao giờ `idle` (`herdr --skill`). |
| D12 | `start.sh` resume-safe: pane đã ghi và còn sống thì chỉ chờ, không split lại; label pane đặt ngay sau split, trước `agent start`; `agent start` thất bại → mã 4, pane giữ nguyên. | Retry sau dialog không được tạo pane mồ côi. |
| D13 | Baseline = `HEAD` + `git stash create` (commit object của index+worktree, không đụng cây) + `git status --short -uall` + manifest sha256 file untracked + sha của `.git/config` và hooks. Reviewer diff với stash sha. Controller guard sha cây trước/sau mỗi lượt reviewer; khác → reviewer vi phạm, verdict không tin, kết quả `DONE_WITH_CONCERNS`. | Cây bẩn không chặn nhưng phải phân biệt được sửa của envoy trên file đã bẩn; reviewer không được sửa cây. |
| D14 | `run.json` là ledger: script ghi `round`, `status`, `prompted_at`, `settled_at`; mọi ghi trong lock `mkdir`; timestamp ISO-8601, elapsed bằng `jq fromdateiso8601`. SKILL.md đọc lại ledger sau compaction. | Chờ 60 phút có thể qua compaction; macOS không có `date -d`. |

## Bằng chứng đã xác minh (2026-10-28, live `--help` trên máy tác giả)

| Kind | Binary | Launch args full permission | Probe auth không in secret | Trạng thái |
|------|--------|-----------------------------|----------------------------|-----------|
| claude | `claude` | `--dangerously-skip-permissions` | `claude auth status --json` + jq `.loggedIn == true` (output có email, không in) | verified |
| codex | `codex` codex-cli 0.153.4 | `--dangerously-bypass-approvals-and-sandbox` | `codex login status` (exit code; stdout in key đã che, luôn bỏ) | verified |
| grok | `grok` 0.2.101 | `--permission-mode bypassPermissions` | không có lệnh status (`grok inspect --json` chỉ có loginPolicy) → smoke prompt | verified launch, probe = smoke |
| omp | `omp` 18.3.5 | `--approval-mode yolo` | không có probe an toàn (`omp token` in secret, cấm) → smoke prompt | verified launch, probe = smoke |
| agy | `agy` 1.1.21 | `--dangerously-skip-permissions` | không có lệnh login/status → smoke prompt | verified launch, probe = smoke |
| pi | `pi` | chưa cài trên máy tác giả; tài liệu ak:orchestrate ghi pi headless không có approval; `--no-approve` chỉ là trust project | `pi auth check --provider <provider> --no-refresh --json` (theo `ak-orchestrate/references/pi-sessions.md:41`, cần provider) | unverified, phải xác minh `pi --help` trước khi thêm vào bảng |
| hermes | `hermes` | chưa cài; nguồn web ghi `--yolo` | chưa rõ | unverified |

Herdr (live help và `herdr --skill`): `herdr agent start <NAME> --kind <KIND> --pane <ID> [--timeout MS] -- <args>` chỉ trả thành công khi agent sẵn sàng nhận input; `herdr agent prompt <T> <TEXT> --wait --timeout MS` (cần state change trong 5 s, nếu không trả `agent_prompt_stalled`; không theo dõi từng turn); `herdr agent wait <T> --timeout MS` (mặc định `idle|done|blocked`); `idle` = sẵn sàng và tab đã được nhìn, `done` = cùng trạng thái nhưng tab chưa được nhìn; tên agent unique và bị xóa khi agent thoát; pane id đã đóng không tái dùng; `herdr agent get` có `.result.agent.agent`, `.agent_status`, `.terminal_id` nhưng **không** có tên agent, và trả `agent_not_found` (exit 1) cho cả pane shell lẫn pane đã mất; `herdr pane list` trả `.result.panes[]` với `pane_id`, `terminal_id`, `label`, `agent_status`; `herdr pane split --current|--pane ID --direction right|down --cwd P --no-focus`; `herdr tab create --workspace W --cwd P --label L --no-focus`; `herdr pane process-info --pane ID`. Loại controller hiện tại: `claude`, pane `wC:p8B`. macOS: bash 3.2.57, không có `timeout`(1), không có `date -d`; Bash tool của Claude Code mặc định 120000 ms, tối đa 600000 ms.

## Phases

| # | Phase | Status |
|---|-------|--------|
| 1 | [Nền tảng: bảng kinds, probe, state, install.sh](./phase-01-foundation.md) | Completed |
| 2 | [Lifecycle pane: new-run, start, prompt-wait, run-state, stop, cleanup](./phase-02-session-lifecycle.md) | Completed |
| 3 | [Contract: templates, check-brief, SKILL.md](./phase-03-contracts-and-skill.md) | Completed |
| 4 | [Đóng gói, docs, evals, kiểm thử end-to-end](./phase-04-packaging-and-e2e.md) | Completed |

Thứ tự tuần tự: 2 phụ thuộc 1 (lib, kinds.json), 3 phụ thuộc 2 (giao diện script), 4 phụ thuộc 3.

## Dependencies

- Herdr đang chạy (`HERDR_ENV=1`, `HERDR_PANE_ID`, `HERDR_WORKSPACE_ID`), `herdr`, `jq`, `git`, `bash` ≥ 3.2 (macOS mặc định), `shasum`.
- Để kiểm thử: `codex` đã login (verified hôm nay), `claude` đã login.
- Không sửa `skills/managed-session`, `skills/pr-review-loop`, `skills/head-chief`.

## Success Criteria

Khớp 8 acceptance criteria của `docs/brainstorms/envoy.md`, kiểm ở Phase 4 (bằng chứng: [report E2E](../reports/tester-261028-1723-envoy-peer-e2e.md)):

- [x] AC1: từ Claude Code trong Herdr, gọi không nêu loại → options chỉ gồm loại đã cài, đã verified, khác `claude`.
- [x] AC2: `--kind codex` → dispatch thẳng, không hỏi loại.
- [x] AC3: loại chưa verify → onboarding, ghi state global; project khác không hỏi lại. Chứng minh: codex qua probe; grok và agy qua smoke (lần đầu exit 6, user xử lý pane, gửi lại → exit 0).
- [x] AC4: run dir có `brief.md`, `result.md`, `review-<n>.md`, `run.json`; brief thiếu acceptance criteria thì `check-brief.sh` chặn. Chứng minh: run `fix-greet` (grok) và `staged-findings` (agy) có đủ `result.md`, `review-<n>.md`, `run.json`.
- [x] AC5: loop đến ACCEPT hoặc max rounds; message cuối chỉ gồm status, tóm tắt, số vòng, đường dẫn. Chứng minh: grok ACCEPT ở vòng 1; agy FINDINGS → sửa → ACCEPT ở vòng 2 (kịch bản dàn dựng, ghi rõ trong brief).
- [x] AC6: cả hai pane đóng khi kết thúc kể cả lỗi; `cleanup.sh` dọn run bỏ dở.
- [x] AC7: từ pane codex, `probe.sh list` loại trừ `codex`, chấp nhận `claude`. Chứng minh: từ pane codex, `controller` → `codex` và list loại trừ `codex`; grok tự chạy `probe.sh` trong pane của nó. Riêng codex tự chạy lệnh chưa được: 9Router từ chối codex với `401 Missing API key` vì cấu hình provider của codex không truyền key; user chọn giữ nguyên cấu hình.
- [x] AC8: `install.sh` tạo symlink, chạy lại không lỗi, `--uninstall` gỡ sạch.

## Rủi ro chính

| Rủi ro | Giảm thiểu |
|--------|-----------|
| `herdr agent start --kind codex -- <args>` chưa từng chạy trong repo này (managed-session dùng `pane run`). | Phase 2 bước đầu tiên là smoke live với codex; nếu `agent start` không nhận args, fallback `herdr pane run` + `herdr agent wait`, ghi vào run-contract. |
| Envoy không tuân Output contract (không ghi `result.md`, chép template, trả lời dài). | `prompt-wait.sh` chỉ coi settled khi file mới hơn `prompted_at`, có `Round: n` và dòng kết khớp regex; template có placeholder không parse được; thiếu thì nhắc một lần theo vai trò, sau đó BLOCKED. |
| Pane `blocked` hoặc `agent start` thất bại do dialog trust/login lần đầu của CLI. | Cả hai về mã 4; trong onboarding không đọc pane, chỉ chỉ label; ngoài onboarding đọc bounded 40 dòng qua `redact`; không tự trả lời. |
| Controller chết giữa chừng hoặc bị compaction, pane mồ côi. | `run.json` ghi pane id + terminal_id, round, status; `cleanup.sh --all` chỉ dọn run của controller đã chết hoặc của chính mình; SKILL.md đọc lại ledger sau compaction. |
| Reviewer sửa code hoặc lệnh verification tự sửa file. | Guard sha cây trước/sau mỗi lượt reviewer; khác → vi phạm, `DONE_WITH_CONCERNS`; template review cấm lệnh `--fix`/formatter. |
| Envoy full permission đổi `.git/config`/hooks hoặc để lại tiến trình nền. | Baseline ghi sha của `.git/config` và hooks, so lại khi kết thúc; `stop.sh` ghi `pane process-info` và cảnh báo survivors; brief mặc định yêu cầu dừng tiến trình nền. |

## Câu hỏi còn mở

Không còn. Ba câu hỏi của bản nháp đã được user chốt ở Validation Log bên dưới.

## Validation Log

### Session 1 — 2026-10-28 (4 câu hỏi, user trả lời trực tiếp)

| # | Câu hỏi | Quyết định | Áp dụng |
|---|---------|-----------|---------|
| 1 | Vị trí run dir | `.envoy/runs/<ts>-<slug>-<nonce>/` tại git root, tự ignore bằng `.envoy/.gitignore` | D1, Phase 1–2 (không đổi) |
| 2 | Mặc định vòng review và chờ | `max_rounds = 3`, `timeout_minutes = 60`, `placement = split` (envoy phải controller, reviewer dưới envoy) | Phase 1 `state.sh` prefs, Phase 2 `new-run.sh` (không đổi) |
| 3 | `--model` / `--reviewer-model` ở bản đầu | Có | Phase 2 `new-run.sh`, `start.sh`; Phase 3 argument-hint (không đổi) |
| 4 | `--cleanup --all` chỉ đóng run của session này hoặc controller đã chết, dry-run trước, `--yes` để đóng | Đồng ý | D9, Phase 2 `cleanup.sh`, Phase 3 Step 0 (không đổi) |

Verification pass: dùng kết quả của ba reviewer red-team (tier Standard, 130 claim đã kiểm, 19 failed đều đã sửa trong plan, 15 unverified là hành vi chỉ kiểm được khi start agent thật và đã ghi thành bước smoke ở Phase 2). Không phase nào cần sửa thêm sau validate; sweep nhất quán ở mục Red Team Review vẫn đúng.

Khuyến nghị: proceed. Task hydration bỏ qua vì session này không có công cụ task-management; tiến độ theo checkbox trong phase files.

## Red Team Review

### Session — 2026-10-28
**Findings:** 29 thô từ 3 reviewer (Security Adversary, Assumption Destroyer, Failure Mode Analyst), gộp còn 15 (15 accepted, trong đó 5 accepted có chỉnh; 3 đề xuất con bị bác)
**Severity breakdown:** 2 Critical, 9 High, 4 Medium

| # | Finding | Severity | Disposition | Applied To |
|---|---------|----------|-------------|------------|
| 1 | Kiểm sở hữu pane theo tên agent không thể hiện thực (`agent get` không có tên), pane mồ côi ở chính các nhánh lỗi | Critical | Accept | D9, D12, Phase 2 (start/stop/cleanup) |
| 2 | Chờ `--until idle` bỏ sót `done` của pane không được nhìn; loop treo khi user rời tab | Critical | Accept | D11, Phase 2, Phase 3 |
| 3 | `start.sh` không resume-safe, mã 3 trùng nghĩa, tên agent trùng giữa các run | High | Accept | D6, D12, Phase 2 |
| 4 | Giả định tool timeout 10 phút (mặc định Claude Code 2 phút); gửi trùng prompt khi lệnh bị cắt; `run.json` không có lock | High | Accept | D3, D14, Phase 2, Phase 3 |
| 5 | Smoke auth không chứng minh gì (không kiểm file); `agent start` thất bại không được coi là onboarding; đề xuất TTL cho kind no-probe | High | Accept (modified: không TTL, no-probe smoke mỗi run theo yêu cầu 2) | D7, Phase 3 |
| 6 | Contract lệch: AC3 cần ghi state ở nhánh ready; reviewer kind không được kiểm; `--model` không chuyển; `stop.sh` một mã exit; mã 2 trùng usage | High | Accept | Phase 1, 2, 3, bảng mã exit |
| 7 | Kiểm hoàn thành nhận file cũ/chép template/giả; không đọc lại Status sau round sửa; run dir trùng phút | High | Accept (modified: dùng `Round:` + mtime, không nonce trong prompt, không xoay file) | D1, D5, Phase 2, 3 |
| 8 | Baseline chỉ `git status --short` không thấy sửa trên file đã bẩn, sửa của reviewer, `.git/config`/hooks | High | Accept (modified: `git stash create` + manifest + sha git-meta, không snapshot tree qua index tạm) | D13, Phase 2, 3 |
| 9 | Text của peer (Summary, Findings khi BLOCKED) vào context controller không giới hạn | High | Accept (modified: trích dẫn giới hạn có tiền tố, Conflicts chỉ `none\|present`) | D5, Phase 2 (`run-state.sh extract`), Phase 3 |
| 10 | Đọc 40 dòng pane lúc `blocked` trong onboarding có thể đưa mã thiết bị/key vào transcript | High | Accept | D7, Phase 1 (`redact`), Phase 2 (`--no-read`), Phase 3 |
| 11 | `cleanup.sh --all` giết run của controller khác còn sống; đề xuất registry ngoài cây | High | Accept (modified: kiểm controller còn sống + dry-run/`--yes`; registry ngoài cây bác vì envoy cùng user ghi được mọi nơi, không thêm bảo vệ) | D9, Phase 2 |
| 12 | Reviewer nhận lời nhắc của envoy (mã 7) và ghi đè `result.md` | High | Accept | Phase 3 Step 5 |
| 13 | Probe chạy qua `bash -c` từ JSON; symlink global theo HEAD checkout; `--project` giả định đã ignore | Medium | Accept | D2, Phase 1 |
| 14 | `.envoy/` không tự ignore ở project đích, umask, nonce; tiến trình nền sống sau khi đóng pane | Medium | Accept | D1, Phase 2 (`stop.sh` process-info), Phase 3 (brief Constraints) |
| 15 | Round/status chỉ trong context, mất khi compaction; e2e để lại pane, xóa `.envoy` trước cleanup, cwd reset, chạm state thật; sai số dòng `session.sh`, pi probe thiếu `--provider`, README còn "three skills"/"both", `date -d`, mảng rỗng bash 3.2 | Medium | Accept | D14, Phase 1, 2, 4 |

Bác bỏ (với lý do): registry run ngoài cây (xem #11); nonce trong prompt và xoay `result.md` mỗi round (`Round:` + mtime đủ, KISS); TTL bỏ smoke cho kind no-probe (trái yêu cầu 2 "mỗi run vẫn probe nhanh").

### Whole-Plan Consistency Sweep
- Files reread: plan.md, phase-01-foundation.md, phase-02-session-lifecycle.md, phase-03-contracts-and-skill.md, phase-04-packaging-and-e2e.md
- Decision deltas checked: 14 (D1 nonce/self-ignore, D2 argv, D3 timeout/mã 8, D5 validate/extract, D6 tên theo nonce, D7 no-read/smoke file, D8 thêm run-state, D9 terminal_id/controller-alive, D11 idle|done, D12 resume, D13 baseline stash/guard, D14 ledger/lock, bảng mã exit 0–11, tên agent `env-`/`rev-`)
- Reconciled stale references: 9 (tên agent `envoy-<kind>-<slug>` → `env-<kind>-<nonce>` trong plan/phase-02; `--until idle` trong phase-02/03; kiểm theo tên trong stop.sh; lời nhắc mã 7 chung → theo vai trò; `.gitignore` project đích → `.envoy/.gitignore`; số dòng `session.sh`; pi probe; README stale refs; AC3 ghi state ở nhánh ready)
- Unresolved contradictions: 0

<!-- slug: envoy-peer-skill -->
