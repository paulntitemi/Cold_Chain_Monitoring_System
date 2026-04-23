import type { Config } from 'tailwindcss';

export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        bg: {
          primary: '#080C14',
          secondary: '#0D1420',
          card: '#111B2E',
        },
        border: {
          DEFAULT: '#1E2D45',
          bright: '#2A3F5F',
        },
        teal: {
          DEFAULT: '#00C9A7',
        },
        amber: {
          DEFAULT: '#F59E0B',
        },
        red: {
          DEFAULT: '#EF4444',
          tint: '#2D0A0A',
          row: '#1A0808',
        },
        green: {
          DEFAULT: '#10B981',
        },
        text: {
          primary: '#E2E8F0',
          secondary: '#64748B',
          dim: '#334155',
        },
      },
      fontFamily: {
        display: ['Rajdhani', 'system-ui', 'sans-serif'],
        body: ['"IBM Plex Sans"', 'system-ui', 'sans-serif'],
        mono: ['"IBM Plex Mono"', 'ui-monospace', 'monospace'],
      },
      keyframes: {
        'pulse-glow-amber': {
          '0%, 100%': { boxShadow: '0 0 0 0 rgba(245, 158, 11, 0.7)' },
          '50%': { boxShadow: '0 0 12px 4px rgba(245, 158, 11, 0.5)' },
        },
        'pulse-glow-red': {
          '0%, 100%': { boxShadow: '0 0 0 0 rgba(239, 68, 68, 0.8)' },
          '50%': { boxShadow: '0 0 16px 6px rgba(239, 68, 68, 0.55)' },
        },
        'pulse-fast-red': {
          '0%, 100%': { boxShadow: '0 0 0 0 rgba(239, 68, 68, 0.9)', opacity: '1' },
          '50%': { boxShadow: '0 0 20px 8px rgba(239, 68, 68, 0.7)', opacity: '0.9' },
        },
        'radiate-ring': {
          '0%': { transform: 'scale(0.8)', opacity: '0.7' },
          '100%': { transform: 'scale(2.2)', opacity: '0' },
        },
        'slide-in-right': {
          '0%': { transform: 'translateX(100%)', opacity: '0' },
          '100%': { transform: 'translateX(0)', opacity: '1' },
        },
        'slide-in-top': {
          '0%': { transform: 'translateY(-12px)', opacity: '0' },
          '100%': { transform: 'translateY(0)', opacity: '1' },
        },
      },
      animation: {
        'pulse-amber': 'pulse-glow-amber 2s ease-in-out infinite',
        'pulse-red': 'pulse-glow-red 1.8s ease-in-out infinite',
        'pulse-fast': 'pulse-fast-red 0.9s ease-in-out infinite',
        'radiate': 'radiate-ring 1.6s ease-out infinite',
        'slide-right': 'slide-in-right 260ms ease-out',
        'slide-top': 'slide-in-top 200ms ease-out',
      },
    },
  },
  plugins: [],
} satisfies Config;
