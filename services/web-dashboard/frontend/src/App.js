import React from "react";
import { BarChart3, FileText, LogIn, LogOut, Leaf } from "lucide-react";

import Dashboard from "./pages/Dashboard";
import Reports from "./pages/Reports";
import { login, logout, processOAuthCallback, isAuthenticated, getUserInfo } from "./auth";


function App() {
  const [tab, setTab] = React.useState("dashboard");
  // userId: corresponde al userid de la BD (entero), no al cognito_sub
  const [userId, setUserId] = React.useState("");
  const [auth, setAuth] = React.useState(isAuthenticated());
  const [userSynced, setUserSynced] = React.useState(false);

  React.useEffect(() => {
    // Procesa tokens si vienen en el hash después del callback
    processOAuthCallback();
    setAuth(isAuthenticated());
  }, []);

  React.useEffect(() => {
    // Sincronizar usuario con la BD después del login
    if (auth && !userSynced) {
      syncUserToDB();
    }
  }, [auth, userSynced]);

  const syncUserToDB = async () => {
    try {
      const userInfo = getUserInfo();
      if (!userInfo) {
        console.error('No user info available');
        return;
      }

      

      // Llama a POST /users para crear/actualizar el usuario en la BD
      const apiUrl = window.ENV?.API_URL || 'http://localhost:3000';
      const response = await fetch(`${apiUrl}/users`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          // Enviar ambos para asegurar upsert y obtener siempre el userid
          email: userInfo.email,
          cognito_sub: userInfo.sub,
          name: userInfo.email?.split('@')[0] || 'user'
        }),
      });

      if (response.ok) {
        const data = await response.json();
        
        // La lambda retorna "userid" cuando recibe cognito_sub
        if (data.userid) {
          setUserId(String(data.userid));
        } else if (data.data && data.data.userid) {
          setUserId(String(data.data.userid));
        } else {
          console.warn('No userid in response, intentando fallback por GET /users');
          // Fallback opcional: dejar userId vacío, la UI mostrará errores si falta
        }
        setUserSynced(true);
      } else {
        console.error('❌ Error syncing user:', await response.text());
      }
    } catch (error) {
      console.error('❌ Error syncing user to DB:', error);
    }
  };

  if (!auth) {
    return (
      <div className="login-container">
        <div className="card login-card">
          <div className="card-content">
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', marginBottom: '2rem' }}>
              <Leaf size={40} style={{ color: 'var(--primary)', marginRight: '0.5rem' }} />
              <h1 className="login-title">Agrosynchro</h1>
            </div>
            <p className="login-subtitle">
              Monitoreo inteligente de cultivos para una agricultura más eficiente
            </p>
            <p style={{ marginBottom: '2rem', color: 'var(--text-secondary)' }}>
              Para continuar, iniciá sesión con tu cuenta
            </p>
            <button className="btn btn-primary btn-lg" onClick={login} style={{ width: '100%' }}>
              <LogIn size={20} />
              Iniciar Sesión
            </button>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="app-container">
      <nav className="navbar">
        <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
          <Leaf size={28} style={{ color: 'var(--primary)' }} />
          <span className="navbar-brand">Agrosynchro</span>
        </div>
        
        <div className="navbar-nav">
          <button 
            className={`btn ${tab === "dashboard" ? "btn-primary" : "btn-ghost"}`}
            onClick={() => setTab("dashboard")}
          >
            <BarChart3 size={18} />
            Dashboard
          </button>
          <button 
            className={`btn ${tab === "reports" ? "btn-primary" : "btn-ghost"}`}
            onClick={() => setTab("reports")}
          >
            <FileText size={18} />
            Reportes
          </button>
        </div>

        <div className="navbar-actions">
          <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: '0.25rem' }}>
            <span style={{ fontSize: 'var(--font-size-sm)', color: 'var(--text-primary)', fontWeight: '500' }}>
              {getUserInfo()?.email || 'Usuario'}
            </span>
            {userId && (
              <span style={{ 
                fontSize: 'var(--font-size-xs)', 
                color: 'var(--text-secondary)',
                background: 'var(--light-gray)',
                padding: '0.125rem 0.375rem',
                borderRadius: 'var(--border-radius-sm)',
                fontWeight: '500'
              }}>
                ID: {userId}
              </span>
            )}
          </div>
          <button className="btn btn-secondary" onClick={logout}>
            <LogOut size={16} />
            Salir
          </button>
        </div>
      </nav>

      <main className="main-content">
        {tab === "dashboard" && <Dashboard userId={userId} />}
        {tab === "reports" && <Reports userId={userId} />}
      </main>
    </div>
  );
}

export default App;
