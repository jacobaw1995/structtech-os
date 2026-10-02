import type { Metadata } from "next";
import localFont from "next/font/local";
import "./globals.css";

// U-W1.46 (2026-09-30) — A PRODUCTION BUILD MUST NOT DEPEND ON REACHING GOOGLE.
//
// A Production deploy FAILED on 2026-09-29 building be5a698: next/font/google
// crashed fetching IBM Plex Sans for this file — "TypeError: Cannot read
// properties of null (reading '1')" inside the font loader, build exit 1. The
// child commit built fine five minutes later, so it was a one-off network
// failure and not a code defect. THE FAILURE MODE IS THE POINT: on pilot week
// a font fetch can stop a deploy, and the error names the font loader rather
// than anything in the change being shipped — so the person debugging it starts
// in the wrong place.
//
// The files are now in the repo and the build touches no network for type.
// LICENCE: IBM Plex is SIL Open Font License 1.1 — verified against the
// authoritative source (github.com/IBM/plex, SPDX OFL-1.1), which permits
// bundling provided the licence travels with the fonts. It is at
// src/app/fonts/OFL.txt.
//
// SANS IS ONE FILE, NOT FOUR, and that was a measurement rather than a guess:
// the four weights downloaded from Google were BYTE-IDENTICAL (same MD5), because
// IBM Plex Sans is served as a VARIABLE font. Declaring it as four static faces
// would have loaded the same file four times under four names. It is declared
// once with the weight RANGE it actually covers. Mono and Serif are genuinely
// distinct files per weight and are declared that way.
const plexSans = localFont({
  src: [{ path: "./fonts/IBMPlexSans-variable.woff2", weight: "400 700", style: "normal" }],
  variable: "--font-plex-sans",
  display: "swap",
});
const plexMono = localFont({
  src: [
    { path: "./fonts/IBMPlexMono-400.woff2", weight: "400", style: "normal" },
    { path: "./fonts/IBMPlexMono-500.woff2", weight: "500", style: "normal" },
    { path: "./fonts/IBMPlexMono-600.woff2", weight: "600", style: "normal" },
  ],
  variable: "--font-plex-mono",
  display: "swap",
});
const plexSerif = localFont({
  src: [
    { path: "./fonts/IBMPlexSerif-400.woff2", weight: "400", style: "normal" },
    { path: "./fonts/IBMPlexSerif-600.woff2", weight: "600", style: "normal" },
  ],
  variable: "--font-plex-serif",
  display: "swap",
  // next/font/google derives the fallback face from the font's own metrics; for
  // a local font the base family is named, and a serif must fall back to a serif
  // or the swap shifts the line.
  adjustFontFallback: "Times New Roman",
});

export const metadata: Metadata = {
  title: "StructTech OS",
  description: "StructTech OS — multi-tenant operations platform",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body
        className={`${plexSans.variable} ${plexMono.variable} ${plexSerif.variable} font-sans antialiased`}
      >
        {children}
      </body>
    </html>
  );
}
