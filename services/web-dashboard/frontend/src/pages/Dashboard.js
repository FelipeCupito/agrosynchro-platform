import React, { useState } from "react";
import { getUsers, getSensorData, getParameters } from "../services/api";
import {
  BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer
} from "recharts";

const Dashboard = () => {
  const [email, setEmail] = useState("nicotordomar@gmail.com");
  const [user, setUser] = useState(null);
  const [avgData, setAvgData] = useState([]);
  const [alarmsData, setAlarmsData] = useState([]);
  const [parameters, setParameters] = useState(null);

  const handleSubmit = async (e) => {
    e.preventDefault();
    const usersRes = await getUsers();
    const foundUser = usersRes.data.find((u) => u.email === email);
    if (!foundUser) {
      alert("Usuario no encontrado");
      return;
    }
    setUser(foundUser);

    // --- Traer parámetros ---
    const paramRes = await getParameters(foundUser.id);
    let params = null;
    if (paramRes.data.length > 0) {
      params = paramRes.data[0].parameters;
      setParameters(params);
    }

    // --- Traer datos de sensores ---
    const sensorRes = await getSensorData(foundUser.id);
    const sensorData = sensorRes.data;

    // --- Promedios por medida ---
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

    // --- Alarmas por hora ---
    const alarms = {};
    sensorData.forEach((d) => {
      let isAlarm = false;

      if (params) {
        const measureKey = d.measure.toLowerCase().replace(" ", "_"); // ej: "soil moisture" -> "soil_moisture"
        const paramDef = params[measureKey];

        if (paramDef) {
          if (d.value < paramDef.min || d.value > paramDef.max) {
            isAlarm = true;
          }
        }
      }

      if (isAlarm) {
        const hour = d.timestamp.slice(0, 13); // yyyy-mm-ddThh
        alarms[hour] = (alarms[hour] || 0) + 1;
      }
    });

    const alarmsArr = Object.keys(alarms).map((hour) => ({
      hour,
      count: alarms[hour],
    }));

    setAlarmsData(alarmsArr);
  };

  return (
    <div style={{ padding: "2rem" }}>
      <h1>Agrosynchro Dashboard</h1>

      <form onSubmit={handleSubmit}>
        <input
          type="email"
          placeholder="Ingresá tu email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
        />
        <button type="submit">Buscar</button>
      </form>

      {user && (
        <>
          <h2>Parámetros configurados</h2>
          {parameters ? (
            <ul>
              <li><b>Temperatura:</b> {parameters.temperature.min} - {parameters.temperature.max}</li>
              <li><b>Humedad:</b> {parameters.humidity.min} - {parameters.humidity.max}</li>
              <li><b>Humedad del suelo:</b> {parameters.soil_moisture.min} - {parameters.soil_moisture.max}</li>
            </ul>
          ) : (
            <p>No hay parámetros configurados</p>
          )}

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
    </div>
  );
};

export default Dashboard;
