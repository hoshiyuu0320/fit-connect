// Design tokens from the brief — AppColors spec.
// All measurements honor the brief's spacing/radius/type rules.

const TOKENS = {
  light: {
    primary:        '#2563EB',
    primary50:      '#EFF6FF',
    primary400:     '#60A5FA',
    background:     '#FAFAFA',
    cardBackground: '#FFFFFF',
    textPrimary:    '#1E293B',
    textSecondary:  '#64748B',
    textHint:       '#94A3B8',
    slate100:       '#F1F5F9',
    slate200:       '#E2E8F0',
    slate400:       '#94A3B8',
    slate500:       '#64748B',
    slate700:       '#334155',
    success:        '#10B981',
    warning:        '#F97316',
    error:          '#EF4444',
    indigo50:       '#EEF2FF',
    indigo400:      '#818CF8',
    indigo600:      '#4F46E5',
    indigo700:      '#4338CA',
    // Shadow spec: black 5%
    shadow:         '0 1px 2px rgba(0,0,0,0.05)',
  },
  dark: {
    primary:        '#3B82F6',
    primary50:      '#1E293B',
    primary400:     '#60A5FA',
    background:     '#0B1220',
    cardBackground: '#111827',
    textPrimary:    '#F1F5F9',
    textSecondary:  '#94A3B8',
    textHint:       '#64748B',
    slate100:       '#1E293B',
    slate200:       '#334155',
    slate400:       '#64748B',
    slate500:       '#94A3B8',
    slate700:       '#CBD5E1',
    success:        '#10B981',
    warning:        '#F97316',
    error:          '#F87171',
    indigo50:       '#1E1B4B',
    indigo400:      '#818CF8',
    indigo600:      '#6366F1',
    indigo700:      '#4338CA',
    shadow:         '0 1px 2px rgba(0,0,0,0.4)',
  },
};

// Sleep stage colors — consistent across modes (brand semantic)
const STAGE = {
  deep:  '#4338CA',
  light: '#818CF8',
  rem:   '#60A5FA',
  awake: '#E2E8F0',
};

const STAGE_DARK = {
  deep:  '#6366F1',
  light: '#818CF8',
  rem:   '#60A5FA',
  awake: '#475569',
};

const T = {
  radius: { card: 8, button: 6, chip: 6 },
  pad:    { card: 16, section: 24, listGap: 12 },
  font:   "'Noto Sans JP', -apple-system, system-ui, sans-serif",
  mono:   "'JetBrains Mono', ui-monospace, monospace",
};

// Sample data used across mockups
const SAMPLE = {
  bedtime:  '23:45',
  wakeup:   '7:08',
  duration: { h: 7, m: 23 },
  stages:   { deep: 25, light: 50, rem: 20, awake: 5 },
  stageMin: { deep: '1h50m', light: '3h41m', rem: '1h28m', awake: '22m' },
  week:     [7.2, 6.5, 8.0, null, 7.8, 6.0, 7.3],
  weekDates:['4/12','4/13','4/14','4/15','4/16','4/17','4/18'],
  weekDow:  ['日','月','火','水','木','金','土'],
  weekRate: ['smile','meh','smile',null,'smile','frown','smile'],
  rating:   'smile', // smile | meh | frown
};

Object.assign(window, { TOKENS, STAGE, STAGE_DARK, T, SAMPLE });
