import React from "react";

import Dashboard from "./pages/Dashboard";
import Reports from "./pages/Reports";


function App() {
  const [tab, setTab] = React.useState("dashboard");
  const [userId, setUserId] = React.useState("");
  return (
    <div>
      <nav style={{ marginBottom: "2rem" }}>
        <button onClick={() => setTab("dashboard")}>Dashboard</button>
        <button onClick={() => setTab("reports")}>Reportes</button>
      </nav>
      {tab === "dashboard" && <Dashboard setUserId={setUserId} />}
      {tab === "reports" && <Reports userId={userId} setUserId={setUserId} />}
    </div>
  );
}

export default App;
