import React from 'react';
import ReactDOM from 'react-dom/client';
import './styles.css';
import App from './App';
import { processOAuthCallback } from './auth';

// Procesar tokens del callback (si vienen en el hash) antes de renderizar la app
try {
  processOAuthCallback();
} catch (e) {
  // no bloquear render en caso de error
}

const root = ReactDOM.createRoot(document.getElementById('root'));
root.render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);