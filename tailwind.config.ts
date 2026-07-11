import type { Config } from "tailwindcss";

const config: Config = {
  content: [
    "./src/pages/**/*.{js,ts,jsx,tsx,mdx}",
    "./src/components/**/*.{js,ts,jsx,tsx,mdx}",
    "./src/app/**/*.{js,ts,jsx,tsx,mdx}",
  ],
  theme: {
    extend: {
      colors: {
        bg: "var(--bg)",
        surface: "var(--surface)",
        surface2: "var(--surface2)",
        text: "var(--text)",
        muted: "var(--muted)",
        border: "var(--border)",
        accent: {
          DEFAULT: "var(--accent)",
          strong: "var(--accent-strong)",
          soft: "var(--accent-soft)",
        },
        warn: {
          DEFAULT: "var(--warn)",
          soft: "var(--warn-soft)",
        },
      },
      fontFamily: {
        sans: ["var(--font-plex-sans)", "ui-sans-serif", "system-ui", "sans-serif"],
        mono: ["var(--font-plex-mono)", "ui-monospace", "monospace"],
        serif: ["var(--font-plex-serif)", "ui-serif", "serif"],
      },
    },
  },
  plugins: [],
};
export default config;
