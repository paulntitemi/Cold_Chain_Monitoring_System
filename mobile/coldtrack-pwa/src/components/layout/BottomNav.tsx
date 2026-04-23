import { NavLink } from 'react-router-dom';
import { clsx } from 'clsx';

const items = [
  { to: '/assignments', label: 'Trips' },
  { to: '/profile', label: 'Profile' },
];

export function BottomNav() {
  return (
    <nav
      className="border-t border-border bg-bg-secondary flex"
      style={{ paddingBottom: 'env(safe-area-inset-bottom)' }}
    >
      {items.map((it) => (
        <NavLink
          key={it.to}
          to={it.to}
          className={({ isActive }) =>
            clsx(
              'flex-1 h-14 flex items-center justify-center font-display font-semibold uppercase tracking-wider text-sm',
              isActive ? 'text-teal border-t-2 border-teal' : 'text-text-secondary',
            )
          }
        >
          {it.label}
        </NavLink>
      ))}
    </nav>
  );
}
