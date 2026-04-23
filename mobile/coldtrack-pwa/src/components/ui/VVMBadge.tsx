import { clsx } from 'clsx';
import type { VVMStage } from '@/types/batch';

const stageColour: Record<VVMStage, string> = {
  stage1: 'bg-green/15 text-green border-green/40',
  stage2: 'bg-amber/15 text-amber border-amber/40',
  stage3: 'bg-red/15 text-red border-red/40',
  stage4: 'bg-red text-white border-red',
};

const stageLabel: Record<VVMStage, string> = {
  stage1: 'VVM 1',
  stage2: 'VVM 2',
  stage3: 'VVM 3',
  stage4: 'VVM 4',
};

export function VVMBadge({ stage, className }: { stage: VVMStage; className?: string }) {
  return (
    <span
      className={clsx(
        'px-2 py-0.5 border rounded-sm text-[10px] font-mono uppercase tracking-wider',
        stageColour[stage],
        className,
      )}
    >
      {stageLabel[stage]}
    </span>
  );
}
