---
title: "Plan skill envoy-peer: peer session khác loại trong Herdr"
date: 2026-10-28
summary: "Lên kế hoạch 4 phase cho skill envoy-peer từ docs/brainstorms/envoy.md; red-team 3 reviewer, 15 findings đã áp; user chốt 4 quyết định validate."
---

# Plan skill envoy-peer: peer session khác loại trong Herdr

## What happened
- Review và viết lại yêu cầu `docs/brainstorms/envoy.md`: envoy là peer session trong pane Herdr (không subagent), reviewer là pane riêng cùng loại controller, full permission, cùng cây, đóng pane khi xong.
- Xác minh live flag full-permission và probe auth cho claude, codex (codex-cli 0.153.4), grok 0.2.101, omp 18.3.5, agy 1.1.21; pi và hermes chưa cài nên đánh dấu unverified.
- Scaffold `plans/261028-0731-envoy-peer-skill` bằng `ak plan create`, 4 phase: nền tảng (kinds.json, probe, state, install.sh), lifecycle pane (new-run, start, prompt-wait, run-state, stop, cleanup), contract (templates, check-brief, SKILL.md), đóng gói và e2e.
- Red-team với 3 reviewer code-reviewer (Security, Assumption, Failure-mode): 29 findings thô, gộp 15, chấp nhận 15 (5 có chỉnh), bác 3 đề xuất con.

## Root causes found by red-team
- Herdr báo `done` thay vì `idle` cho pane không được nhìn thấy; mọi wait `--until idle` sẽ treo. Sửa: dùng mặc định `idle|done|blocked`.
- `herdr agent get` không có trường tên agent và trả `agent_not_found` cho cả pane shell lẫn pane đã mất; kiểm sở hữu pane theo tên không hiện thực được. Sửa: so `pane_id` + `terminal_id` với `herdr pane list`, label pane trước khi start.
- Bash tool của Claude Code mặc định 120 s, không phải 10 phút; SKILL.md phải bắt caller đặt timeout 600000 hoặc chạy nền; `prompt-wait.sh` từ chối gửi trùng (mã 8).
- Kiểm hoàn thành theo dòng `Status:` nhận file cũ hoặc template chép nguyên; sửa bằng `Round: n` + mtime và placeholder không parse được.
- Baseline chỉ `git status --short` không phân biệt sửa trên file đã bẩn; sửa bằng `git stash create` + manifest untracked + guard sha trước/sau reviewer.
- Đọc 40 dòng pane khi `blocked` trong onboarding có thể lộ mã login; sửa bằng `--no-read` và bộ lọc `redact`.

## Decision
- User chốt: run dir `.envoy/runs/<ts>-<slug>-<nonce>/` tại git root tự ignore; mặc định 3 round / 60 phút / split; có `--model` và `--reviewer-model` ở bản đầu; `--cleanup --all` chỉ đóng run của session này hoặc controller đã chết, dry-run trước, `--yes` để đóng.
- Bác bỏ: registry run ngoài cây (envoy cùng user ghi được mọi nơi, không thêm bảo vệ), nonce trong prompt và xoay result.md (Round + mtime đủ), TTL bỏ smoke cho kind không có probe (trái yêu cầu probe mỗi run).

## Next steps
- Hiện thực theo `/ak:cook plans/261028-0731-envoy-peer-skill/plan.md`, bắt đầu Phase 1.
- Bước smoke live đầu Phase 2 quyết định `herdr agent start -- <args>` có chuyển args cho codex không; nếu không, fallback `pane run`.
- Task hydration bỏ qua vì session không có công cụ task-management; theo dõi bằng checkbox trong phase files.

> Historical work record — not durable authority. Prefer docs/specs/ADRs for current decisions.
