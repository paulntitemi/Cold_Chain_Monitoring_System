import { useEffect } from 'react';
import { BrowserRouter, Routes, Route, Navigate, useNavigate } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { Toaster } from 'react-hot-toast';
import { useAuthStore } from '@/store/authStore';
import { useAlertStore } from '@/store/alertStore';
import { LoginScreen } from '@/screens/LoginScreen';
import { AssignmentsScreen } from '@/screens/AssignmentsScreen';
import { ManifestScreen } from '@/screens/ManifestScreen';
import { LiveTripScreen } from '@/screens/LiveTripScreen';
import { AlertScreen } from '@/screens/AlertScreen';
import { DiversionNavScreen } from '@/screens/DiversionNavScreen';
import { ColdStoreHandoffScreen } from '@/screens/ColdStoreHandoffScreen';
import { DestinationHandoffScreen } from '@/screens/DestinationHandoffScreen';
import { TripSummaryScreen } from '@/screens/TripSummaryScreen';
import { ProfileScreen } from '@/screens/ProfileScreen';

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 2_000,
      retry: 1,
      refetchOnWindowFocus: false,
    },
  },
});

function RequireAuth({ children }: { children: React.ReactNode }) {
  const loggedIn = useAuthStore((s) => s.loggedIn);
  if (!loggedIn) return <Navigate to="/login" replace />;
  return <>{children}</>;
}

/**
 * Side-effect component: when an active alert lands in the alert store
 * *while the user is anywhere else in the app*, route them to /alert.
 */
function AlertRouter() {
  const navigate = useNavigate();
  const activeAlert = useAlertStore((s) => s.activeAlert);

  useEffect(() => {
    if (!activeAlert) return;
    if (window.location.pathname === '/alert') return;
    navigate('/alert');
  }, [activeAlert, navigate]);

  return null;
}

export default function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <BrowserRouter>
        <AlertRouter />
        <Routes>
          <Route path="/login" element={<LoginScreen />} />
          <Route
            path="/assignments"
            element={
              <RequireAuth>
                <AssignmentsScreen />
              </RequireAuth>
            }
          />
          <Route
            path="/manifest/:shipmentId"
            element={
              <RequireAuth>
                <ManifestScreen />
              </RequireAuth>
            }
          />
          <Route
            path="/trip"
            element={
              <RequireAuth>
                <LiveTripScreen />
              </RequireAuth>
            }
          />
          <Route
            path="/alert"
            element={
              <RequireAuth>
                <AlertScreen />
              </RequireAuth>
            }
          />
          <Route
            path="/divert/:shipmentId"
            element={
              <RequireAuth>
                <DiversionNavScreen />
              </RequireAuth>
            }
          />
          <Route
            path="/handoff/cold-store/:shipmentId"
            element={
              <RequireAuth>
                <ColdStoreHandoffScreen />
              </RequireAuth>
            }
          />
          <Route
            path="/handoff/destination/:shipmentId"
            element={
              <RequireAuth>
                <DestinationHandoffScreen />
              </RequireAuth>
            }
          />
          <Route
            path="/summary/:shipmentId"
            element={
              <RequireAuth>
                <TripSummaryScreen />
              </RequireAuth>
            }
          />
          <Route
            path="/profile"
            element={
              <RequireAuth>
                <ProfileScreen />
              </RequireAuth>
            }
          />
          <Route path="/" element={<Navigate to="/login" replace />} />
          <Route path="*" element={<Navigate to="/login" replace />} />
        </Routes>
        <Toaster
          position="top-center"
          toastOptions={{
            style: {
              background: '#0D1420',
              color: '#E2E8F0',
              border: '1px solid #1E2D45',
              fontFamily: 'IBM Plex Sans',
            },
          }}
        />
      </BrowserRouter>
    </QueryClientProvider>
  );
}
