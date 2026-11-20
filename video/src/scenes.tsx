import React from "react";
import { AbsoluteFill, interpolate, useCurrentFrame, useVideoConfig } from "remotion";
import { C, mono, serif } from "./theme";
import { Card, Kicker, Paper, Typed, fadeUp, useEnter } from "./ui";

const Center: React.FC<{ children: React.ReactNode; style?: React.CSSProperties }> = ({
  children,
  style,
}) => (
  <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", ...style }}>
    {children}
  </AbsoluteFill>
);

// 1. Title
export const TitleScene: React.FC = () => {
  const a = useEnter(0.1);
  const b = useEnter(0.7);
  const line = useEnter(0.4);
  return (
    <Paper>
      <Center style={{ flexDirection: "column", gap: 28 }}>
        <div style={fadeUp(a)}>
          <Kicker>Agent skills for Claude Code</Kicker>
        </div>
        <div style={{ ...fadeUp(a, 60), fontSize: 190, fontWeight: 800, letterSpacing: -6 }}>
          head-chief
        </div>
        <svg width={720} height={24}>
          <path
            d="M 6 14 C 160 4, 360 22, 520 10 S 700 14, 714 12"
            stroke={C.red}
            strokeWidth={6}
            fill="none"
            strokeLinecap="round"
            strokeDasharray={760}
            strokeDashoffset={760 * (1 - line)}
          />
        </svg>
        <div style={{ ...fadeUp(b), fontSize: 54, color: C.inkSoft, fontWeight: 400 }}>
          One session to run all the others.
        </div>
      </Center>
    </Paper>
  );
};

// 2. Problem: many sessions, nobody routing
const SESSIONS = ["auth-refactor", "fix-login-500", "docs-update", "api-tests", "perf-audit", "migration"];
export const ProblemScene: React.FC = () => {
  const frame = useCurrentFrame();
  const head = useEnter(0);
  const tail = useEnter(3.2);
  return (
    <Paper>
      <div style={{ position: "absolute", top: 90, left: 0, right: 0, textAlign: "center" }}>
        <div style={{ ...fadeUp(head), fontSize: 72, fontWeight: 600 }}>
          Six sessions in one repo. Who is doing what?
        </div>
      </div>
      <div
        style={{
          position: "absolute",
          top: 270,
          left: 210,
          width: 1500,
          display: "flex",
          flexWrap: "wrap",
          gap: 60,
          justifyContent: "center",
        }}
      >
        {SESSIONS.map((s, i) => {
          const p = useEnter(0.4 + i * 0.18);
          const wobble = Math.sin((frame + i * 20) / 9) * 2.5;
          return (
            <div key={s} style={{ ...fadeUp(p), transform: `${fadeUp(p).transform} rotate(${wobble}deg)` }}>
              <Card w={420} h={200} seed={s} fill={[C.blue, C.green, C.yellow, C.pink, C.lilac, C.blue][i]} progress={p}>
                <div style={{ fontFamily: mono, fontSize: 24, color: C.inkSoft }}>claude ▸</div>
                <div style={{ fontFamily: mono, fontSize: 34, fontWeight: 700, marginTop: 10 }}>{s}</div>
                <div style={{ fontSize: 64, color: C.red, position: "absolute", right: 34, bottom: 18, fontWeight: 800 }}>?</div>
              </Card>
            </div>
          );
        })}
      </div>
      <div style={{ position: "absolute", bottom: 80, left: 0, right: 0, textAlign: "center" }}>
        <div style={{ ...fadeUp(tail), fontSize: 50, color: C.inkSoft }}>
          You become the router: copying context, chasing status, switching tabs.
        </div>
      </div>
    </Paper>
  );
};

// 3. Hub: chief in the middle, staff sessions around it
const STAFF = [
  { name: "auth-refactor", x: 330, y: 300 },
  { name: "fix-login-500", x: 1590, y: 300 },
  { name: "docs-update", x: 330, y: 780 },
  { name: "api-tests", x: 1590, y: 780 },
];
export const HubScene: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const chief = useEnter(0.2);
  const cap = useEnter(0.1);
  const cx = 960;
  const cy = 540;
  return (
    <Paper>
      <div style={{ position: "absolute", top: 60, left: 0, right: 0, textAlign: "center" }}>
        <div style={{ ...fadeUp(cap), fontSize: 64, fontWeight: 600 }}>
          <span style={{ fontFamily: mono, color: C.red }}>/head-chief</span> makes one session your single point of contact
        </div>
      </div>
      <svg width={1920} height={1080} style={{ position: "absolute", inset: 0 }}>
        {STAFF.map((s, i) => {
          const p = interpolate(frame, [(0.8 + i * 0.25) * fps, (1.6 + i * 0.25) * fps], [0, 1], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
          });
          const len = Math.hypot(s.x - cx, s.y - cy);
          // A pulse travels chief -> staff, looping after the line is drawn.
          const t = ((frame - (2.2 + i * 0.4) * fps) / (1.4 * fps)) % 1;
          const show = frame > (2.2 + i * 0.4) * fps;
          return (
            <g key={s.name}>
              <line
                x1={cx}
                y1={cy}
                x2={s.x}
                y2={s.y}
                stroke={C.ink}
                strokeWidth={3}
                strokeDasharray={`${len}`}
                strokeDashoffset={len * (1 - p)}
              />
              {show && (
                <circle cx={cx + (s.x - cx) * t} cy={cy + (s.y - cy) * t} r={11} fill={C.red} />
              )}
            </g>
          );
        })}
      </svg>
      {STAFF.map((s, i) => {
        const p = useEnter(1.2 + i * 0.25);
        return (
          <div key={s.name} style={{ position: "absolute", left: s.x - 190, top: s.y - 70, ...fadeUp(p, 20) }}>
            <Card w={380} h={140} seed={`hub-${s.name}`} fill={C.paperDeep} progress={p}>
              <div style={{ fontFamily: mono, fontSize: 20, color: C.inkSoft }}>staff session</div>
              <div style={{ fontFamily: mono, fontSize: 30, fontWeight: 700, marginTop: 8 }}>{s.name}</div>
            </Card>
          </div>
        );
      })}
      <div style={{ position: "absolute", left: cx - 210, top: cy - 95, transform: `scale(${0.8 + 0.2 * chief})`, opacity: chief }}>
        <Card w={420} h={190} seed="chief" fill={C.yellow} progress={chief}>
          <Kicker>chief</Kicker>
          <div style={{ fontSize: 46, fontWeight: 800, marginTop: 8 }}>head-chief</div>
          <div style={{ fontFamily: mono, fontSize: 20, color: C.inkSoft, marginTop: 6 }}>routes · tracks · reports</div>
        </Card>
      </div>
      <div style={{ position: "absolute", bottom: 50, left: 0, right: 0, textAlign: "center", fontSize: 40, color: C.inkSoft, opacity: useEnter(3) }}>
        It finds running sessions, spawns new ones and stops them when the work is done.
      </div>
    </Paper>
  );
};

// 4. Classification: every request goes to one of three lanes
const REQUESTS = [
  { text: "what is everyone working on?", lane: 0 },
  { text: "fix the 500 on /login", lane: 1 },
  { text: "which branch is api-tests on?", lane: 2 },
];
const LANES = [
  { name: "CHIEF", desc: "Answered from the ledger", fill: C.yellow },
  { name: "MAIN", desc: "Logged, forwarded to a staff session", fill: C.blue },
  { name: "SIDECAR", desc: "A cheap lookup, small footprint", fill: C.green },
];
export const ClassifyScene: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const per = 2.4; // seconds per request
  const idx = Math.min(REQUESTS.length - 1, Math.floor(frame / (per * fps)));
  const local = frame - idx * per * fps;
  const req = REQUESTS[idx];
  const picked = local > 1.3 * fps;
  const head = useEnter(0);
  return (
    <Paper>
      <div style={{ position: "absolute", top: 80, left: 0, right: 0, textAlign: "center" }}>
        <div style={{ ...fadeUp(head), fontSize: 68, fontWeight: 600 }}>Every request is classified, then routed</div>
      </div>
      <div style={{ position: "absolute", top: 230, left: 260 }}>
        <Card w={1400} h={130} seed="term" fill={C.ink} progress={head}>
          <div style={{ fontFamily: mono, fontSize: 40, color: C.paper, paddingTop: 12 }}>
            <span style={{ color: C.yellow }}>you › </span>
            <Typed key={idx} text={req.text} start={idx * per} cps={30} />
          </div>
        </Card>
      </div>
      <div style={{ position: "absolute", top: 480, left: 160, display: "flex", gap: 60 }}>
        {LANES.map((l, i) => {
          const on = picked && req.lane === i;
          const p = useEnter(0.3 + i * 0.15);
          return (
            <div
              key={l.name}
              style={{
                ...fadeUp(p),
                transform: `${fadeUp(p).transform} translateY(${on ? -16 : 0}px)`,
                opacity: p * (picked && !on ? 0.45 : 1),
              }}
            >
              <Card w={490} h={300} seed={`lane-${i}`} fill={l.fill} progress={p}>
                <div style={{ fontFamily: mono, fontSize: 52, fontWeight: 700, color: on ? C.red : C.ink }}>{l.name}</div>
                <div style={{ fontSize: 36, marginTop: 20, lineHeight: 1.25 }}>{l.desc}</div>
                {on && (
                  <div style={{ position: "absolute", right: 30, bottom: 20, fontSize: 70, color: C.red, fontWeight: 800 }}>✓</div>
                )}
              </Card>
            </div>
          );
        })}
      </div>
    </Paper>
  );
};

// 5. The five skills
const SKILLS = [
  { name: "head-chief", desc: "The orchestrator: roster, routing, ledger, reports, discussion panels.", fill: C.yellow },
  { name: "managed-session", desc: "Spawn and stop Claude Code sessions as Herdr panes.", fill: C.blue },
  { name: "pr-review-loop", desc: "A separate reviewer session loops review → fix until approved.", fill: C.green },
  { name: "envoy-peer", desc: "Hand a task to codex, grok, … and have it reviewed until accepted.", fill: C.pink },
  { name: "roadmap-supervisor", desc: "Drive a roadmap to done through plan, cook and review sessions.", fill: C.lilac },
];
export const SkillsScene: React.FC = () => {
  const head = useEnter(0);
  return (
    <Paper>
      <div style={{ position: "absolute", top: 70, left: 0, right: 0, textAlign: "center" }}>
        <div style={fadeUp(head)}>
          <Kicker>Five skills that work together</Kicker>
        </div>
      </div>
      <div
        style={{
          position: "absolute",
          top: 170,
          left: 120,
          width: 1680,
          display: "flex",
          flexWrap: "wrap",
          gap: 48,
          justifyContent: "center",
        }}
      >
        {SKILLS.map((s, i) => {
          const p = useEnter(0.4 + i * 0.9);
          return (
            <div key={s.name} style={fadeUp(p)}>
              <Card w={520} h={380} seed={`skill-${s.name}`} fill={s.fill} progress={p}>
                <div style={{ fontFamily: mono, fontSize: 22, color: C.red, fontWeight: 700 }}>0{i + 1}</div>
                <div style={{ fontFamily: mono, fontSize: 38, fontWeight: 700, marginTop: 14 }}>{s.name}</div>
                <div style={{ fontSize: 34, marginTop: 22, lineHeight: 1.3 }}>{s.desc}</div>
              </Card>
            </div>
          );
        })}
      </div>
    </Paper>
  );
};

// 6. The ledger
const TREE: { line: string; note?: string }[] = [
  { line: ".orchestrator/" },
  { line: "├── system-prompt.md", note: "chief persona" },
  { line: "├── tracks/" },
  { line: "│   ├── INDEX.md", note: "fleet board" },
  { line: "│   └── fix-login-500/status.md", note: "mission + timeline" },
  { line: "└── logs/" },
  { line: "    └── fix-login-500/" },
  { line: "        └── 20261120-0341Z-fix-500-on-login.md", note: "one file per request" },
];
export const LedgerScene: React.FC = () => {
  const head = useEnter(0);
  const tail = useEnter(3.4);
  return (
    <Paper>
      <div style={{ position: "absolute", top: 80, left: 160 }}>
        <div style={fadeUp(head)}>
          <Kicker>A ledger you can read</Kicker>
        </div>
        <div style={{ ...fadeUp(head), fontSize: 66, fontWeight: 600, marginTop: 14, maxWidth: 1600 }}>
          Every routed request is written down, so reports cite evidence instead of memory.
        </div>
      </div>
      <div style={{ position: "absolute", top: 360, left: 160 }}>
        <Card w={1600} h={540} seed="ledger" fill="#fbf8f1" progress={head}>
          {TREE.map((t, i) => {
            const p = useEnter(0.5 + i * 0.3);
            return (
              <div key={t.line} style={{ display: "flex", alignItems: "baseline", gap: 30, opacity: p, fontFamily: mono, fontSize: 36, lineHeight: 1.62, whiteSpace: "pre" }}>
                <span style={{ fontWeight: i === 0 ? 700 : 400 }}>{t.line}</span>
                {t.note && <span style={{ fontFamily: serif, fontSize: 30, color: C.red, fontStyle: "italic" }}>← {t.note}</span>}
              </div>
            );
          })}
        </Card>
      </div>
      <div style={{ position: "absolute", bottom: 60, left: 0, right: 0, textAlign: "center", fontSize: 40, color: C.inkSoft, ...fadeUp(tail) }}>
        The chief never writes application code. It delegates, then verifies.
      </div>
    </Paper>
  );
};

// 7. Install
export const InstallScene: React.FC = () => {
  const a = useEnter(0.1);
  const b = useEnter(1.6);
  const c = useEnter(3.4);
  return (
    <Paper>
      <Center style={{ flexDirection: "column", gap: 44 }}>
        <div style={fadeUp(a)}>
          <Kicker>Try it in two lines</Kicker>
        </div>
        <div style={{ position: "relative", ...fadeUp(a) }}>
          <Card w={1300} h={250} seed="install" fill={C.ink} progress={a}>
            <div style={{ fontFamily: mono, fontSize: 42, color: C.paper, lineHeight: 1.7, paddingTop: 8 }}>
              <div>
                <span style={{ color: C.yellow }}>$ </span>
                <Typed text="npx skills add duylongpro99/head-chief" start={0.4} cps={30} />
              </div>
              <div style={{ opacity: b }}>
                <span style={{ color: C.yellow }}>› </span>/head-chief
              </div>
            </div>
          </Card>
        </div>
        <div style={{ ...fadeUp(c), fontSize: 46, color: C.inkSoft }}>
          github.com/duylongpro99/head-chief
        </div>
      </Center>
    </Paper>
  );
};
