# Acting on feedback, and reporting

Each rule below comes from a specific moment in the session this skill was drawn from.
The reason is given so you can judge cases the rule does not name.

## Reading the feedback

- **Read every note, wherever it sits.** The user wrote a request about models in the box
  for the changes section, and a request about a local port in the context box. A box's
  title says where the cursor was, not what the note is about.
- **"Đồng ý" with a note still has work in it.** One agreed section carried a note that
  reorganised the whole role structure.
- **A note without a verdict is feedback.** So is the free field at the end, which the
  user once used to introduce an entirely new idea.
- **Feedback in chat counts the same** as feedback from the page. It does not start a new
  round: keep the round number so what the user has typed on the page survives.
- **Feedback titled with an older round** than the draft was written against an earlier
  version. Say so and map each point onto the current text before changing anything.

## Changing the draft

- **Change the page; keep the chat short.** After round 1 the agent answered at length in
  chat and promised to update the file later, and the user had to ask for the update.
- **"Cần bàn thêm" on a choice means rewrite that choice,** and show the previous version
  beside the new one with a before/after pair so the change is visible.
- **When the user faults your wording, say it was wrong and rewrite it.** The user read
  "Thế mạnh của team là chạy thử, không phải viết" as a promise of poor writing. The
  reply was "tôi diễn đạt sai ý và đã viết lại", with no defence. More generally, do not
  praise one quality by running down another; the reader takes the second half as a
  commitment.
- **A user decision goes to "Đã chốt" and stays there.** When you have a concern about a
  decision, keep the decision, state the concern beside it and propose how to check it
  later. The model for this: "Tôi giữ lựa chọn của bạn", followed by a way to compare
  results.
- **Follow a decision through.** When the user chose not to add credit, the model
  assignment table changed, an option that depended on a balance was removed, and the
  reason was written at each place.
- **Do the check the user asked for, then write the result on the page.** Checking and
  reporting only in chat leaves the page stale.
- **Label every number and command** as verified, estimated or not yet tried, at the
  place it appears: "Con số 100 tới 200 là ước lượng của tôi", "Tôi chưa chạy thử các
  bước này".
- **Name what you decided yourself.** List these in the report and invite objection
  through the feedback boxes: "Ba điểm tôi tự quyết, bạn có thể phản đối ngay trong ô
  góp ý".
- **No secret values on the page.** Name the environment variable or the file, and say
  that you did not read it.

## Unanswered questions

Every `(chưa chọn)` line in the export is resolved one of two ways:

- **Inferred.** When the option is described in a section the user marked "Đồng ý", take
  the option from that section. Write the inference where the decision is recorded and
  repeat it in the report, for example: "Bạn không chọn ở phần câu hỏi, nhưng đã đồng ý
  với các phần mô tả chúng, nên tôi lấy theo phương án trong các phần đó. Nếu tôi hiểu sai
  mục nào, bạn nói lại là tôi sửa."
- **Asked.** When nothing on the page settles it, ask the user directly, one question per
  open item, and say that it was left blank in the previous round. The answer may be
  outside the offered options; record it as given.

A question is never treated as answered by your own recommendation alone.

## Report after each version

Keep this order, in the user's language, in complete sentences:

1. One sentence with the outcome: which version this is, and that it is the same file.
2. Check status, including what could not be done. If the page was not opened in a
   browser, say so here, with the reason.
3. The command for the user to open the page, with the absolute path.
4. A reply to each point the user raised, each naming the section that changed.
5. What you decided yourself, and what is still unverified.
6. Questions still open, and that they are answered on the page.
7. For a new round: the feedback boxes start empty because the content changed; the
   previous round's feedback is still in the browser but no longer shown.

For round 1, items 4 and 7 are replaced by what the page contains and how to give
feedback: mark each section, write notes, answer the questions, press "Sao chép góp ý"
and paste the result into the session.
