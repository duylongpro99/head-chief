import React from "react";
import {
  AbsoluteFill,
  interpolate,
  random,
  spring,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { C, mono, serif } from "./theme";

// Spring entrance that starts `delay` seconds into the current sequence.
export const useEnter = (delay = 0, damping = 200) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  return spring({ frame: frame - delay * fps, fps, config: { damping } });
};

export const Paper: React.FC<{ children: React.ReactNode }> = ({ children }) => (
  <AbsoluteFill
    style={{
      backgroundColor: C.paper,
      backgroundImage: `radial-gradient(${C.paperDeep} 1px, transparent 1px)`,
      backgroundSize: "28px 28px",
      color: C.ink,
      fontFamily: serif,
    }}
  >
    {children}
  </AbsoluteFill>
);

// A hand-wobbled rectangle outline, drawn on with a stroke-dash reveal.
export const InkBox: React.FC<{
  w: number;
  h: number;
  seed: string;
  progress?: number;
  stroke?: string;
  fill?: string;
  strokeWidth?: number;
}> = ({ w, h, seed, progress = 1, stroke = C.ink, fill = "none", strokeWidth = 3 }) => {
  const j = (i: number) => (random(`${seed}-${i}`) - 0.5) * 6;
  const pts = [
    [4 + j(1), 4 + j(2)],
    [w / 2 + j(3), 3 + j(4)],
    [w - 4 + j(5), 4 + j(6)],
    [w - 3 + j(7), h / 2 + j(8)],
    [w - 4 + j(9), h - 4 + j(10)],
    [w / 2 + j(11), h - 3 + j(12)],
    [4 + j(13), h - 4 + j(14)],
    [3 + j(15), h / 2 + j(16)],
  ];
  const d = `M ${pts.map((p) => p.join(" ")).join(" L ")} Z`;
  const len = 2 * (w + h) + 60;
  return (
    <svg width={w} height={h} style={{ position: "absolute", inset: 0, overflow: "visible" }}>
      <path d={d} fill={fill} opacity={fill === "none" ? 1 : Math.min(1, progress * 1.5)} stroke="none" />
      <path
        d={d}
        fill="none"
        stroke={stroke}
        strokeWidth={strokeWidth}
        strokeLinejoin="round"
        strokeDasharray={len}
        strokeDashoffset={len * (1 - progress)}
      />
    </svg>
  );
};

// A card with a pencil fill and a wobbly ink border.
export const Card: React.FC<{
  w: number;
  h: number;
  seed: string;
  fill: string;
  progress: number;
  children: React.ReactNode;
  style?: React.CSSProperties;
}> = ({ w, h, seed, fill, progress, children, style }) => (
  <div style={{ position: "relative", width: w, height: h, ...style }}>
    <InkBox w={w} h={h} seed={seed} fill={fill} progress={progress} />
    <div style={{ position: "relative", padding: "26px 30px", height: "100%", boxSizing: "border-box" }}>
      {children}
    </div>
  </div>
);

export const Kicker: React.FC<{ children: React.ReactNode; color?: string }> = ({
  children,
  color = C.red,
}) => (
  <div
    style={{
      fontFamily: mono,
      fontSize: 26,
      letterSpacing: 4,
      textTransform: "uppercase",
      color,
      fontWeight: 700,
    }}
  >
    {children}
  </div>
);

// Typewriter text: reveals characters by frame.
export const Typed: React.FC<{ text: string; start?: number; cps?: number }> = ({
  text,
  start = 0,
  cps = 28,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const n = Math.max(0, Math.floor(((frame - start * fps) / fps) * cps));
  const shown = text.slice(0, n);
  const caretOn = Math.floor(frame / 15) % 2 === 0 || n < text.length;
  return (
    <span>
      {shown}
      <span style={{ opacity: caretOn && n <= text.length ? 1 : 0 }}>▍</span>
    </span>
  );
};

export const fadeUp = (p: number, dist = 40): React.CSSProperties => ({
  opacity: p,
  transform: `translateY(${interpolate(p, [0, 1], [dist, 0])}px)`,
});
