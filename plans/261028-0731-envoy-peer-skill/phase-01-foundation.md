---
phase: 1
title: "Nền tảng: bảng kinds, probe, state, install.sh"
status: completed
priority: P1
effort: "3h"
dependencies: []
---

# Phase 1: Nền tảng

## Goal

Dựng khung `skills/envoy-peer/`, bảng kinds duy nhất, script phát hiện loại controller, liệt kê loại khả dụng, probe auth không in secret, state global, thư viện dùng chung (lock, redact, JSON atomic) và `install.sh` symlink ở root.

## Context

- Yêu cầu 1, 2, 9, 10 trong `docs/brainstorms/envoy.md`.
- Bằng chứng kinds đã xác minh: bảng trong `plan.md`.
- Pattern kiểm tra môi trường: `skills/managed-session/scripts/create-session.sh:7-10` (HERDR_ENV), `skills/pr-review-loop/scripts/session.sh:17-26` (tìm thư mục skill theo thứ tự env, project, `~/.claude/skills`, `~/.agents/skills`).
- macOS: bash 3.2.57 (không `declare -A`, không `mapfile`, mảng rỗng với `set -u` cần idiom `${a[@]+"${a[@]}"}`), không có `timeout`(1), không có `date -d`; `jq` 1.x có `fromdateiso8601`.

## Files to Create / Modify

- Create: `skills/envoy-peer/references/kinds.json`
- Create: `skills/envoy-peer/scripts/lib.sh`
- Create: `skills/envoy-peer/scripts/probe.sh`
- Create: `skills/envoy-peer/scripts/state.sh`
- Create: `install.sh` (root)
- Modify: `.gitignore` (thêm `.envoy/`, cùng precedent `.orchestrator/` ở `.gitignore:9`)

## Tasks & Steps

1. **`references/kinds.json`** (một bảng duy nhất, D2). Probe là **mảng argv**, chạy trực tiếp không qua shell; readiness = exit 0, hoặc jq filter `ready_jq` áp lên stdout khi có. Schema:

   ```json
   {
     "version": 1,
     "kinds": {
       "codex": {
         "binary": "codex",
         "launch_args": ["--dangerously-bypass-approvals-and-sandbox"],
         "model_flag": "--model",
         "auth_probe": ["codex", "login", "status"],
         "ready_jq": null,
         "version_cmd": ["codex", "--version"],
         "verified": {"date": "2026-10-28", "cli_version": "codex-cli 0.153.4", "method": "live --help"},
         "notes": "login status prints a masked key on stdout; probe output is always discarded"
       },
       "claude": {
         "binary": "claude",
         "launch_args": ["--dangerously-skip-permissions"],
         "model_flag": "--model",
         "auth_probe": ["claude", "auth", "status", "--json"],
         "ready_jq": ".loggedIn == true",
         "version_cmd": ["claude", "--version"],
         "verified": {"date": "2026-10-28", "cli_version": "<ghi từ claude --version>", "method": "live --help"},
         "notes": "status JSON contains the account email; never print it"
       }
     }
   }
   ```

   Điền đủ `grok` (`["--permission-mode","bypassPermissions"]`, `-m/--model`, `auth_probe: null`, 0.2.101), `omp` (`["--approval-mode","yolo"]`, `--model`, `auth_probe: null`, 18.3.5), `agy` (`["--dangerously-skip-permissions"]`, `--model`, `auth_probe: null`, 1.1.21). `auth_probe: null` nghĩa là không có probe an toàn → smoke prompt (D7). Thêm `pi` và `hermes` với `"verified": null` và `notes`: pi `auth_probe` ứng viên `["pi","auth","check","--provider","<provider>","--no-refresh","--json"]` cần `--provider` (theo `ak-orchestrate/references/pi-sessions.md:41`) nên phải chốt provider mặc định khi xác minh; hermes ứng viên `--yolo` (nguồn web, chưa xác minh). Kiểm `jq . references/kinds.json` hợp lệ.

2. **`scripts/lib.sh`** (source bởi mọi script): `die`, `usage` (exit 2), `require_herdr` (HERDR_ENV=1, `herdr`, `jq`, `git` trên PATH), `skill_dir` (resolve theo `${BASH_SOURCE[0]}` qua symlink: `cd "$(dirname "$(readlink "$0" || echo "$0")")/.." && pwd -P`, kiểm bằng cách chạy qua link ở Verification), `kinds_file`, `kind_row <kind>` (jq, exit 1 nếu không có), `kind_launch_args` (một arg một dòng), `kind_verified`, `herdr_kinds` (parse `herdr agent start --help`: `sed -n 's/.*\[possible values: \(.*\)\]/\1/p' | tr -d ',' | tr ' ' '\n'`; rỗng → `die "could not parse herdr kinds"`), `controller_kind` (`herdr agent get "$HERDR_PANE_ID" | jq -r '.result.agent.agent'`), `envoy_root` (`git -C "$dir" rev-parse --show-toplevel 2>/dev/null || echo "$dir"` + `/.envoy`), `state_file` (`${XDG_CONFIG_HOME:-$HOME/.config}/envoy-peer/state.json`), `json_write_atomic <file>` (ghi tmp cùng thư mục rồi `mv`, `chmod 600`), `with_lock <dir> <cmd…>` (`mkdir "$dir"` lặp tối đa 50 lần cách 100 ms; `trap` xóa lock), `now_iso` (`date -u +%Y-%m-%dT%H:%M:%SZ`), `iso_to_epoch` (`jq -rn --arg t "$1" '$t|fromdateiso8601'`), `redact` (sed: `sk-[A-Za-z0-9_-]{8,}`, `xai-[A-Za-z0-9_-]{8,}`, `eyJ[A-Za-z0-9_-]{10,}`, `(code|token|key|secret|password)=[^[:space:]]+`, `[A-Z0-9]{4}-[A-Z0-9]{4}` (device code), chuỗi hex/base64 ≥ 32 ký tự → `[redacted]`), `pane_row <pane>` (`herdr pane list | jq` lấy đúng pane, rỗng nếu không còn).

3. **`scripts/probe.sh`** với subcommand:
   - `controller` → in kind của pane hiện tại; exit 1 nếu `unknown`/rỗng.
   - `list [--json]` → giao của `herdr_kinds`, binary có trên PATH, loại ≠ controller. Mỗi phần tử: `kind`, `binary_path`, `verified` (true nếu kinds.json có `verified` khác null), `auth_verified_at` (từ state, hoặc null), `selectable` (= verified), `reason` khi không selectable. Loại có binary nhưng chưa verified vẫn liệt kê với `selectable:false`, để SKILL.md báo user.
   - `auth <kind>` → chạy mảng `auth_probe` (`"${probe[@]}"`), stdout vào biến chỉ khi có `ready_jq`, stderr về `/dev/null`; in `ready|not-ready|no-probe` và exit 0; kind không có trong bảng → exit 1. Không bao giờ in output của probe.
   - `args <kind>` → in launch args, mỗi arg một dòng (cho `start.sh`).
   - `version <kind>` → in dòng đầu của `version_cmd`.
   Mọi lỗi "kind không có trong bảng" in đúng một câu hướng dẫn: xác minh `<binary> --help` rồi thêm dòng vào `references/kinds.json`.

4. **`scripts/state.sh`**: `show`, `get <kind>` (in `verified_at`, exit 1 nếu chưa), `set-verified <kind> [--version V] [--probe auth|smoke]`, `pref get <key>`, `pref set <key> <value>`, `clear <kind>`. File khởi tạo `{"version":1,"kinds":{},"prefs":{"default_kind":null,"reviewer_kind":null,"max_rounds":3,"timeout_minutes":60,"placement":"split","model":{}}}`. Ghi atomic trong lock, `chmod 600`, không bao giờ chứa token. Tôn trọng `XDG_CONFIG_HOME` (test dùng thư mục scratch).

5. **`install.sh`** ở root:

   ```text
   install.sh [--skill NAME ...] [--target DIR | --project | --agents] [--uninstall] [--force] [--dry-run]
   ```

   Mặc định skill `envoy-peer`, target `~/.claude/skills`; `--agents` → `~/.agents/skills`; `--project` → `$(git rev-parse --show-toplevel)/.claude/skills`, và **kiểm `git check-ignore -q <link path>`**: không được ignore → từ chối với lời nhắc thêm `.claude/skills/` vào `.gitignore`, trừ khi `--force`. Tạo thư mục target nếu thiếu. Symlink `<target>/<name>` → đường dẫn tuyệt đối `skills/<name>` của repo này (`pwd -P`). Idempotent: link đã trỏ đúng → "already linked", exit 0; tồn tại thư mục thật hoặc link khác → báo và exit 1 trừ khi `--force` (chỉ thay link, không xóa thư mục thật). `--uninstall` chỉ xóa symlink trỏ vào repo này. In từng hành động một dòng. Ghi trong `--help` và README: symlink chạy theo HEAD hiện tại của checkout này (đổi branch là đổi skill cho mọi project).

6. **`.gitignore`**: thêm `.envoy/` kèm comment "runtime run dirs of envoy-peer" (run dir còn tự ignore bằng `.envoy/.gitignore`, Phase 2).

7. `chmod +x` mọi script; `bash -n` từng file; chạy `shellcheck` (có trên PATH) và sửa cảnh báo thật.

## Verification

```bash
cd /Users/onedayin20902/personal/head-chief
export XDG_CONFIG_HOME=$(mktemp -d)        # không chạm state thật của user trong test
jq -e '.kinds.codex.verified.date and (.kinds.codex.auth_probe|type=="array")' skills/envoy-peer/references/kinds.json
for f in skills/envoy-peer/scripts/*.sh install.sh; do bash -n "$f"; done; shellcheck skills/envoy-peer/scripts/*.sh install.sh
S=skills/envoy-peer/scripts
$S/probe.sh controller                       # claude
$S/probe.sh list --json | jq -r '.[].kind'   # có codex grok omp agy; không có claude
$S/probe.sh list --json | jq -e 'map(select(.kind=="claude")) | length == 0'
$S/probe.sh auth codex; echo "exit=$?"       # ready, exit=0 (đã login hôm nay); không in gì khác
$S/probe.sh auth claude                      # ready
$S/probe.sh auth grok                        # no-probe
$S/probe.sh args codex                       # --dangerously-bypass-approvals-and-sandbox
$S/probe.sh args nope; echo "exit=$?"        # câu hướng dẫn, exit=1
$S/state.sh set-verified codex --probe auth && $S/state.sh get codex && $S/state.sh clear codex
stat -f '%Lp' "$XDG_CONFIG_HOME/envoy-peer/state.json"   # 600
printf 'sk-abcdefghijklmnop token=zzz AB12-CD34\n' | bash -c 'source skills/envoy-peer/scripts/lib.sh; redact'   # toàn [redacted]
T=$(mktemp -d); ./install.sh --target "$T"; ./install.sh --target "$T"; readlink "$T/envoy-peer"; ./install.sh --target "$T" --uninstall; test ! -e "$T/envoy-peer"
./install.sh --target "$T" && "$T/envoy-peer/scripts/probe.sh" args codex && ./install.sh --target "$T" --uninstall   # chạy qua symlink
./install.sh --project; test -L .claude/skills/envoy-peer; ./install.sh --project --uninstall
git check-ignore -q .envoy/runs/x && echo ignored
# Kiểm --project từ chối khi không ignore: trong repo tạm không có .gitignore
U=$(mktemp -d); git -C "$U" init -q; (cd "$U" && /Users/onedayin20902/personal/head-chief/install.sh --project; echo "exit=$?")   # 1, nhắc gitignore
unset XDG_CONFIG_HOME
```

## Todo

- [x] `references/kinds.json` đủ 5 kind verified (probe dạng argv, `ready_jq`) + 2 kind unverified có notes (pi cần `--provider`)
- [x] `scripts/lib.sh` (lock, redact, iso_to_epoch, pane_row, skill_dir qua symlink)
- [x] `scripts/probe.sh` (controller, list, auth in từ, args, version)
- [x] `scripts/state.sh` (show, get, set-verified, pref, clear; XDG)
- [x] `install.sh` (target/project/agents, check-ignore, idempotent, uninstall, force, dry-run)
- [x] `.gitignore` thêm `.envoy/`
- [x] Toàn bộ lệnh Verification xanh, shellcheck sạch

## Success Criteria

- `probe.sh list` không hard-code danh sách kind: đổi PATH thì kết quả đổi theo; không parse được help của Herdr thì báo lỗi rõ.
- Không script nào đọc file auth của CLI, không in output probe, không chạy chuỗi lệnh qua shell từ JSON.
- `install.sh` chạy hai lần không lỗi; `--uninstall` gỡ sạch; script chạy đúng qua symlink; `--project` từ chối khi link sẽ bị commit.

## Risk

- Định dạng `[possible values: ...]` của Herdr đổi → `herdr_kinds` chết với thông báo rõ thay vì danh sách rỗng âm thầm.
- `codex login status` exit code khi chưa login chưa được kiểm (máy đang login). Nếu khi hiện thực kiểm được bằng `CODEX_HOME=$(mktemp -d) codex login status` (thư mục rỗng, không chạm auth thật) thì làm và ghi vào `notes`.
- `readlink` trên macOS không có `-f`; resolve một bậc symlink là đủ cho install.sh (link trực tiếp vào thư mục skill), ghi chú trong `lib.sh`.
