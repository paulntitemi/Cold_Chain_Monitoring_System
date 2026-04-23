import { useMemo, useState } from 'react';
import toast from 'react-hot-toast';
import { useQueryClient } from '@tanstack/react-query';
import { api } from '@/lib/apiClient';
import type { VVMStage, VaccineType } from '@/types/batch';

interface Props {
  onClose: () => void;
}

const vaccineTypes: VaccineType[] = [
  'Polio',
  'Measles',
  'COVID-19',
  'Yellow Fever',
  'Meningitis',
  'Other',
];

const prefill: Record<VaccineType, { min: number; max: number; prefix: string }> = {
  Polio: { min: 2, max: 8, prefix: 'POL' },
  Measles: { min: 2, max: 8, prefix: 'MEA' },
  'COVID-19': { min: 2, max: 8, prefix: 'COV' },
  'Yellow Fever': { min: 2, max: 8, prefix: 'YFV' },
  Meningitis: { min: 2, max: 8, prefix: 'MNG' },
  Other: { min: 2, max: 8, prefix: 'VAC' },
};

export function BatchRegistrationModal({ onClose }: Props) {
  const qc = useQueryClient();
  const [vaccineType, setVaccineType] = useState<VaccineType>('Polio');
  const [manufacturer, setManufacturer] = useState('GSK, Brentford');
  const [manufactureDate, setManufactureDate] = useState(
    new Date().toISOString().slice(0, 10),
  );
  const [expiryDate, setExpiryDate] = useState(
    new Date(Date.now() + 365 * 86400_000).toISOString().slice(0, 10),
  );
  const [doseCount, setDoseCount] = useState(1000);
  const [minSafeTemp, setMinSafeTemp] = useState(2);
  const [maxSafeTemp, setMaxSafeTemp] = useState(8);
  const [vvmStatus, setVvmStatus] = useState<VVMStage>('stage1');
  const [storageLocation, setStorageLocation] = useState('NHS Central Vaccine Depot');
  const [notes, setNotes] = useState('');

  const suggestedId = useMemo(() => {
    const year = new Date().getFullYear();
    const seq = String(Math.floor(Math.random() * 9999)).padStart(4, '0');
    return `${prefill[vaccineType].prefix}-${year}-UK-${seq}`;
  }, [vaccineType]);
  const [batchId, setBatchId] = useState(suggestedId);

  const applyPrefill = (t: VaccineType) => {
    setVaccineType(t);
    setMinSafeTemp(prefill[t].min);
    setMaxSafeTemp(prefill[t].max);
    const year = new Date().getFullYear();
    const seq = String(Math.floor(Math.random() * 9999)).padStart(4, '0');
    setBatchId(`${prefill[t].prefix}-${year}-UK-${seq}`);
  };

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    await api.createBatch({
      batchId,
      vaccineType,
      manufacturer,
      manufactureDate: new Date(manufactureDate).toISOString(),
      expiryDate: new Date(expiryDate).toISOString(),
      doseCount,
      dosesRemaining: doseCount,
      minSafeTemp,
      maxSafeTemp,
      vvmStatus,
      storageLocation,
      status: 'in_storage',
      chainOfCustody: [
        {
          id: `${batchId}-CUST-1`,
          timestamp: new Date().toISOString(),
          eventType: 'received',
          location: storageLocation,
          handledBy: 'Control Desk',
          notes: notes || undefined,
        },
      ],
    });
    toast.success(`Registered ${batchId}`);
    qc.invalidateQueries({ queryKey: ['batches'] });
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-6" onClick={onClose}>
      <form
        onClick={(e) => e.stopPropagation()}
        onSubmit={submit}
        className="flex max-h-[90vh] w-full max-w-2xl flex-col rounded-sm border border-border bg-bg-primary shadow-2xl"
      >
        <header className="flex items-center justify-between border-b border-border px-6 py-4">
          <h2 className="font-display text-sm font-semibold uppercase tracking-widest text-text-primary">
            Register New Batch
          </h2>
          <button
            type="button"
            onClick={onClose}
            className="rounded-sm border border-border bg-bg-card px-2 py-1 text-text-secondary hover:text-text-primary"
          >
            ✕
          </button>
        </header>

        <div className="flex-1 overflow-y-auto px-6 py-5 space-y-4">
          <Field label="Batch ID">
            <input
              value={batchId}
              onChange={(e) => setBatchId(e.target.value)}
              className={inputCls}
              required
            />
          </Field>
          <div className="grid grid-cols-2 gap-4">
            <Field label="Vaccine Type">
              <select
                value={vaccineType}
                onChange={(e) => applyPrefill(e.target.value as VaccineType)}
                className={inputCls}
              >
                {vaccineTypes.map((t) => (
                  <option key={t} value={t}>
                    {t}
                  </option>
                ))}
              </select>
            </Field>
            <Field label="Manufacturer">
              <input
                value={manufacturer}
                onChange={(e) => setManufacturer(e.target.value)}
                className={inputCls}
                required
              />
            </Field>
          </div>
          <div className="grid grid-cols-2 gap-4">
            <Field label="Manufacture Date">
              <input
                type="date"
                value={manufactureDate}
                onChange={(e) => setManufactureDate(e.target.value)}
                className={inputCls}
                required
              />
            </Field>
            <Field label="Expiry Date">
              <input
                type="date"
                value={expiryDate}
                onChange={(e) => setExpiryDate(e.target.value)}
                className={inputCls}
                required
              />
            </Field>
          </div>
          <Field label="Initial Dose Count">
            <input
              type="number"
              min={1}
              value={doseCount}
              onChange={(e) => setDoseCount(parseInt(e.target.value, 10) || 0)}
              className={inputCls}
              required
            />
          </Field>
          <div className="grid grid-cols-2 gap-4">
            <Field label="Min Safe Temp (°C)">
              <input
                type="number"
                step={0.1}
                value={minSafeTemp}
                onChange={(e) => setMinSafeTemp(parseFloat(e.target.value))}
                className={inputCls}
              />
            </Field>
            <Field label="Max Safe Temp (°C)">
              <input
                type="number"
                step={0.1}
                value={maxSafeTemp}
                onChange={(e) => setMaxSafeTemp(parseFloat(e.target.value))}
                className={inputCls}
              />
            </Field>
          </div>
          <div className="grid grid-cols-2 gap-4">
            <Field label="Initial VVM Status">
              <select
                value={vvmStatus}
                onChange={(e) => setVvmStatus(e.target.value as VVMStage)}
                className={inputCls}
              >
                <option value="stage1">Stage 1 — OK</option>
                <option value="stage2">Stage 2 — Use first</option>
              </select>
            </Field>
            <Field label="Storage Location">
              <input
                value={storageLocation}
                onChange={(e) => setStorageLocation(e.target.value)}
                className={inputCls}
                required
              />
            </Field>
          </div>
          <Field label="Notes">
            <textarea
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              rows={3}
              className={inputCls}
            />
          </Field>
        </div>

        <footer className="flex justify-end gap-2 border-t border-border px-6 py-4">
          <button
            type="button"
            onClick={onClose}
            className="rounded-sm border border-border bg-bg-card px-4 py-1.5 text-sm text-text-secondary hover:text-text-primary"
          >
            Cancel
          </button>
          <button
            type="submit"
            className="rounded-sm border border-teal/60 bg-teal/20 px-4 py-1.5 text-sm font-semibold text-teal hover:bg-teal/30"
          >
            Register Batch
          </button>
        </footer>
      </form>
    </div>
  );
}

const inputCls =
  'w-full rounded-sm border border-border bg-bg-card px-3 py-1.5 text-sm text-text-primary focus:border-teal focus:outline-none';

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label className="block">
      <span className="mb-1 block text-[10px] font-semibold uppercase tracking-widest text-text-secondary">
        {label}
      </span>
      {children}
    </label>
  );
}
