import type { Config } from "tailwindcss";

export default {
  content: [
    "./src/pages/**/*.{js,ts,jsx,tsx,mdx}",
    "./src/components/**/*.{js,ts,jsx,tsx,mdx}",
    "./src/app/**/*.{js,ts,jsx,tsx,mdx}",
  ],
  theme: {
    extend: {
      fontFamily: {
        sans: ['var(--font-jakarta)', 'var(--font-noto)', 'sans-serif'],
      },
      colors: {
        background: "hsl(var(--background))",
        foreground: "hsl(var(--foreground))",
        accent: {
          DEFAULT: "#14B8A6",
          light: "#F0FDFA",
          subtle: "#CCFBF1",
          hover: "#0D9488",
        },
      },
      borderRadius: {
        DEFAULT: '6px',
      },
    },
  },
  plugins: [],
} satisfies Config;
