import React, { useEffect, useState } from "react";
import { getSensorData, getParameters, createParameters } from "../services/api";
import {
  BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer
} from "recharts";

const Dashboard = ({ userId }) => {
  const [loaded, setLoaded] = useState(false);
  const [avgData, setAvgData] = useState([]);
  const [alarmsData, setAlarmsData] = useState([]);
  const [parameters, setParameters] = useState(null);

  // --- Crear usuario ---
  const [tempMin, setTempMin] = useState("");
  const [tempMax, setTempMax] = useState("");
  const [humMin, setHumMin] = useState("");
  const [humMax, setHumMax] = useState("");
  const [soilMin, setSoilMin] = useState("");
  const [soilMax, setSoilMax] = useState("");
  const [alarmEvents, setAlarmEvents] = useState([]); // nueva lista de alarmas

  // Cargar datos y parámetros del usuario logueado
  useEffect(() => {
    if (!userId) return;
    const load = async () => {
      try {
        // 1) Obtener parámetros
        const paramRes = await getParameters(userId);
        let params = null;
        const paramArr = paramRes?.data?.data || paramRes?.data || [];
        if (Array.isArray(paramArr) && paramArr.length > 0) {
          // Cuando parameters_get devuelve "data: [{...}]"
          const p = paramArr[0];
          params = {
            temperature: { min: p.min_temperature, max: p.max_temperature },
            humidity: { min: p.min_humidity, max: p.max_humidity },
            soil_moisture: { min: p.min_soil_moisture, max: p.max_soil_moisture }
          };
        }
        setParameters(params);

        // 2) Obtener datos de sensores
        const sensorRes = await getSensorData(userId);
        const sensorData = sensorRes?.data?.data || [];

        // Promedios por medida
        const grouped = {};
        sensorData.forEach((d) => {
          if (!grouped[d.measure]) grouped[d.measure] = [];
          grouped[d.measure].push(d.value);
        });
        const averages = Object.keys(grouped).map((m) => ({
          measure: m,
          avg: grouped[m].reduce((a, b) => a + b, 0) / grouped[m].length,
        }));
        setAvgData(averages);

        // Alarmas por hora
        const alarms = {};
        const alarmList = [];
        sensorData.forEach((d) => {
          let isAlarm = false;
          if (params) {
            const measureKey = d.measure.toLowerCase().replace(" ", "_");
            const paramDef = params[measureKey];
            if (paramDef) {
              if (d.value < paramDef.min || d.value > paramDef.max) isAlarm = true;
            }
          }
          if (isAlarm) {
            const hour = String(d.timestamp).slice(0, 13);
            alarms[hour] = (alarms[hour] || 0) + 1;
            alarmList.push({ timestamp: d.timestamp, measure: d.measure, value: d.value });
          }
        });
        const alarmsArr = Object.keys(alarms).map((hour) => ({ hour, count: alarms[hour] }));
        setAlarmsData(alarmsArr);
        setAlarmEvents(alarmList);

        setLoaded(true);
      } catch (err) {
        console.error(err);
        setLoaded(true);
      }
    };
    load();
  }, [userId]);

  const handleSaveParameters = async (e) => {
    e.preventDefault();
    if (!userId) return alert("No hay usuario logueado");
    if (!tempMin || !tempMax || !humMin || !humMax || !soilMin || !soilMax) {
      return alert("Completá todos los campos de alarmas");
    }
    try {
      const customParams = {
        temperature: { min: parseFloat(tempMin), max: parseFloat(tempMax) },
        humidity: { min: parseFloat(humMin), max: parseFloat(humMax) },
        soil_moisture: { min: parseFloat(soilMin), max: parseFloat(soilMax) }
      };
      await createParameters(userId, customParams);
      setParameters(customParams);
      alert("Alarmas guardadas");
    } catch (err) {
      console.error(err);
      alert("Error al guardar alarmas");
    }
  };

  return (
    <div style={{ padding: "2rem" }}>
      <h1>Agrosynchro Dashboard</h1>
      {!userId && <p>Iniciá sesión para ver tus datos.</p>}

      {/* Mostrar formulario de alarmas SOLO si el usuario no tiene parámetros */}
      {userId && !parameters && (
        <div style={{ marginBottom: "2rem" }}>
          <h2>Configurar alarmas</h2>
          <form onSubmit={handleSaveParameters}>
            <b>Temperatura (°C):</b><br />
            <input type="number" placeholder="Min" value={tempMin} onChange={e => setTempMin(e.target.value)} />
            <input type="number" placeholder="Max" value={tempMax} onChange={e => setTempMax(e.target.value)} /><br />

            <b>Humedad (%):</b><br />
            <input type="number" placeholder="Min" value={humMin} onChange={e => setHumMin(e.target.value)} />
            <input type="number" placeholder="Max" value={humMax} onChange={e => setHumMax(e.target.value)} /><br />

            <b>Humedad del suelo (%):</b><br />
            <input type="number" placeholder="Min" value={soilMin} onChange={e => setSoilMin(e.target.value)} />
            <input type="number" placeholder="Max" value={soilMax} onChange={e => setSoilMax(e.target.value)} /><br />

            <button type="submit">Guardar alarmas</button>
          </form>
        </div>
      )}

      {/* --- Dashboards solo al buscar usuario --- */}
      {userId && loaded && (
        <>
          <h2>Promedios de sensores</h2>
          <ResponsiveContainer width="100%" height={300}>
            <BarChart data={avgData}>
              <CartesianGrid strokeDasharray="3 3" />
              <XAxis dataKey="measure" />
              <YAxis />
              <Tooltip />
              <Legend />
              <Bar dataKey="avg" fill="#82ca9d" />
            </BarChart>
          </ResponsiveContainer>

          <h2>Alarmas por hora</h2>
          <ResponsiveContainer width="100%" height={300}>
            <BarChart data={alarmsData}>
              <CartesianGrid strokeDasharray="3 3" />
              <XAxis dataKey="hour" />
              <YAxis />
              <Tooltip />
              <Legend />
              <Bar dataKey="count" fill="#ff4d4d" />
            </BarChart>
          </ResponsiveContainer>
        </>
      )}

             <h2>Tabla de alarmas</h2>
          {alarmEvents.length > 0 ? (
            <table border="1" cellPadding="5" style={{ borderCollapse: "collapse", width: "100%" }}>
              <thead>
                <tr>
                  <th>Timestamp</th>
                  <th>Medida</th>
                  <th>Valor</th>
                </tr>
              </thead>
              <tbody>
                {alarmEvents.map((a, idx) => (
                  <tr key={idx}>
                    <td>{a.timestamp}</td>
                    <td>{a.measure}</td>
                    <td>{a.value}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          ) : <p>No se registraron alarmas.</p>}

    </div>
  );
};

export default Dashboard;
