import React from 'react';
import ReactDOM from 'react-dom/client';
import { Workbox } from 'workbox-window';
import App from './App';
import { drainQueue } from './lib/offlineQueue';
import { apiClient } from './lib/apiClient';
import './index.css';

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);

if ('serviceWorker' in navigator && import.meta.env.PROD) {
  const wb = new Workbox('/service-worker.js', { scope: '/' });
  wb.addEventListener('waiting', () => {
    void wb.messageSW({ type: 'SKIP_WAITING' });
  });
  void wb.register();
}

// Drain the IndexedDB write queue whenever the browser comes back online.
window.addEventListener('online', () => {
  void drainQueue(async (item) => {
    await apiClient.request({
      method: item.method.toLowerCase(),
      url: item.path,
      data: item.body,
    });
  });
});
