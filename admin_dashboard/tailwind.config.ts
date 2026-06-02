import type { Config } from 'tailwindcss';

export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        border: '#E2E8F0',
        muted: '#64748B',
        ink: '#0F172A',
        brand: '#1E88B8',
      },
      boxShadow: {
        panel: '0 1px 2px rgba(15, 23, 42, 0.06)',
      },
    },
  },
  plugins: [],
} satisfies Config;
