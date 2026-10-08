import React from 'react';
import { createRoot } from 'react-dom/client';
import App from './App';
import PublicDownloads from './PublicDownloads';
import './styles.css';
createRoot(document.getElementById('root')!).render(<React.StrictMode>{location.pathname.replace(/\/$/, '') === '/downloads' ? <PublicDownloads/> : <App/>}</React.StrictMode>);
