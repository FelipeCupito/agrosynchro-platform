import React, { useEffect, useState } from "react";
import { getSensorData, getParameters, createParameters } from "../services/api";
import {
  BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer
} from "recharts";
import { 
  Thermometer, 
  Droplets, 
  Sprout, 
  AlertTriangle, 
  Settings, 
  TrendingUp,
  Clock,
  CheckCircle2
} from "lucide-react";

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
            // Mapeo correcto de medidas a parámetros
            const measureMap = {
              'TEMP': 'temperature',
              'HUM': 'humidity', 
              'SOIL': 'soil_moisture'
            };
            
            const measureKey = measureMap[d.measure] || d.measure.toLowerCase().replace(" ", "_");
            const paramDef = params[measureKey];
            
            
            if (paramDef) {
              if (d.value < paramDef.min || d.value > paramDef.max) {
                isAlarm = true;
                console.log("🚨 ALARM DETECTED:", d.measure, d.value, "outside range", paramDef.min, "-", paramDef.max);
              }
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

  // Helper para obtener icono por tipo de medición
  const getMeasureIcon = (measure) => {
    switch(measure) {
      case 'TEMP': return <Thermometer size={20} />;
      case 'HUM': return <Droplets size={20} />;
      case 'SOIL': return <Sprout size={20} />;
      default: return <TrendingUp size={20} />;
    }
  };

  // Helper para obtener color por tipo de medición
  const getMeasureColor = (measure) => {
    switch(measure) {
      case 'TEMP': return '#e67e22';
      case 'HUM': return '#3498db';
      case 'SOIL': return '#27ae60';
      default: return '#95a5a6';
    }
  };

  return (
    <div>
      {/* Header */}
      <div style={{ marginBottom: '2rem' }}>
        <h1 style={{ fontSize: 'var(--font-size-3xl)', fontWeight: '700', marginBottom: '0.5rem', color: 'var(--text-primary)' }}>
          Dashboard Agrosynchro
        </h1>
        <p style={{ color: 'var(--text-secondary)', fontSize: 'var(--font-size-lg)' }}>
          Monitoreo en tiempo real de tu cultivo
        </p>
      </div>

      {!userId && (
        <div className="card">
          <div className="card-content text-center">
            <AlertTriangle size={48} style={{ color: 'var(--warning)', marginBottom: '1rem' }} />
            <p style={{ fontSize: 'var(--font-size-lg)', marginBottom: '0' }}>
              Iniciá sesión para ver tus datos de monitoreo
            </p>
          </div>
        </div>
      )}

      {/* Configuración de parámetros */}
      {userId && !parameters && (
        <div className="card mb-8">
          <div className="card-header">
            <h2 className="card-title">
              <Settings size={24} style={{ marginRight: '0.5rem', verticalAlign: 'middle' }} />
              Configuración Inicial
            </h2>
            <p className="card-description">
              Establecé los rangos de alarma para monitorear tu cultivo
            </p>
          </div>
          <div className="card-content">
            <form onSubmit={handleSaveParameters}>
              <div className="grid grid-3">
                {/* Temperatura */}
                <div className="form-group">
                  <label className="form-label">
                    <Thermometer size={16} style={{ marginRight: '0.5rem', verticalAlign: 'middle' }} />
                    Temperatura (°C)
                  </label>
                  <div className="form-row">
                    <input 
                      className="form-input" 
                      type="number" 
                      placeholder="Mínima" 
                      value={tempMin} 
                      onChange={e => setTempMin(e.target.value)} 
                    />
                    <input 
                      className="form-input" 
                      type="number" 
                      placeholder="Máxima" 
                      value={tempMax} 
                      onChange={e => setTempMax(e.target.value)} 
                    />
                  </div>
                </div>

                {/* Humedad */}
                <div className="form-group">
                  <label className="form-label">
                    <Droplets size={16} style={{ marginRight: '0.5rem', verticalAlign: 'middle' }} />
                    Humedad (%)
                  </label>
                  <div className="form-row">
                    <input 
                      className="form-input" 
                      type="number" 
                      placeholder="Mínima" 
                      value={humMin} 
                      onChange={e => setHumMin(e.target.value)} 
                    />
                    <input 
                      className="form-input" 
                      type="number" 
                      placeholder="Máxima" 
                      value={humMax} 
                      onChange={e => setHumMax(e.target.value)} 
                    />
                  </div>
                </div>

                {/* Humedad del suelo */}
                <div className="form-group">
                  <label className="form-label">
                    <Sprout size={16} style={{ marginRight: '0.5rem', verticalAlign: 'middle' }} />
                    Humedad del Suelo (%)
                  </label>
                  <div className="form-row">
                    <input 
                      className="form-input" 
                      type="number" 
                      placeholder="Mínima" 
                      value={soilMin} 
                      onChange={e => setSoilMin(e.target.value)} 
                    />
                    <input 
                      className="form-input" 
                      type="number" 
                      placeholder="Máxima" 
                      value={soilMax} 
                      onChange={e => setSoilMax(e.target.value)} 
                    />
                  </div>
                </div>
              </div>
              
              <div className="card-footer" style={{ marginTop: '1.5rem', padding: '0', border: 'none', background: 'transparent' }}>
                <button type="submit" className="btn btn-primary">
                  <CheckCircle2 size={16} />
                  Guardar Configuración
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Dashboard principal */}
      {userId && loaded && (
        <>
          {/* Gráfico de promedios */}
          <div className="chart-container">
            <h2 className="chart-title">
              <TrendingUp size={24} style={{ marginRight: '0.5rem', verticalAlign: 'middle' }} />
              Promedios de Sensores
            </h2>
            <ResponsiveContainer width="100%" height={300}>
              <BarChart data={avgData}>
                <CartesianGrid strokeDasharray="3 3" stroke="var(--gray)" />
                <XAxis 
                  dataKey="measure" 
                  axisLine={false}
                  tickLine={false}
                  tick={{ fill: 'var(--text-secondary)', fontSize: '12px' }}
                />
                <YAxis 
                  axisLine={false}
                  tickLine={false}
                  tick={{ fill: 'var(--text-secondary)', fontSize: '12px' }}
                />
                <Tooltip 
                  contentStyle={{
                    backgroundColor: 'var(--white)',
                    border: '1px solid var(--gray)',
                    borderRadius: 'var(--border-radius)',
                    boxShadow: 'var(--shadow)'
                  }}
                />
                <Legend />
                <Bar 
                  dataKey="avg" 
                  fill="url(#colorGradient)" 
                  radius={[4, 4, 0, 0]}
                />
                <defs>
                  <linearGradient id="colorGradient" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="0%" stopColor="var(--primary)" />
                    <stop offset="100%" stopColor="var(--primary-dark)" />
                  </linearGradient>
                </defs>
              </BarChart>
            </ResponsiveContainer>
          </div>

          {/* Gráfico de alarmas */}
          <div className="chart-container">
            <h2 className="chart-title">
              <AlertTriangle size={24} style={{ marginRight: '0.5rem', verticalAlign: 'middle', color: 'var(--error)' }} />
              Alarmas por Hora
            </h2>
            <ResponsiveContainer width="100%" height={300}>
              <BarChart data={alarmsData}>
                <CartesianGrid strokeDasharray="3 3" stroke="var(--gray)" />
                <XAxis 
                  dataKey="hour" 
                  axisLine={false}
                  tickLine={false}
                  tick={{ fill: 'var(--text-secondary)', fontSize: '12px' }}
                />
                <YAxis 
                  axisLine={false}
                  tickLine={false}
                  tick={{ fill: 'var(--text-secondary)', fontSize: '12px' }}
                />
                <Tooltip 
                  contentStyle={{
                    backgroundColor: 'var(--white)',
                    border: '1px solid var(--gray)',
                    borderRadius: 'var(--border-radius)',
                    boxShadow: 'var(--shadow)'
                  }}
                />
                <Legend />
                <Bar 
                  dataKey="count" 
                  fill="url(#errorGradient)" 
                  radius={[4, 4, 0, 0]}
                />
                <defs>
                  <linearGradient id="errorGradient" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="0%" stopColor="var(--error)" />
                    <stop offset="100%" stopColor="#c0392b" />
                  </linearGradient>
                </defs>
              </BarChart>
            </ResponsiveContainer>
          </div>

          {/* Tabla de alarmas */}
          <div className="card">
            <div className="card-header">
              <h2 className="card-title">
                <Clock size={24} style={{ marginRight: '0.5rem', verticalAlign: 'middle' }} />
                Registro de Alarmas
              </h2>
              <p className="card-description">
                Historial detallado de todas las alarmas generadas
              </p>
            </div>
            <div className="card-content" style={{ padding: '0' }}>
              {alarmEvents.length > 0 ? (
                <div className="table-container" style={{ boxShadow: 'none', border: 'none' }}>
                  <table className="table">
                    <thead>
                      <tr>
                        <th>Timestamp</th>
                        <th>Medida</th>
                        <th>Valor</th>
                        <th>Estado</th>
                      </tr>
                    </thead>
                    <tbody>
                      {alarmEvents.map((a, idx) => (
                        <tr key={idx}>
                          <td>{new Date(a.timestamp).toLocaleString()}</td>
                          <td>
                            <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                              <span style={{ color: getMeasureColor(a.measure) }}>
                                {getMeasureIcon(a.measure)}
                              </span>
                              {a.measure}
                            </div>
                          </td>
                          <td>
                            <span style={{ fontWeight: '600', color: 'var(--text-primary)' }}>
                              {a.value}
                            </span>
                          </td>
                          <td>
                            <span style={{ 
                              color: 'var(--error)', 
                              display: 'flex', 
                              alignItems: 'center', 
                              gap: '0.25rem',
                              fontSize: 'var(--font-size-sm)'
                            }}>
                              <AlertTriangle size={14} />
                              Fuera de rango
                            </span>
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              ) : (
                <div style={{ padding: 'var(--spacing-8)', textAlign: 'center' }}>
                  <CheckCircle2 size={48} style={{ color: 'var(--success)', marginBottom: '1rem' }} />
                  <p style={{ color: 'var(--text-secondary)', margin: '0' }}>
                    ¡Excelente! No se registraron alarmas en el período monitoreado.
                  </p>
                </div>
              )}
            </div>
          </div>
        </>
      )}

      {userId && !loaded && (
        <div className="loading">
          <div className="spinner"></div>
          Cargando datos del dashboard...
        </div>
      )}

    </div>
  );
};

export default Dashboard;
