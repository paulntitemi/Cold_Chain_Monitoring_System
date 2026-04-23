import { clsx } from 'clsx';
import type { ReactNode, ButtonHTMLAttributes } from 'react';

type Variant = 'teal' | 'green' | 'red' | 'ghost' | 'amber';

interface Props extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: Variant;
  children: ReactNode;
  fullWidth?: boolean;
  height?: 'md' | 'lg' | 'xl';
}

const variantStyles: Record<Variant, string> = {
  teal: 'bg-teal text-bg-primary border-teal disabled:bg-teal/30 disabled:text-bg-primary/50',
  green: 'bg-green text-bg-primary border-green',
  red: 'bg-red text-white border-red',
  amber: 'bg-amber text-bg-primary border-amber',
  ghost: 'bg-bg-card text-text-primary border-border',
};

const heightStyles: Record<NonNullable<Props['height']>, string> = {
  md: 'h-12 text-base',
  lg: 'h-14 text-lg',
  xl: 'h-16 text-xl',
};

export function BigButton({
  variant = 'teal',
  fullWidth = true,
  height = 'xl',
  className,
  children,
  ...rest
}: Props) {
  return (
    <button
      {...rest}
      className={clsx(
        'font-display font-semibold uppercase tracking-wider border-2 rounded-sm',
        'active:scale-[0.99] transition-transform',
        'disabled:cursor-not-allowed disabled:opacity-50',
        'flex items-center justify-center gap-2',
        fullWidth && 'w-full',
        variantStyles[variant],
        heightStyles[height],
        className,
      )}
    >
      {children}
    </button>
  );
}
