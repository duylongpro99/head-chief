import React from "react";
import { TransitionSeries, linearTiming } from "@remotion/transitions";
import { fade } from "@remotion/transitions/fade";
import { slide } from "@remotion/transitions/slide";
import { FPS } from "./theme";
import {
  ClassifyScene,
  HubScene,
  InstallScene,
  LedgerScene,
  ProblemScene,
  SkillsScene,
  TitleScene,
} from "./scenes";

const s = (sec: number) => Math.round(sec * FPS);
const T = s(0.6); // transition length

const SCENES: { C: React.FC; dur: number }[] = [
  { C: TitleScene, dur: s(4) },
  { C: ProblemScene, dur: s(6) },
  { C: HubScene, dur: s(7) },
  { C: ClassifyScene, dur: s(7.6) },
  { C: SkillsScene, dur: s(7.5) },
  { C: LedgerScene, dur: s(7) },
  { C: InstallScene, dur: s(6) },
];

export const INTRO_DURATION = SCENES.reduce((a, b) => a + b.dur, 0) - T * (SCENES.length - 1);

export const HeadChiefIntro: React.FC = () => (
  <TransitionSeries>
    {SCENES.map(({ C, dur }, i) => (
      <React.Fragment key={i}>
        {i > 0 && (
          <TransitionSeries.Transition
            presentation={i % 2 ? slide({ direction: "from-right" }) : fade()}
            timing={linearTiming({ durationInFrames: T })}
          />
        )}
        <TransitionSeries.Sequence durationInFrames={dur}>
          <C />
        </TransitionSeries.Sequence>
      </React.Fragment>
    ))}
  </TransitionSeries>
);
