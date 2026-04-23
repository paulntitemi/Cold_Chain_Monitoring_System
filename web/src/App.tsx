import { Navigate, Route, Routes } from 'react-router-dom';
import { Toaster } from 'react-hot-toast';
import { Sidebar } from '@/components/layout/Sidebar';
import { TopBar } from '@/components/layout/TopBar';
import { AlertsPanel } from '@/components/layout/AlertsPanel';
import { FleetOverview } from '@/views/FleetOverview';
import { BatchRegistry } from '@/views/BatchRegistry';
import { AlertHistory } from '@/views/AlertHistory';
import { ShipmentDetailView } from '@/views/ShipmentDetail';
import { ShipmentDetailPanel } from '@/components/shipments/ShipmentDetailPanel';
import { useShipments } from '@/hooks/useShipments';
import { useActiveAlerts } from '@/hooks/useAlerts';
import { useWebSocket } from '@/hooks/useWebSocket';

export default function App() {
  // Kick off polling (and WebSocket if enabled) at the top of the tree so
  // every view shares the same global stores.
  useShipments();
  useActiveAlerts();
  useWebSocket();

  return (
    <div className="flex h-full w-full bg-bg-primary">
      <Sidebar />

      <div className="flex min-w-0 flex-1 flex-col">
        <TopBar />
        <div className="flex min-h-0 flex-1">
          <main className="flex min-w-0 flex-1 flex-col overflow-hidden">
            <Routes>
              <Route path="/" element={<Navigate to="/dashboard" replace />} />
              <Route path="/dashboard" element={<FleetOverview />} />
              <Route path="/batches" element={<BatchRegistry />} />
              <Route path="/alerts" element={<AlertHistory />} />
              <Route path="/shipments/:id" element={<ShipmentDetailView />} />
              <Route
                path="*"
                element={
                  <div className="flex flex-1 items-center justify-center text-text-secondary">
                    Not found.
                  </div>
                }
              />
            </Routes>
          </main>
          <AlertsPanel />
        </div>
      </div>

      <ShipmentDetailPanel />

      <Toaster
        position="top-right"
        toastOptions={{
          style: {
            background: '#0D1420',
            color: '#E2E8F0',
            border: '1px solid #2A3F5F',
            borderRadius: 2,
            fontFamily: '"IBM Plex Sans", system-ui, sans-serif',
            fontSize: 13,
          },
          success: { iconTheme: { primary: '#10B981', secondary: '#0D1420' } },
          error: { iconTheme: { primary: '#EF4444', secondary: '#0D1420' } },
        }}
      />
    </div>
  );
}
