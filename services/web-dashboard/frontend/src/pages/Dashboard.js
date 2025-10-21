import React, { useState } from "react";
import {
  getUsers, getSensorData, getParameters, createUser, createParameters
} from "../services/api";
import {
  BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer
} from "recharts";

const Dashboard = ({ setUserId }) => {
  const [email, setEmail] = useState("");
  const [user, setUser] = useState(null);
  const [avgData, setAvgData] = useState([]);
  const [alarmsData, setAlarmsData] = useState([]);
  const [parameters, setParameters] = useState(null);

  // --- Crear usuario ---
  const [newEmail, setNewEmail] = useState("");
  const [tempMin, setTempMin] = useState("");
  const [tempMax, setTempMax] = useState("");
  const [humMin, setHumMin] = useState("");
  const [humMax, setHumMax] = useState("");
  const [soilMin, setSoilMin] = useState("");
  const [soilMax, setSoilMax] = useState("");
  const [newUserCreated, setNewUserCreated] = useState(false);
  const [alarmEvents, setAlarmEvents] = useState([]); // nueva lista de alarmas


  // --- Buscar usuario existente ---
  const handleSubmit = async (e) => {
    e.preventDefault();
    try {
      const usersRes = await getUsers();
      const foundUser = usersRes.data.data.find((u) => u.email === email);
      if (!foundUser) {
        alert("Usuario no encontrado");
        return;
      }
  setUser(foundUser);
  setUserId(foundUser.id);

      // Parámetros
      const paramRes = await getParameters(foundUser.id);
      let params = null;
      if (paramRes.data.length > 0) {
        params = paramRes.data[0].parameters;
        setParameters(params);
      }

      // Sensor data
      const sensorRes = await getSensorData(foundUser.id);
      const sensorData = sensorRes.data.data;

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
          const hour = d.timestamp.slice(0, 13);
          alarms[hour] = (alarms[hour] || 0) + 1;
          alarmList.push({
            timestamp: d.timestamp,
            measure: d.measure,
            value: d.value
          });

        }
      });
      const alarmsArr = Object.keys(alarms).map((hour) => ({
        hour,
        count: alarms[hour],
      }));
      setAlarmsData(alarmsArr);
      setAlarmEvents(alarmList);


    } catch (err) {
      console.error(err);
      alert("Error al buscar usuario");
    }
  };

  // --- Crear nuevo usuario con parámetros personalizados ---
  const handleCreateUser = async (e) => {
    e.preventDefault();

    if (!newEmail || !tempMin || !tempMax || !humMin || !humMax || !soilMin || !soilMax) {
      return alert("Completá todos los campos");
    }

    try {
      // 1️⃣ Crear usuario
      const userRes = await createUser(newEmail);
      const userId = userRes.data.userid;

      // 2️⃣ Crear parámetros personalizados
      const customParams = {
        temperature: { min: parseFloat(tempMin), max: parseFloat(tempMax) },
        humidity: { min: parseFloat(humMin), max: parseFloat(humMax) },
        soil_moisture: { min: parseFloat(soilMin), max: parseFloat(soilMax) }
      };
      await createParameters(userId, customParams);

      alert(`Usuario creado con ID: ${userId}`);
      setNewUserCreated(true);

      // Limpiar formulario
      setNewEmail("");
      setTempMin(""); setTempMax("");
      setHumMin(""); setHumMax("");
      setSoilMin(""); setSoilMax("");

    } catch (err) {
      console.error(err);
      alert("Error al crear usuario");
    }
  };

  return (
    <div style={{ padding: "2rem" }}>
      <h1>Agrosynchro Dashboard</h1>

      {/* --- Buscar usuario --- */}
      <form onSubmit={handleSubmit} style={{ marginBottom: "2rem" }}>
        <input
          type="email"
          placeholder="Ingresá tu email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
        />
        <button type="submit">Buscar</button>
      </form>

      {/* --- Crear nuevo usuario --- */}
      <h2>Crear nuevo usuario</h2>
      <form onSubmit={handleCreateUser} style={{ marginBottom: "2rem" }}>
        <input type="email" placeholder="Email" value={newEmail} onChange={e => setNewEmail(e.target.value)} /><br />

        <b>Temperatura (°C):</b><br />
        <input type="number" placeholder="Min" value={tempMin} onChange={e => setTempMin(e.target.value)} />
        <input type="number" placeholder="Max" value={tempMax} onChange={e => setTempMax(e.target.value)} /><br />

        <b>Humedad (%):</b><br />
        <input type="number" placeholder="Min" value={humMin} onChange={e => setHumMin(e.target.value)} />
        <input type="number" placeholder="Max" value={humMax} onChange={e => setHumMax(e.target.value)} /><br />

        <b>Humedad del suelo (%):</b><br />
        <input type="number" placeholder="Min" value={soilMin} onChange={e => setSoilMin(e.target.value)} />
        <input type="number" placeholder="Max" value={soilMax} onChange={e => setSoilMax(e.target.value)} /><br />

        <button type="submit">Crear usuario</button>
      </form>
      {newUserCreated && <p style={{ color: "green" }}>Usuario creado exitosamente!</p>}

      {/* --- Dashboards solo al buscar usuario --- */}
      {user && (
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
