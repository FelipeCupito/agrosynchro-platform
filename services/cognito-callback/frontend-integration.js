// Ejemplo de integración en el frontend (React/Vanilla JS)

// ===================================================================
// 1. COMPONENTE DE LOGIN - Redirige a Cognito Hosted UI
// ===================================================================

function LoginButton() {
  const handleLogin = () => {
    // Obtener configuración de Cognito (estos valores vienen de Terraform outputs)
    const cognitoConfig = {
      domain: 'YOUR_COGNITO_DOMAIN',  // Ejemplo: myapp-abc123.auth.us-east-1.amazoncognito.com
      clientId: 'YOUR_CLIENT_ID',     // Ejemplo: 1a2b3c4d5e6f7g8h9i0j
      redirectUri: 'YOUR_API_GATEWAY_CALLBACK_URL',  // Ejemplo: https://abc123.execute-api.us-east-1.amazonaws.com/dev/callback
      scope: 'email openid profile'
    };
    
    // Construir URL del Hosted UI
    const loginUrl = `https://${cognitoConfig.domain}/login?` + 
      `client_id=${cognitoConfig.clientId}&` +
      `response_type=code&` +
      `scope=${encodeURIComponent(cognitoConfig.scope)}&` +
      `redirect_uri=${encodeURIComponent(cognitoConfig.redirectUri)}`;
    
    // Redirigir al Hosted UI
    window.location.href = loginUrl;
  };
  
  return <button onClick={handleLogin}>Login with Cognito</button>;
}

// ===================================================================
// 2. PROCESAR TOKENS AL CARGAR LA APP
// ===================================================================

// Este código debe ejecutarse cuando la app carga (App.js, index.js, etc.)

function processOAuthCallback() {
  // Verificar si hay un hash en la URL (tokens del callback)
  if (window.location.hash) {
    const hash = window.location.hash.substring(1);  // Remover el #
    const params = new URLSearchParams(hash);
    
    // Verificar si hay error
    const error = params.get('error');
    if (error) {
      console.error('OAuth error:', error);
      console.error('Description:', params.get('error_description'));
      alert(`Login failed: ${error}`);
      return;
    }
    
    // Extraer tokens
    const accessToken = params.get('access_token');
    const idToken = params.get('id_token');
    const refreshToken = params.get('refresh_token');
    const expiresIn = params.get('expires_in');
    
    if (accessToken && idToken) {
      
      // Guardar tokens en localStorage
      localStorage.setItem('access_token', accessToken);
      localStorage.setItem('id_token', idToken);
      if (refreshToken) {
        localStorage.setItem('refresh_token', refreshToken);
      }
      if (expiresIn) {
        const expirationTime = Date.now() + (parseInt(expiresIn) * 1000);
        localStorage.setItem('token_expiration', expirationTime.toString());
      }
      
      // Limpiar el hash de la URL
      window.history.replaceState(null, '', window.location.pathname);
      
      // Redirigir al dashboard o página principal
      window.location.href = '/dashboard';
    }
  }
}

// Llamar esta función al iniciar la app
processOAuthCallback();

// ===================================================================
// 3. HACER LLAMADAS AUTENTICADAS A LA API
// ===================================================================

async function fetchProtectedResource(endpoint) {
  // Obtener access token del localStorage
  const accessToken = localStorage.getItem('access_token');
  
  if (!accessToken) {
    console.error('No access token found. User must login.');
    window.location.href = '/login';
    return null;
  }
  
  try {
    const response = await fetch(`https://YOUR_API_GATEWAY_URL/${endpoint}`, {
      method: 'GET',
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'Content-Type': 'application/json'
      }
    });
    
    if (response.status === 401) {
      // Token expirado o inválido
      console.error('Access token expired or invalid');
      localStorage.removeItem('access_token');
      localStorage.removeItem('id_token');
      window.location.href = '/login';
      return null;
    }
    
    if (!response.ok) {
      throw new Error(`API error: ${response.status}`);
    }
    
    return await response.json();
  } catch (error) {
    console.error('Error fetching protected resource:', error);
    throw error;
  }
}

// Ejemplo de uso
async function getUserData() {
  const users = await fetchProtectedResource('users');
  console.log('Users:', users);
}

// ===================================================================
// 4. VERIFICAR SI EL USUARIO ESTÁ AUTENTICADO
// ===================================================================

function isAuthenticated() {
  const accessToken = localStorage.getItem('access_token');
  const expiration = localStorage.getItem('token_expiration');
  
  if (!accessToken) {
    return false;
  }
  
  // Verificar si el token ha expirado
  if (expiration && Date.now() > parseInt(expiration)) {
    console.log('Token has expired');
    // Aquí podrías intentar renovar el token con el refresh_token
    return false;
  }
  
  return true;
}

// ===================================================================
// 5. LOGOUT
// ===================================================================

function logout() {
  // Limpiar tokens del localStorage
  localStorage.removeItem('access_token');
  localStorage.removeItem('id_token');
  localStorage.removeItem('refresh_token');
  localStorage.removeItem('token_expiration');
  
  // Redirigir al logout de Cognito (opcional)
  const cognitoConfig = {
    domain: 'YOUR_COGNITO_DOMAIN',
    clientId: 'YOUR_CLIENT_ID',
    logoutUri: window.location.origin  // Volver al inicio del sitio
  };
  
  const logoutUrl = `https://${cognitoConfig.domain}/logout?` +
    `client_id=${cognitoConfig.clientId}&` +
    `logout_uri=${encodeURIComponent(cognitoConfig.logoutUri)}`;
  
  window.location.href = logoutUrl;
}

// ===================================================================
// 6. DECODIFICAR ID TOKEN (obtener información del usuario)
// ===================================================================

function decodeJWT(token) {
  try {
    const base64Url = token.split('.')[1];
    const base64 = base64Url.replace(/-/g, '+').replace(/_/g, '/');
    const jsonPayload = decodeURIComponent(
      atob(base64)
        .split('')
        .map(c => '%' + ('00' + c.charCodeAt(0).toString(16)).slice(-2))
        .join('')
    );
    return JSON.parse(jsonPayload);
  } catch (error) {
    console.error('Error decoding JWT:', error);
    return null;
  }
}

function getUserInfo() {
  const idToken = localStorage.getItem('id_token');
  if (!idToken) {
    return null;
  }
  
  const decoded = decodeJWT(idToken);
  console.log('User info:', decoded);
  
  return {
    email: decoded.email,
    name: decoded.name,
    sub: decoded.sub,  // User ID único en Cognito
    emailVerified: decoded.email_verified
  };
}

// ===================================================================
// 7. RENOVAR ACCESS TOKEN CON REFRESH TOKEN (OPCIONAL)
// ===================================================================

async function refreshAccessToken() {
  const refreshToken = localStorage.getItem('refresh_token');
  if (!refreshToken) {
    console.error('No refresh token available');
    return false;
  }
  
  const cognitoConfig = {
    domain: 'YOUR_COGNITO_DOMAIN',
    clientId: 'YOUR_CLIENT_ID'
  };
  
  try {
    const response = await fetch(`https://${cognitoConfig.domain}/oauth2/token`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded'
      },
      body: new URLSearchParams({
        grant_type: 'refresh_token',
        client_id: cognitoConfig.clientId,
        refresh_token: refreshToken
      })
    });
    
    if (!response.ok) {
      throw new Error('Failed to refresh token');
    }
    
    const data = await response.json();
    
    // Actualizar access token
    localStorage.setItem('access_token', data.access_token);
    if (data.id_token) {
      localStorage.setItem('id_token', data.id_token);
    }
    if (data.expires_in) {
      const expirationTime = Date.now() + (parseInt(data.expires_in) * 1000);
      localStorage.setItem('token_expiration', expirationTime.toString());
    }
    
    console.log('Access token refreshed successfully');
    return true;
  } catch (error) {
    console.error('Error refreshing token:', error);
    // Limpiar tokens y redirigir a login
    logout();
    return false;
  }
}

// ===================================================================
// 8. REACT CONTEXT PROVIDER (EJEMPLO COMPLETO)
// ===================================================================

import React, { createContext, useContext, useState, useEffect } from 'react';

const AuthContext = createContext(null);

export function AuthProvider({ children }) {
  const [user, setUser] = useState(null);
  const [loading, setLoading] = useState(true);
  
  useEffect(() => {
    // Procesar callback al cargar
    processOAuthCallback();
    
    // Verificar si hay sesión activa
    if (isAuthenticated()) {
      const userInfo = getUserInfo();
      setUser(userInfo);
    }
    
    setLoading(false);
  }, []);
  
  const login = () => {
    const cognitoConfig = {
      domain: process.env.REACT_APP_COGNITO_DOMAIN,
      clientId: process.env.REACT_APP_COGNITO_CLIENT_ID,
      redirectUri: process.env.REACT_APP_CALLBACK_URL,
      scope: 'email openid profile'
    };
    
    const loginUrl = `https://${cognitoConfig.domain}/login?` + 
      `client_id=${cognitoConfig.clientId}&` +
      `response_type=code&` +
      `scope=${encodeURIComponent(cognitoConfig.scope)}&` +
      `redirect_uri=${encodeURIComponent(cognitoConfig.redirectUri)}`;
    
    window.location.href = loginUrl;
  };
  
  const value = {
    user,
    login,
    logout,
    isAuthenticated: isAuthenticated(),
    loading
  };
  
  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error('useAuth must be used within AuthProvider');
  }
  return context;
}

// Uso en componentes:
// function MyComponent() {
//   const { user, login, logout, isAuthenticated } = useAuth();
//   
//   if (!isAuthenticated) {
//     return <button onClick={login}>Login</button>;
//   }
//   
//   return (
//     <div>
//       <p>Welcome {user?.email}</p>
//       <button onClick={logout}>Logout</button>
//     </div>
//   );
// }
