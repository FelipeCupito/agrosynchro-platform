import React from "react";

import Dashboard from "./pages/Dashboard";
import Reports from "./pages/Reports";
import { login, logout, processOAuthCallback, isAuthenticated, getUserInfo } from "./auth";


function App() {
  const [tab, setTab] = React.useState("dashboard");
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

      console.log('👤 Syncing user to DB:', userInfo);

      // Llama a POST /users para crear/actualizar el usuario en la BD
      const apiUrl = window.ENV?.API_URL || 'https://a0ptztcgc8.execute-api.us-east-1.amazonaws.com/aws';
      const response = await fetch(`${apiUrl}/users`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          mail: userInfo.email,
        }),
      });

      if (response.ok) {
        const data = await response.json();
        console.log('✅ User synced successfully:', data);
        setUserId(userInfo.sub); // Usa el cognito_sub como userId
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
      <div style={{ padding: "2rem" }}>
        <h1>Agrosynchro</h1>
        <p>Para continuar, iniciá sesión con Cognito.</p>
        <button onClick={login}>Login</button>
      </div>
    );
  }

  return (
    <div>
      <nav style={{ marginBottom: "2rem" }}>
        <button onClick={() => setTab("dashboard")}>Dashboard</button>
        <button onClick={() => setTab("reports")}>Reportes</button>
        <span style={{ marginLeft: 16 }} />
        <button onClick={logout}>Logout</button>
      </nav>
      {tab === "dashboard" && <Dashboard setUserId={setUserId} />}
      {tab === "reports" && <Reports userId={userId} setUserId={setUserId} />}
    </div>
  );
}

export default App;
