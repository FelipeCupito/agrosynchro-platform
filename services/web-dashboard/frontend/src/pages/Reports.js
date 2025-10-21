import React, { useEffect, useState } from "react";
import { getReports, postReport } from "../services/api";

const Reports = ({ userId, setUserId }) => {
  const [reports, setReports] = useState([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  // Cargar reportes al montar

  useEffect(() => {
    fetchReports();
  }, [userId]);

  const fetchReports = async () => {
    setLoading(true);
    setError("");
    try {
      const res = await getReports(userId);
      setReports(res.data.reports || []);
    } catch (err) {
      setError("Error al obtener reportes");
    }
    setLoading(false);
  };

  const handleGetTodayReport = async () => {
    setError("");
    const today = new Date().toISOString().slice(0, 10);
    try {
      await postReport({ userid: userId, date: today });
      await fetchReports();
    } catch (err) {
      setError("Error al obtener el reporte de hoy");
    }
  };

  return (
    <div style={{ padding: "2rem" }}>
      <h1>Reportes</h1>
      <div style={{ marginBottom: "1rem" }}>
        <input
          type="text"
          placeholder="User ID"
          value={userId}
          onChange={e => setUserId(e.target.value)}
          disabled={!!userId}
        />
        <button onClick={handleGetTodayReport} disabled={!userId}>
          Obtener reporte de hoy
        </button>
      </div>
      {loading ? <p>Cargando...</p> : null}
      {error ? <p style={{ color: "red" }}>{error}</p> : null}
      <table border="1" cellPadding="5" style={{ borderCollapse: "collapse", width: "100%" }}>
        <thead>
          <tr>
            <th>Fecha</th>
            <th>User ID</th>
            <th>Reporte</th>
          </tr>
        </thead>
        <tbody>
          {reports.map((r, idx) => (
            <tr key={idx}>
              <td>{r.date}</td>
              <td>{r.userid}</td>
              <td>{r.report}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
};

export default Reports;
