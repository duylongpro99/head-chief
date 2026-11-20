import React from "react";
import { Composition } from "remotion";
import { HeadChiefIntro, INTRO_DURATION } from "./head-chief-intro";
import { FPS } from "./theme";

export const RemotionRoot: React.FC = () => (
  <Composition
    id="HeadChiefIntro"
    component={HeadChiefIntro}
    durationInFrames={INTRO_DURATION}
    fps={FPS}
    width={1920}
    height={1080}
  />
);
