import { useState } from 'react';
import { useMutation } from '@tanstack/react-query';
import { api } from '@/lib/apiClient';
import { vibrate, PATTERNS } from '@/lib/haptic';
import { BigButton } from '@/components/ui/BigButton';
import { PhotoCapture } from './PhotoCapture';
import { SignaturePad } from './SignaturePad';
import type { HandoffRecord } from '@/types/rider-ext';
import type { Shipment } from '@/types/shipment';

interface Props {
  shipment: Shipment;
  location: HandoffRecord['location'];
  coldStoreId?: string;
  offerSignature?: boolean;
  onComplete(): void;
}

export function HandoffForm({ shipment, location, coldStoreId, offerSignature, onComplete }: Props) {
  const [recipientName, setRecipientName] = useState('');
  const [recipientRole, setRecipientRole] = useState('');
  const [photo, setPhoto] = useState<string | null>(null);
  const [signature, setSignature] = useState<string | null>(null);
  const [tempAtHandoff, setTempAtHandoff] = useState(shipment.currentTemp);
  const [notes, setNotes] = useState('');
  const [err, setErr] = useState<string | null>(null);

  const submit = useMutation({
    mutationFn: async () => {
      const record: HandoffRecord = {
        shipmentId: shipment.id,
        location,
        coldStoreId,
        recipientName: recipientName.trim(),
        recipientRole: recipientRole.trim() || undefined,
        signature: signature ?? undefined,
        photoUrl: photo ?? undefined,
        tempAtHandoff,
        notes: notes.trim() || undefined,
        clientTimestamp: new Date().toISOString(),
      };
      await api.postHandoff(record);
    },
    onSuccess: () => {
      vibrate(PATTERNS.confirm);
      onComplete();
    },
    onError: (e) => setErr(e instanceof Error ? e.message : 'Failed to submit'),
  });

  const valid = recipientName.trim().length > 1 && !Number.isNaN(tempAtHandoff);

  return (
    <div className="space-y-4">
      <label className="flex flex-col gap-1">
        <span className="text-xs font-mono uppercase text-text-secondary tracking-wider">Recipient name</span>
        <input
          type="text"
          value={recipientName}
          onChange={(e) => setRecipientName(e.target.value)}
          placeholder="Staff member"
          className="h-12 px-3 bg-bg-secondary border border-border text-text-primary font-body text-lg rounded-sm focus:outline-none focus:border-teal"
        />
      </label>

      <label className="flex flex-col gap-1">
        <span className="text-xs font-mono uppercase text-text-secondary tracking-wider">Role (optional)</span>
        <input
          type="text"
          value={recipientRole}
          onChange={(e) => setRecipientRole(e.target.value)}
          placeholder="Pharmacist, cold-store manager…"
          className="h-12 px-3 bg-bg-secondary border border-border text-text-primary font-body text-lg rounded-sm focus:outline-none focus:border-teal"
        />
      </label>

      <div className="space-y-1">
        <div className="text-xs font-mono uppercase text-text-secondary tracking-wider">Photo of vials in cold room</div>
        <PhotoCapture onCapture={setPhoto} existingPhoto={photo} />
      </div>

      <label className="flex flex-col gap-1">
        <span className="text-xs font-mono uppercase text-text-secondary tracking-wider">
          Temp at handoff (°C)
        </span>
        <input
          type="number"
          step="0.1"
          value={tempAtHandoff}
          onChange={(e) => setTempAtHandoff(Number(e.target.value))}
          className="h-12 px-3 bg-bg-secondary border border-border text-text-primary font-display text-2xl rounded-sm focus:outline-none focus:border-teal"
        />
      </label>

      {offerSignature && (
        <div className="space-y-1">
          <div className="text-xs font-mono uppercase text-text-secondary tracking-wider">
            Recipient signature (optional)
          </div>
          <SignaturePad onChange={setSignature} />
        </div>
      )}

      <label className="flex flex-col gap-1">
        <span className="text-xs font-mono uppercase text-text-secondary tracking-wider">Notes (optional)</span>
        <textarea
          value={notes}
          onChange={(e) => setNotes(e.target.value)}
          rows={3}
          className="px-3 py-2 bg-bg-secondary border border-border text-text-primary font-body text-base rounded-sm focus:outline-none focus:border-teal"
        />
      </label>

      {err && <div className="border border-red bg-red-tint text-red text-sm p-3 font-mono rounded-sm">{err}</div>}

      <BigButton disabled={!valid || submit.isPending} onClick={() => submit.mutate()}>
        {submit.isPending ? 'Saving…' : 'Confirm handoff'}
      </BigButton>
    </div>
  );
}
