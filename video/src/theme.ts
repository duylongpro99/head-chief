import { loadFont as loadSerif } from "@remotion/google-fonts/Fraunces";
import { loadFont as loadMono } from "@remotion/google-fonts/JetBrainsMono";

export const serif = loadSerif("normal", {
  weights: ["400", "600", "800"],
  subsets: ["latin"],
}).fontFamily;

export const mono = loadMono("normal", {
  weights: ["400", "700"],
  subsets: ["latin"],
}).fontFamily;

// Paper-and-pencil palette: warm paper, ink, one meaningful red, pastel pencil fills.
export const C = {
  paper: "#f4eee2",
  paperDeep: "#ebe3d2",
  ink: "#2b2622",
  inkSoft: "#6b625a",
  red: "#c4372c",
  blue: "#bcd3e6",
  green: "#cfe3c3",
  yellow: "#f2e1a6",
  pink: "#efc9c3",
  lilac: "#d9cfe8",
};

export const FPS = 30;
