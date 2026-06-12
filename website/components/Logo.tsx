/** Inline rendering of Sources/Resources/AppIcon.svg, simplified for small sizes. */
export function Logo({ size = 28 }: { size?: number }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 1024 1024"
      aria-hidden="true"
      focusable="false"
    >
      <defs>
        <linearGradient id="logo-backdrop" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#6E63F1" />
          <stop offset="0.5" stopColor="#5340DB" />
          <stop offset="1" stopColor="#371DA8" />
        </linearGradient>
        <linearGradient id="logo-faraway" x1="0" y1="0" x2="0.6" y2="1">
          <stop offset="0" stopColor="#FFD27A" />
          <stop offset="0.45" stopColor="#FF9457" />
          <stop offset="1" stopColor="#EF5D86" />
        </linearGradient>
        <linearGradient id="logo-glass" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#FFFFFF" stopOpacity="0.34" />
          <stop offset="1" stopColor="#FFFFFF" stopOpacity="0.16" />
        </linearGradient>
        <clipPath id="logo-clip">
          <rect x="0" y="0" width="1024" height="1024" rx="229" ry="229" />
        </clipPath>
      </defs>
      <g clipPath="url(#logo-clip)">
        <rect width="1024" height="1024" fill="url(#logo-backdrop)" />
        <g transform="translate(512 512) scale(1.2427) translate(-512 -512)">
          <rect x="480" y="288" width="320" height="248" rx="40" fill="url(#logo-faraway)" />
          <rect
            x="244"
            y="416"
            width="372"
            height="292"
            rx="44"
            fill="url(#logo-glass)"
            stroke="#FFFFFF"
            strokeOpacity="0.95"
            strokeWidth="16"
          />
          <circle cx="304" cy="472" r="11" fill="#FFFFFF" fillOpacity="0.9" />
          <circle cx="344" cy="472" r="11" fill="#FFFFFF" fillOpacity="0.62" />
          <circle cx="384" cy="472" r="11" fill="#FFFFFF" fillOpacity="0.38" />
        </g>
      </g>
    </svg>
  );
}
