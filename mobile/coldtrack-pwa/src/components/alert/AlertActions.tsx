import { BigButton } from '@/components/ui/BigButton';

interface Props {
  onAccept(): void;
  onReject(): void;
  disabled?: boolean;
}

export function AlertActions({ onAccept, onReject, disabled }: Props) {
  return (
    <div className="grid grid-cols-2 gap-2">
      <BigButton variant="green" height="xl" onClick={onAccept} disabled={disabled}>
        ✓ Accept
      </BigButton>
      <BigButton variant="red" height="xl" onClick={onReject} disabled={disabled}>
        ✗ I can't
      </BigButton>
    </div>
  );
}
