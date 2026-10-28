---
phase: 2
title: "Lifecycle pane: new-run, start, prompt-wait, run-state, stop, cleanup"
status: completed
priority: P1
effort: "5h"
dependencies: [1]
---

# Phase 2: Lifecycle pane Herdr

## Goal

Script mở pane, start agent theo kind, gửi prompt một dòng, chờ bounded, ghi trạng thái run, đóng pane và dọn run bỏ dở, với `run.json` làm nguồn sự thật của run (sống qua compaction). Xác minh live bằng một envoy codex thật, kể cả các nhánh lỗi.

## Context

- Yêu cầu 6, 7, 8 trong `docs/brainstorms/envoy.md`; quyết định D3, D4, D6, D9, D11–D14 trong `plan.md`.
- Pattern: `skills/managed-session/scripts/create-session.sh:86-96` (split/tab + jq lấy pane id), `skills/pr-review-loop/scripts/session.sh:60` và `:74` (`herdr agent wait --until idle --timeout`, lưu ý: cách dùng `--until idle` này **không** tái dùng, xem Semantics), `:81` (`agent prompt --wait --timeout 600000`), `:96-106` (stop: `/exit` rồi `pane close`).
- Semantics Herdr (từ `herdr --skill`, xác minh 2026-10-28): `idle` = sẵn sàng **và** tab đã được nhìn thấy trong UI; `done` = cùng trạng thái idle nhưng tab chưa được nhìn thấy; `blocked` = Herdr nhận ra UI approval/câu hỏi. `agent prompt --wait` và `agent wait` mặc định khớp `idle|done|blocked`, tài liệu dặn không lặp lại mặc định bằng `--until`. Tên agent phải unique trong các agent đang sống và bị xóa khi agent thoát. Pane id đã đóng không bao giờ tái dùng. `herdr agent get <pane>` trả `agent_not_found` (exit 1) cho cả pane shell còn mở lẫn pane đã mất; `herdr pane list` trả `.result.panes[]` với `pane_id`, `terminal_id`, `label`, `agent_status`.
- Giới hạn tool Bash của host Claude Code: mặc định 120000 ms, tối đa 600000 ms khi caller đặt rõ (`timeout`), hoặc `run_in_background`.

## Files to Create / Modify

- Create: `skills/envoy-peer/references/run-contract.md` (layout run dir, schema `run.json`, mã exit, semantics Herdr ở trên)
- Create: `skills/envoy-peer/scripts/new-run.sh`
- Create: `skills/envoy-peer/scripts/start.sh`
- Create: `skills/envoy-peer/scripts/prompt-wait.sh`
- Create: `skills/envoy-peer/scripts/run-state.sh`
- Create: `skills/envoy-peer/scripts/stop.sh`
- Create: `skills/envoy-peer/scripts/cleanup.sh`

## Tasks & Steps

1. **`run-contract.md`** viết trước, là hợp đồng cho mọi script và cho SKILL.md.

   ```text
   .envoy/
     .gitignore            # nội dung "*": thư mục tự ignore, không cần sửa .gitignore của project đích
     runs/<YYMMDD-HHMM>-<slug>-<nonce>/
       run.json  brief.md  result.md  review-1.md … review-n.md
       baseline-status.txt  baseline-untracked.sha  smoke.txt (chỉ khi onboarding)
   ```

   `run.json` (mọi timestamp ISO-8601 UTC; elapsed tính bằng `jq 'now - (.x|fromdateiso8601)'`, không dùng `date -d`):

   ```json
   {
     "version": 1,
     "run_id": "261028-1500-add-install-a1b2c3",
     "nonce": "a1b2c3",
     "run_dir": "/abs/.envoy/runs/261028-1500-add-install-a1b2c3",
     "cwd": "/abs/repo",
     "created_at": "2026-10-28T08:00:00Z",
     "controller": {"pane": "wC:p8B", "kind": "claude"},
     "envoy":    {"kind": "codex",  "name": "env-codex-a1b2c3",  "label": "envoy codex add-install",    "model": null,
                  "pane": null, "tab": null, "terminal_id": null, "command": null,
                  "started_at": null, "prompted_at": null, "settled_at": null, "last_status": null, "closed_at": null},
     "reviewer": {"kind": "claude", "name": "rev-claude-a1b2c3", "label": "reviewer claude add-install", "model": null,
                  "pane": null, "tab": null, "terminal_id": null, "command": null,
                  "started_at": null, "prompted_at": null, "settled_at": null, "last_status": null, "closed_at": null},
     "baseline": {"head": null, "stash_sha": null, "dirty": null, "status_file": "baseline-status.txt",
                  "untracked_manifest": "baseline-untracked.sha", "git_meta_sha": null},
     "guard": {},
     "round": 0, "max_rounds": 3, "timeout_minutes": 60, "placement": "split",
     "dispatched_at": null,
     "status": "created", "final_status": null,
     "updated_at": "..."
   }
   ```

   `status` ∈ `created | dispatched | reviewing | fixing | accepted | concerns | blocked | timeout | cleaned`. Script nào ghi gì: `new-run.sh` → `created`; `start.sh` → `dispatched` (envoy) / `reviewing` (reviewer); `prompt-wait.sh` → `last_status`, `prompted_at`, `settled_at`, `dispatched_at` (lần prompt đầu của envoy), `timeout`, `blocked`; `run-state.sh set` → `round`, `fixing`, `accepted`, `concerns`, `blocked`; `cleanup.sh` → `final_status` + `cleaned`. Mọi ghi `run.json` qua `json_write_atomic` **bên trong lock** `run.json.lock` (`mkdir` lock, bash 3.2, chờ tối đa 5 s).

   Mã exit chung của mọi script:

   | Mã | Nghĩa |
   |----|-------|
   | 0 | ok / settled |
   | 1 | lỗi môi trường, Herdr, kind không có trong bảng |
   | 2 | sai cú pháp gọi |
   | 3 | còn chạy, gọi lại (`prompt-wait.sh`) |
   | 4 | cần user: pane `blocked`, hoặc `agent start` thất bại (dialog trust/login/onboarding), pane giữ nguyên |
   | 5 | hết timeout tổng của run |
   | 6 | `agent_prompt_stalled` và agent không `working` |
   | 7 | settled nhưng file mong đợi thiếu, cũ hơn `prompted_at`, thiếu `Round:` hoặc không có dòng kết hợp lệ |
   | 8 | từ chối gửi `--text`: role đã có `prompted_at` chưa `settled_at` và agent đang `working` |
   | 9 | từ chối đóng: pane không thuộc run (terminal_id không khớp) |
   | 10 | pane/agent đã mất (`agent_not_found` khi chờ, hoặc pane không còn trong `pane list`) |
   | 11 | `start.sh`: pane mở được nhưng agent không sẵn sàng trong thời hạn |

   `probe.sh auth` không dùng bảng này: in `ready|not-ready|no-probe`, exit 0 khi probe đã quyết, exit 1 khi kind không có trong bảng.

2. **`new-run.sh <slug> [--kind K] [--reviewer K] [--max-rounds N] [--timeout-min N] [--placement split|tab] [--model M] [--reviewer-model M] [--cwd DIR]`**:
   - slug chuẩn hóa `[a-z0-9-]`, cắt 24 ký tự; nonce 6 ký tự hex từ `/dev/urandom`; `umask 077`; `mkdir "$root/runs/$id"` **không** `-p` cho lá, thất bại nếu đã tồn tại; tạo `$root/.gitignore` nội dung `*` nếu chưa có.
   - Controller pane/kind từ `probe.sh controller`; từ chối (exit 1) nếu kind envoy = kind controller, kind envoy không `selectable` theo `probe.sh list`, hoặc kind reviewer không có `launch_args` trong `kinds.json` (reviewer mặc định = kind controller nhưng vẫn phải có dòng trong bảng).
   - Tên agent `env-<kind>-<nonce>` / `rev-<kind>-<nonce>` (≤ 32 ký tự với mọi kind Herdr hiện có; kiểm regex), label pane `envoy <kind> <slug>` / `reviewer <kind> <slug>`.
   - Prefs mặc định từ `state.sh pref get`, flag override; `--cwd` mặc định `$PWD` (Bash tool của host có thể reset cwd giữa các lần gọi, nên SKILL.md truyền `--cwd` rõ khi làm việc ngoài thư mục session).
   - In đường dẫn run dir.

3. **`start.sh --run DIR --role envoy|reviewer`**:
   1. `require_herdr`; đọc kind, name, label, model, placement, cwd từ `run.json`.
   2. **Resume**: nếu `<role>.pane` đã có và pane còn trong `herdr pane list` với `terminal_id` khớp → không split; nhảy tới bước 5 (chờ sẵn sàng). Nếu pane đã mất → ghi `closed_at`, tiếp tục mở pane mới.
   3. Role envoy, chỉ lần đầu: baseline trước khi mở pane: `git rev-parse HEAD` → `baseline.head`; `git stash create` → `baseline.stash_sha` (rỗng khi cây sạch → dùng head; lệnh này tạo commit object mà không đụng cây hay index); `git status --short -uall` → `baseline-status.txt`; `git ls-files -o --exclude-standard -z | xargs -0 shasum -a 256` → `baseline-untracked.sha`; `baseline.git_meta_sha` = `shasum -a 256` gộp của `.git/config` và `.git/hooks/*` không phải `*.sample`. Ngoài git repo: mọi giá trị `null` và ghi chú.
   4. Mở pane: envoy + split → `herdr pane split --current --direction right --cwd "$cwd" --no-focus`; reviewer + split → `herdr pane split --pane <envoy pane> --direction down --cwd "$cwd" --no-focus` (pane envoy không còn, hoặc Herdr từ chối split pane khác current → `--current --direction down`); tab → `herdr tab create --workspace "$HERDR_WORKSPACE_ID" --cwd "$cwd" --label "$label" --no-focus`, pane = `.result.root_pane.pane_id`. Ghi `pane`, `tab`, `terminal_id` (từ `herdr pane list` cho pane vừa tạo) vào `run.json` **ngay**, rồi `herdr pane rename "$pane" "$label"` **trước** khi start agent.
   5. Kiểm tên còn trống: `herdr agent get "$name"` phải trả `agent_not_found`; nếu tên đang sống ở pane khác → exit 1 kèm thông báo (chỉ xảy ra khi nonce trùng, gần như không).
   6. `herdr agent start "$name" --kind "$kind" --pane "$pane" --timeout 60000 -- <launch args> [<model_flag> M]` (mảng args, idiom `${a[@]+"${a[@]}"}` cho bash 3.2 với `set -u`). Lưu lệnh vào `<role>.command`. **Thất bại** (exit ≠ 0, thường do dialog trust/login khiến agent không "ready") → `last_status: start-failed`, exit 4, pane giữ nguyên, in đúng hai dòng: trạng thái `herdr agent get <pane>` (`agent_status` hoặc `agent_not_found`) và `check pane <pane> (label: <label>)`. **Không đọc nội dung pane** ở bước này (có thể đang là màn hình login).
   7. `herdr agent wait "$pane" --timeout 90000` (mặc định `idle|done|blocked`). `blocked` → exit 4 cùng hai dòng như trên. Timeout → exit 11, pane giữ nguyên (gọi lại `start.sh` sẽ resume theo bước 2).
   8. Cập nhật `started_at`, `status` (`dispatched` / `reviewing`); in pane id.

4. **`prompt-wait.sh --run DIR --role R [--text "one line"] [--round N] [--expect FILE --match REGEX] [--wait-ms N] [--no-read]`**:
   - `wait_ms` mặc định 540000, kẹp ≤ 570000. SKILL.md bắt buộc caller đặt timeout tool ≥ `wait_ms + 30000` (Claude Code: `timeout: 600000`) hoặc chạy nền; script in cảnh báo này ở `--help`.
   - Trước khi gửi `--text`: `herdr agent get "$pane"`; `agent_not_found` → exit 10. Nếu role có `prompted_at` mà chưa `settled_at` và agent `working` → exit 8 (không gửi lại). Nếu agent `working` mà không do ta prompt → `herdr agent wait` trước rồi mới gửi. Ghi `prompted_at` (và `dispatched_at` nếu là lần đầu của envoy), `round` nếu có `--round`, xóa `settled_at`, rồi `herdr agent prompt "$pane" "$text" --wait --timeout "$wait_ms"`. Không có `--text`: `herdr agent wait "$pane" --timeout "$wait_ms"`.
   - Settled = Herdr trả `idle` **hoặc** `done` (hai trạng thái tương đương, xem Context). Khi settled: ghi `settled_at`; nếu có `--expect`: file phải tồn tại, `stat -f %m` > `prompted_at` (so epoch), chứa `^Round: N$` khi có `--round`, và có đúng một dòng khớp `--match` → in dòng khớp đó ra stdout (chỉ dòng đã validate bằng regex, không in gì khác của file), exit 0; sai bất kỳ điều kiện → exit 7 kèm lý do một dòng (`missing|stale|no-round|no-match`).
   - `blocked` → `last_status: blocked`, exit 4. Mặc định in 40 dòng cuối `herdr agent read --source recent-unwrapped --lines 40` qua `redact` ra stderr; với `--no-read` (SKILL.md dùng trong onboarding) chỉ in `agent_status` và pane id.
   - Hết `wait_ms` chưa settled → nếu `now - dispatched_at > timeout_minutes*60` → `status: timeout`, exit 5; ngược lại exit 3.
   - `agent_prompt_stalled` → `herdr agent get`: `working` → coi như đã gửi, tiếp tục chờ bằng `agent wait`; `idle|done` → exit 6 (20 dòng cuối qua `redact`, trừ khi `--no-read`).
   - Trong lúc chờ, Herdr trả `agent_not_found` → exit 10.

5. **`run-state.sh --run DIR <sub>`**:
   - `get <key>` (jq path), `set <key> <value>` (`round`, `status`, `final_status`; trong lock).
   - `guard begin <n>` → ghi `guard.<n>.before` = `{status_sha: sha256(git status --porcelain -uall), diff_sha: sha256(git diff HEAD), untracked_sha: sha256(manifest untracked)}`; `guard end <n>` → tính lại, ghi `guard.<n>.after` và `guard.<n>.clean: true|false`; in `clean|changed` và, khi `changed`, danh sách file khác (`git status --porcelain -uall` diff với bản trước, tối đa 20 dòng).
   - `git-meta` → so `baseline.git_meta_sha` với hiện tại, in `same|changed`.
   - `extract <section> <file> [--max-lines 8]` → in nội dung một mục H2 (`Summary`, `Unresolved`) giới hạn dòng/ký tự (mặc định 8 dòng, 600 ký tự), mỗi dòng có tiền tố `> ` để controller nhìn thấy đây là trích dẫn; `conflicts <review file>` → in `none` khi mục `## Conflicts with brief or user decisions` chỉ có `None`, ngược lại `present` (không in nội dung).

6. **`stop.sh --run DIR --role R`**: pane và `terminal_id` từ `run.json`; `closed_at` đã có hoặc pane rỗng → no-op exit 0. Tra `herdr pane list`: pane không còn → ghi `closed_at`, exit 10. Có nhưng `terminal_id` khác → exit 9, không đóng. Khớp → ghi `herdr pane process-info --pane "$pane"` (tiến trình con, nếu lệnh trả được) vào `<role>.processes_at_stop`, `herdr pane close "$pane"`, ghi `closed_at`, exit 0. Không gửi `/exit` (khác nhau theo kind; `pane close` kết thúc tiến trình). Sau khi đóng, nếu `processes_at_stop` liệt kê tiến trình có cwd bằng `cwd` của run mà vẫn sống (`ps -o pid=,command= -p <pids>`), in cảnh báo "survivors" (không tự kill).

7. **`cleanup.sh --run DIR | --all [--root DIR] [--yes]`**: với `--run`: `stop.sh` envoy rồi reviewer, chấp nhận exit 0/10, dừng ở 9 với thông báo; `final_status` = `status` cũ (trừ khi đã có), `status: cleaned`. `--all`: quét `$root/runs/*/run.json` có `status != cleaned`; chỉ chọn run mà `controller.pane == $HERDR_PANE_ID` **hoặc** `controller.pane` không còn trong `herdr pane list` (controller đã chết); run có controller khác còn sống → liệt kê `skipped (controller alive: <pane>)`. Không `--yes` → chỉ in danh sách sẽ đóng (dry-run); `--yes` → đóng. In tổng kết: số run, pane đóng, pane đã mất, run bỏ qua.

8. **Smoke live** (chạy trong pane Claude Code này, kind envoy `codex`; mọi lệnh chờ gọi với timeout tool 600000):
   1. `R=$(new-run.sh smoke --kind codex --max-rounds 1)`; ghi `$R/brief.md` một đoạn: "Create the file `$R/result.md` containing exactly three lines: `# Result`, `Round: 1`, `Status: DONE`. Reply only with that file's path." (dùng Write tool, không heredoc).
   2. `start.sh --run $R --role envoy` → pane mới bên phải, không cướp focus, label `envoy codex smoke`; `herdr agent get <pane>` trả `agent: codex`; `herdr agent get env-codex-<nonce>` trả cùng pane.
   3. `prompt-wait.sh --run $R --role envoy --round 1 --expect $R/result.md --match '^Status: (DONE|DONE_WITH_CONCERNS|BLOCKED)$' --text "Read $R/brief.md and do exactly what it says. Reply only with the path of the file you wrote."` → stdout `Status: DONE`, exit 0.
   4. Nhánh lỗi: gửi lại cùng `--text` khi agent đang `working` (prompt một việc dài hơn, ví dụ "count to 200 slowly in a file") → exit 8; `--wait-ms 5000` → exit 3 rồi gọi lại không text → 0; `run-state.sh set timeout_minutes 0` tạm → `--wait-ms 5000` → exit 5 (trả lại 60 sau test); `--expect` tới file cũ không đổi → exit 7 `stale`.
   5. `start.sh --run $R --role reviewer` (kind claude) → pane dưới envoy; `stop.sh` từng role → `closed_at`, `herdr pane list` không còn hai pane đó.
   6. Resume: run mới, `start.sh` envoy, gọi `start.sh` lần hai → không mở pane mới (pane id giữ nguyên).
   7. Orphan: run thứ ba, start envoy, không stop; `cleanup.sh --all` → liệt kê (dry-run); `cleanup.sh --all --yes` → pane đóng, `status: cleaned`, `final_status: dispatched`.
   8. Nếu `herdr agent start … -- <args>` không chuyển được args cho codex: fallback `herdr pane run "$pane" "<binary> <args>"` + `herdr agent wait`, ghi quyết định vào `run-contract.md` và `kinds.json.notes`.
   9. Xóa `.envoy/` của repo này sau khi test; `herdr pane list` về đúng tập pane trước test.

## Verification

```bash
cd /Users/onedayin20902/personal/head-chief; S=skills/envoy-peer/scripts
for f in $S/*.sh; do bash -n "$f"; done
herdr pane list | jq -r '.result.panes[].pane_id' | sort > /tmp/panes-before.txt
R=$($S/new-run.sh smoke --kind codex --max-rounds 1); jq -e '.status=="created" and .envoy.kind=="codex" and (.nonce|length)==6' "$R/run.json"
test "$(cat "$(dirname "$R")/../.gitignore")" = "*"
$S/new-run.sh bad --kind claude; echo "exit=$?"            # 1: cùng loại controller
$S/start.sh --run "$R" --role envoy; P=$(jq -r '.envoy.pane' "$R/run.json")
herdr agent get "$P" | jq -r '.result.agent.agent'          # codex
herdr pane list | jq -r --arg p "$P" '.result.panes[]|select(.pane_id==$p)|.label'   # envoy codex smoke
$S/start.sh --run "$R" --role envoy; test "$(jq -r '.envoy.pane' "$R/run.json")" = "$P"   # resume, không split
$S/prompt-wait.sh --run "$R" --role envoy --round 1 --expect "$R/result.md" --match '^Status: (DONE|DONE_WITH_CONCERNS|BLOCKED)$' --text "Read $R/brief.md and do exactly what it says. Reply only with the path of the file you wrote."; echo "exit=$?"   # Status: DONE, exit=0
$S/prompt-wait.sh --run "$R" --role envoy --round 1 --expect "$R/result.md" --match '^Status: ' ; echo "exit=$?"   # 7 stale (không prompt mới)
$S/run-state.sh --run "$R" guard begin 1; $S/run-state.sh --run "$R" guard end 1    # clean
$S/start.sh --run "$R" --role reviewer; $S/stop.sh --run "$R" --role reviewer; $S/stop.sh --run "$R" --role envoy
jq -e '.envoy.closed_at != null and .reviewer.closed_at != null' "$R/run.json"
R2=$($S/new-run.sh orphan --kind codex); $S/start.sh --run "$R2" --role envoy
$S/cleanup.sh --all; $S/cleanup.sh --all --yes; jq -r '.status, .final_status' "$R2/run.json"   # cleaned, dispatched
rm -rf .envoy
herdr pane list | jq -r '.result.panes[].pane_id' | sort | diff - /tmp/panes-before.txt && echo "no leftover panes"
```

## Todo

- [x] `references/run-contract.md` (layout, schema, bảng mã exit, semantics Herdr idle/done)
- [x] `scripts/new-run.sh` (nonce, umask, mkdir không -p, `.envoy/.gitignore`, kiểm reviewer kind)
- [x] `scripts/start.sh` (resume, baseline stash/untracked/git-meta, label trước start, start-failed → 4, wait mặc định, 11 khi timeout)
- [x] `scripts/prompt-wait.sh` (8 khi gửi trùng, settled = idle|done, expect/match/round, redact, `--no-read`, 3/4/5/6/7/10)
- [x] `scripts/run-state.sh` (get/set/guard/git-meta/extract/conflicts)
- [x] `scripts/stop.sh` (terminal_id, process-info, survivors)
- [x] `scripts/cleanup.sh` (`--run`, `--all` dry-run/`--yes`, controller-alive)
- [x] Smoke live codex xanh kể cả nhánh 3/5/7/8, resume, orphan; hình dạng JSON `agent prompt --wait` ghi vào comment script
- [x] `.envoy/` của repo này xóa sau test; pane list trước/sau khớp

Smoke notes (2026-10-28): the codex provider configured on this machine was unreachable, and grok, omp and agy were not logged in, so the settled success path (`Verdict: ACCEPT`, exit 0, guard `clean`, conflicts `present`) was proven through the claude reviewer role. Exits 3, 5, 6, 7, 8, 9 and 10, resume, and `cleanup.sh --all` (dry run, foreign controller skipped, dead controller cleaned) were proven live. Exits 4 and 11 could not be triggered: no installed kind entered Herdr's `blocked` state (grok's and agy's sign-in screens report `idle`, which surfaces as exit 6 on the first prompt).

## Success Criteria

- Pane envoy và reviewer mở với `--no-focus`, controller giữ focus; mọi wait chấp nhận `done` như `idle` (kiểm bằng cách không focus tab envoy trong suốt smoke).
- Không lệnh chờ nào vượt 9 phút 30 giây; `prompt-wait.sh` trả 3 khi còn chạy, 8 khi gửi trùng.
- `stop.sh`/`cleanup.sh` đóng đúng pane của run (so `terminal_id`) và không đụng pane khác; `cleanup.sh --all` bỏ qua run của controller khác còn sống.
- Không script nào in nội dung pane khi `--no-read`; mọi read khác đi qua `redact`.

## Risk

- `herdr agent prompt --wait` có thể khớp turn đang chạy thay vì turn mới ("does not track turns"); vì vậy chỉ gửi khi agent `idle|done`, và exit 8 chặn gửi trùng.
- `herdr agent start` có thể thất bại thay vì trả `blocked` khi CLI hiện dialog trust/login lần đầu; cả hai đường đều về exit 4 và SKILL.md xử lý như nhau.
- `herdr pane split --pane <envoy pane>` cho reviewer: nếu Herdr từ chối, fallback `--current --direction down`.
- `git stash create` không gồm file untracked; manifest untracked bù phần đó.
