// Inline Lucide-style icons. Pass `size` and `color`; default inherits currentColor.
// Strokes are 2px, round caps/joins — matching Lucide defaults.

const Icon = ({ children, size = 16, color = 'currentColor', stroke = 2, fill = 'none', style }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill={fill} stroke={color}
       strokeWidth={stroke} strokeLinecap="round" strokeLinejoin="round"
       style={{ flexShrink: 0, ...style }}>
    {children}
  </svg>
);

const MoonIcon = (p) => <Icon {...p}><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/></Icon>;
const HeartPulseIcon = (p) => <Icon {...p}>
  <path d="M20.42 4.58a5.4 5.4 0 0 0-7.65 0l-.77.78-.77-.78a5.4 5.4 0 0 0-7.65 7.65l8.42 8.42 8.42-8.42a5.4 5.4 0 0 0 0-7.65z"/>
  <path d="M3.22 12H9.5l.5-1 2 4.5 2-7 1.5 3.5h5.27"/>
</Icon>;
const PenLineIcon = (p) => <Icon {...p}>
  <path d="M12 20h9"/><path d="M16.5 3.5a2.12 2.12 0 0 1 3 3L7 19l-4 1 1-4L16.5 3.5z"/>
</Icon>;
const PencilIcon = (p) => <Icon {...p}>
  <path d="M12 20h9"/><path d="M16.5 3.5a2.12 2.12 0 0 1 3 3L7 19l-4 1 1-4L16.5 3.5z"/>
</Icon>;
const SmileIcon = (p) => <Icon {...p}>
  <circle cx="12" cy="12" r="10"/><path d="M8 14s1.5 2 4 2 4-2 4-2"/>
  <line x1="9" y1="9" x2="9.01" y2="9"/><line x1="15" y1="9" x2="15.01" y2="9"/>
</Icon>;
const MehIcon = (p) => <Icon {...p}>
  <circle cx="12" cy="12" r="10"/><line x1="8" y1="15" x2="16" y2="15"/>
  <line x1="9" y1="9" x2="9.01" y2="9"/><line x1="15" y1="9" x2="15.01" y2="9"/>
</Icon>;
const FrownIcon = (p) => <Icon {...p}>
  <circle cx="12" cy="12" r="10"/><path d="M16 16s-1.5-2-4-2-4 2-4 2"/>
  <line x1="9" y1="9" x2="9.01" y2="9"/><line x1="15" y1="9" x2="15.01" y2="9"/>
</Icon>;
const RefreshIcon = (p) => <Icon {...p}>
  <path d="M23 4v6h-6"/><path d="M1 20v-6h6"/>
  <path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10"/>
  <path d="M20.49 15a9 9 0 0 1-14.85 3.36L1 14"/>
</Icon>;
const ChevronRightIcon = (p) => <Icon {...p}><polyline points="9 18 15 12 9 6"/></Icon>;
const ChevronLeftIcon = (p) => <Icon {...p}><polyline points="15 18 9 12 15 6"/></Icon>;
const ArrowRightIcon = (p) => <Icon {...p}><line x1="5" y1="12" x2="19" y2="12"/><polyline points="12 5 19 12 12 19"/></Icon>;
const SunIcon = (p) => <Icon {...p}>
  <circle cx="12" cy="12" r="5"/>
  <line x1="12" y1="1" x2="12" y2="3"/><line x1="12" y1="21" x2="12" y2="23"/>
  <line x1="4.22" y1="4.22" x2="5.64" y2="5.64"/><line x1="18.36" y1="18.36" x2="19.78" y2="19.78"/>
  <line x1="1" y1="12" x2="3" y2="12"/><line x1="21" y1="12" x2="23" y2="12"/>
  <line x1="4.22" y1="19.78" x2="5.64" y2="18.36"/><line x1="18.36" y1="5.64" x2="19.78" y2="4.22"/>
</Icon>;
const XIcon = (p) => <Icon {...p}><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></Icon>;
const PlusIcon = (p) => <Icon {...p}><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></Icon>;
const InfoIcon = (p) => <Icon {...p}><circle cx="12" cy="12" r="10"/><line x1="12" y1="16" x2="12" y2="12"/><line x1="12" y1="8" x2="12.01" y2="8"/></Icon>;
const LockIcon = (p) => <Icon {...p}>
  <rect x="3" y="11" width="18" height="11" rx="2"/>
  <path d="M7 11V7a5 5 0 0 1 10 0v4"/>
</Icon>;
const DumbbellIcon = (p) => <Icon {...p}>
  <path d="M6.5 6.5L17.5 17.5"/><path d="M21 21l-1-1"/><path d="M3 3l1 1"/>
  <path d="M18 22l4-4"/><path d="M2 6l4-4"/>
  <path d="M3 10l7-7"/><path d="M14 21l7-7"/>
</Icon>;
const ScaleIcon = (p) => <Icon {...p}>
  <path d="M6 20h12"/><circle cx="12" cy="12" r="8"/>
  <path d="M9 10l3 2 3-2"/>
</Icon>;
const UtensilsIcon = (p) => <Icon {...p}>
  <path d="M3 2v7c0 1.1.9 2 2 2h0a2 2 0 0 0 2-2V2"/>
  <path d="M5 11v11"/><path d="M19 2v20"/>
  <path d="M15 2h4a0 0 0 0 1 0 0v7a4 4 0 0 1-4 4h0V2z"/>
</Icon>;
const BellIcon = (p) => <Icon {...p}>
  <path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"/>
  <path d="M13.73 21a2 2 0 0 1-3.46 0"/>
</Icon>;

const RatingIcon = ({ rating, size = 20 }) => {
  const c = window.TOKENS.light;
  if (rating === 'smile') return <SmileIcon size={size} color={c.success} stroke={2}/>;
  if (rating === 'meh')   return <MehIcon   size={size} color={c.warning} stroke={2}/>;
  if (rating === 'frown') return <FrownIcon size={size} color={c.error}   stroke={2}/>;
  return null;
};

const ratingColor = (rating, mode='light') => {
  const c = window.TOKENS[mode];
  return rating === 'smile' ? c.success : rating === 'meh' ? c.warning : c.error;
};
const ratingLabel = (r) => r === 'smile' ? 'すっきり' : r === 'meh' ? 'まあまあ' : r === 'frown' ? 'だるい' : '';

Object.assign(window, {
  Icon, MoonIcon, HeartPulseIcon, PenLineIcon, PencilIcon,
  SmileIcon, MehIcon, FrownIcon,
  RefreshIcon, ChevronRightIcon, ChevronLeftIcon, ArrowRightIcon,
  SunIcon, XIcon, PlusIcon, InfoIcon, LockIcon,
  DumbbellIcon, ScaleIcon, UtensilsIcon, BellIcon,
  RatingIcon, ratingColor, ratingLabel,
});
