// Auth helpers for Cognito Hosted UI + Lambda callback flow

// Expected env vars injected at build or via public env.js:
// - window.ENV.COGNITO_DOMAIN           e.g. myapp-xyz.auth.us-east-1.amazoncognito.com
// - window.ENV.COGNITO_CLIENT_ID        e.g. 1a2b3c4d5e6f7g8h9i0j
// - window.ENV.CALLBACK_URL             e.g. https://{api-id}.execute-api.{region}.amazonaws.com/{stage}/callback
// - window.ENV.API_URL                  e.g. https://{api-id}.execute-api.{region}.amazonaws.com/{stage}

const getEnv = () => (typeof window !== 'undefined' ? (window.ENV || {}) : {});

export function login() {
  const env = getEnv();
  const domain = env.COGNITO_DOMAIN;
  const clientId = env.COGNITO_CLIENT_ID;
  const redirectUri = env.CALLBACK_URL;
  const scope = 'email openid profile';

  if (!domain || !clientId || !redirectUri) {
    alert('Faltan variables de entorno de Cognito (COGNITO_DOMAIN, COGNITO_CLIENT_ID, CALLBACK_URL).');
    return;
  }

  const loginUrl = `https://${domain}/login?client_id=${encodeURIComponent(clientId)}&response_type=code&scope=${encodeURIComponent(scope)}&redirect_uri=${encodeURIComponent(redirectUri)}`;
  window.location.href = loginUrl;
}

export function processOAuthCallback() {
  // Expect tokens in the URL hash after Lambda redirect: #access_token=...&id_token=...&refresh_token=...
  if (typeof window === 'undefined') return;
  
  console.log('🔍 Processing OAuth callback...');
  console.log('Current URL:', window.location.href);
  console.log('Hash:', window.location.hash);
  
  const hash = window.location.hash?.startsWith('#') ? window.location.hash.substring(1) : '';
  if (!hash) {
    console.log('⚠️ No hash found in URL, skipping token processing');
    return;
  }

  const params = new URLSearchParams(hash);
  console.log('📦 Hash params:', Array.from(params.entries()));
  
  const error = params.get('error');
  if (error) {
    console.error('❌ OAuth error:', error, params.get('error_description'));
    // Clear hash to avoid re-processing
    window.history.replaceState(null, '', window.location.pathname);
    return;
  }

  const accessToken = params.get('access_token');
  const idToken = params.get('id_token');
  const refreshToken = params.get('refresh_token');
  const expiresIn = params.get('expires_in');

  if (accessToken) {
    console.log('✅ Access token received, saving to localStorage');
    localStorage.setItem('access_token', accessToken);
  } else {
    console.warn('⚠️ No access_token in hash');
  }
  
  if (idToken) {
    console.log('✅ ID token received, saving to localStorage');
    localStorage.setItem('id_token', idToken);
  }
  if (refreshToken) {
    localStorage.setItem('refresh_token', refreshToken);
  }
  if (expiresIn) {
    const expirationTime = Date.now() + parseInt(expiresIn, 10) * 1000;
    localStorage.setItem('token_expiration', String(expirationTime));
  }

  console.log('✅ Tokens saved, clearing hash from URL');
  // Clear hash from URL
  window.history.replaceState(null, '', window.location.pathname);
}

export function isAuthenticated() {
  const token = localStorage.getItem('access_token');
  const exp = localStorage.getItem('token_expiration');
  if (!token) return false;
  if (exp && Date.now() > Number(exp)) {
    return false;
  }
  return true;
}

export function getAccessToken() {
  return localStorage.getItem('access_token');
}

export function getIdToken() {
  return localStorage.getItem('id_token');
}

// Decodifica el JWT (sin verificar firma - solo para leer claims en el frontend)
export function decodeJWT(token) {
  if (!token) return null;
  try {
    const base64Url = token.split('.')[1];
    const base64 = base64Url.replace(/-/g, '+').replace(/_/g, '/');
    const jsonPayload = decodeURIComponent(
      atob(base64)
        .split('')
        .map((c) => '%' + ('00' + c.charCodeAt(0).toString(16)).slice(-2))
        .join('')
    );
    return JSON.parse(jsonPayload);
  } catch (error) {
    console.error('Error decoding JWT:', error);
    return null;
  }
}

// Obtiene la información del usuario desde el id_token
export function getUserInfo() {
  const idToken = getIdToken();
  if (!idToken) return null;
  
  const decoded = decodeJWT(idToken);
  if (!decoded) return null;
  
  return {
    sub: decoded.sub,              // ID único de Cognito
    email: decoded.email,
    email_verified: decoded.email_verified,
    // Otros atributos según lo configurado en Cognito
  };
}

export function logout() {
  localStorage.removeItem('access_token');
  localStorage.removeItem('id_token');
  localStorage.removeItem('refresh_token');
  localStorage.removeItem('token_expiration');

  // Redirect to Cognito logout only for localhost (HTTPS required for production)
  const env = getEnv();
  const isLocalhost = window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1';
  
  if (env.COGNITO_DOMAIN && env.COGNITO_CLIENT_ID && isLocalhost) {
    // Solo redirigir a Cognito logout en localhost (tiene HTTPS exception)
    const logoutUri = window.location.origin + '/';
    const url = `https://${env.COGNITO_DOMAIN}/logout?client_id=${encodeURIComponent(env.COGNITO_CLIENT_ID)}&logout_uri=${encodeURIComponent(logoutUri)}`;
    window.location.href = url;
  } else {
    // Para producción (S3 website HTTP), solo limpiar tokens localmente y recargar
    window.location.href = '/';
  }
}
