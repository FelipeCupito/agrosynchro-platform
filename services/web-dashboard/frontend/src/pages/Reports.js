import React, { useEffect, useState } from "react";
import { getReports, postReport } from "../services/api";
import { FileText, Download, Calendar, User, RefreshCw, AlertCircle, CheckCircle2, Eye, Maximize2 } from "lucide-react";

const Reports = ({ userId }) => {
  const [reports, setReports] = useState([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [expandedReport, setExpandedReport] = useState(null);
  const [selectedDate, setSelectedDate] = useState(new Date().toISOString().slice(0, 10));

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

  const handleGenerateReport = async () => {
    setError("");
    setLoading(true);
    try {
      await postReport({ userid: userId, date: selectedDate });
      await fetchReports();
    } catch (err) {
      setError("Error al generar el reporte");
    } finally {
      setLoading(false);
    }
  };

  // Función para formatear el texto del reporte
  const formatReportText = (text) => {
    if (!text) return '';
    
    let formatted = text
      // Convertir títulos con ## a elementos destacados
      .replace(/##\s*([^#\n]+)/g, '<h3 class="report-title">$1</h3>')
      // Convertir texto en negrita **texto** 
      .replace(/\*\*([^*]+?)\*\*/g, '<strong class="report-bold">$1</strong>')
      // Convertir números seguidos de puntos (como 1., 2., etc.) en bullets numerados
      .replace(/^\s*(\d+)\.\s*([^\n]+)/gm, '<div class="report-bullet numbered">$1. $2</div>')
      // Convertir asteriscos simples * a bullets
      .replace(/^\s*\*\s*([^*\n]+)/gm, '<div class="report-bullet">• $1</div>')
      // Dividir por saltos de línea dobles para crear párrafos
      .split(/\n\s*\n/)
      .map(paragraph => {
        if (paragraph.includes('<h3') || paragraph.includes('<div class="report-bullet')) {
          return paragraph;
        }
        return paragraph.trim() ? `<p class="report-paragraph">${paragraph.trim()}</p>` : '';
      })
      .filter(p => p.length > 0)
      .join('');
    
    return formatted;
  };

  const toggleExpandReport = (index) => {
    setExpandedReport(expandedReport === index ? null : index);
  };

  return (
    <div>
      {/* Header */}
      <div style={{ marginBottom: '2rem' }}>
        <h1 style={{ fontSize: 'var(--font-size-3xl)', fontWeight: '700', marginBottom: '0.5rem', color: 'var(--text-primary)' }}>
          Reportes
        </h1>
        <p style={{ color: 'var(--text-secondary)', fontSize: 'var(--font-size-lg)' }}>
          Genera y consulta reportes de análisis de tu cultivo
        </p>
      </div>

      {/* Actions Card */}
      <div className="card mb-8">
        <div className="card-header">
          <h2 className="card-title">
            <Download size={24} style={{ marginRight: '0.5rem', verticalAlign: 'middle' }} />
            Generar Nuevo Reporte
          </h2>
          <p className="card-description">
            Obtené un análisis completo del estado actual de tu cultivo
          </p>
        </div>
        <div className="card-content">
          <div style={{ display: 'flex', flexDirection: 'column', gap: '1rem' }}>
            {/* Date Selector */}
            <div style={{ display: 'flex', alignItems: 'center', gap: '1rem' }}>
              <Calendar size={20} style={{ color: 'var(--primary)', flexShrink: 0 }} />
              <div style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem', flex: 1 }}>
                <label 
                  htmlFor="report-date" 
                  style={{ 
                    fontSize: 'var(--font-size-sm)', 
                    color: 'var(--text-secondary)',
                    fontWeight: '500'
                  }}
                >
                  Seleccionar Fecha:
                </label>
                <input
                  id="report-date"
                  type="date"
                  value={selectedDate}
                  onChange={(e) => setSelectedDate(e.target.value)}
                  max={new Date().toISOString().slice(0, 10)}
                  style={{
                    padding: '0.625rem 0.875rem',
                    fontSize: 'var(--font-size-base)',
                    borderRadius: 'var(--border-radius)',
                    border: '1px solid var(--gray)',
                    fontFamily: 'var(--font-primary)',
                    color: 'var(--text-primary)',
                    backgroundColor: 'var(--white)',
                    cursor: 'pointer',
                    transition: 'border-color 0.2s ease',
                    maxWidth: '200px'
                  }}
                  onFocus={(e) => e.target.style.borderColor = 'var(--primary)'}
                  onBlur={(e) => e.target.style.borderColor = 'var(--gray)'}
                />
              </div>
            </div>

            {/* Selected Date Display */}
            <div style={{ 
              padding: '0.75rem 1rem',
              background: 'var(--light-gray)',
              borderRadius: 'var(--border-radius)',
              fontSize: 'var(--font-size-sm)',
              color: 'var(--text-secondary)',
              borderLeft: '3px solid var(--primary)'
            }}>
              <strong style={{ color: 'var(--text-primary)' }}>Fecha seleccionada:</strong>{' '}
              {new Date(selectedDate + 'T00:00:00').toLocaleDateString('es-AR', { 
                weekday: 'long', 
                year: 'numeric', 
                month: 'long', 
                day: 'numeric' 
              })}
            </div>
          </div>
          
          {error && (
            <div className="alert alert-error" style={{ marginTop: '1rem' }}>
              <AlertCircle size={16} style={{ marginRight: '0.5rem' }} />
              {error}
            </div>
          )}

          <button 
            className="btn btn-primary"
            onClick={handleGenerateReport} 
            disabled={!userId || loading}
            style={{ marginTop: '1rem' }}
          >
            {loading ? (
              <>
                <div className="spinner" style={{ width: '16px', height: '16px' }}></div>
                Generando...
              </>
            ) : (
              <>
                <Download size={16} />
                Generar Reporte
              </>
            )}
          </button>
        </div>
      </div>

      {/* Reports Table */}
      <div className="card">
        <div className="card-header">
          <h2 className="card-title">
            <FileText size={24} style={{ marginRight: '0.5rem', verticalAlign: 'middle' }} />
            Historial de Reportes
          </h2>
          <p className="card-description">
            Todos los reportes generados para tu cultivo
          </p>
        </div>
        <div className="card-content" style={{ padding: '0' }}>
          {loading && reports.length === 0 ? (
            <div className="loading">
              <div className="spinner"></div>
              Cargando reportes...
            </div>
          ) : reports.length > 0 ? (
            <div className="table-container" style={{ boxShadow: 'none', border: 'none' }}>
              <table className="table">
                <thead>
                  <tr>
                    <th>
                      <Calendar size={16} style={{ marginRight: '0.5rem', verticalAlign: 'middle' }} />
                      Fecha
                    </th>
                    <th>
                      <User size={16} style={{ marginRight: '0.5rem', verticalAlign: 'middle' }} />
                      Usuario
                    </th>
                    <th style={{ minWidth: '300px' }}>
                      <FileText size={16} style={{ marginRight: '0.5rem', verticalAlign: 'middle' }} />
                      Contenido del Reporte
                    </th>
                    <th>Estado</th>
                  </tr>
                </thead>
                <tbody>
                  {reports.map((r, idx) => (
                    <tr key={idx}>
                      <td>
                        <span style={{ fontWeight: '600', color: 'var(--text-primary)' }}>
                          {new Date(r.date + 'T00:00:00').toLocaleDateString('es-AR', {
                            day: '2-digit',
                            month: '2-digit',
                            year: 'numeric'
                          })}
                        </span>
                      </td>
                      <td>
                        <span style={{ 
                          padding: '0.25rem 0.5rem', 
                          background: 'var(--light-gray)', 
                          borderRadius: 'var(--border-radius-sm)',
                          fontSize: 'var(--font-size-xs)',
                          fontWeight: '500'
                        }}>
                          ID: {r.userid}
                        </span>
                      </td>
                      <td>
                        <div style={{ maxWidth: '500px' }}>
                          {expandedReport === idx ? (
                            <div>
                              <div 
                                className="report-content"
                                dangerouslySetInnerHTML={{ 
                                  __html: formatReportText(r.report) 
                                }}
                              />
                              <button 
                                className="btn btn-ghost btn-sm mt-2"
                                onClick={() => toggleExpandReport(idx)}
                                style={{ fontSize: 'var(--font-size-xs)' }}
                              >
                                <Maximize2 size={12} />
                                Contraer
                              </button>
                            </div>
                          ) : (
                            <div>
                              <div style={{ 
                                maxHeight: '60px',
                                overflow: 'hidden',
                                lineHeight: '1.4',
                                color: 'var(--text-secondary)',
                                marginBottom: '0.5rem'
                              }}>
                                {r.report.length > 150 
                                  ? r.report.substring(0, 150) + '...' 
                                  : r.report
                                }
                              </div>
                              <button 
                                className="btn btn-ghost btn-sm"
                                onClick={() => toggleExpandReport(idx)}
                                style={{ fontSize: 'var(--font-size-xs)' }}
                              >
                                <Eye size={12} />
                                Ver completo
                              </button>
                            </div>
                          )}
                        </div>
                      </td>
                      <td>
                        <span style={{ 
                          color: 'var(--success)', 
                          display: 'flex', 
                          alignItems: 'center', 
                          gap: '0.25rem',
                          fontSize: 'var(--font-size-sm)'
                        }}>
                          <CheckCircle2 size={14} />
                          Completado
                        </span>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ) : (
            <div style={{ padding: 'var(--spacing-8)', textAlign: 'center' }}>
              <FileText size={48} style={{ color: 'var(--text-secondary)', marginBottom: '1rem' }} />
              <p style={{ color: 'var(--text-secondary)', margin: '0', marginBottom: '1rem' }}>
                Aún no hay reportes generados
              </p>
              <p style={{ color: 'var(--text-secondary)', margin: '0', fontSize: 'var(--font-size-sm)' }}>
                Hacé clic en "Obtener Reporte de Hoy" para generar tu primer análisis
              </p>
            </div>
          )}
        </div>
      </div>
    </div>
  );
};

export default Reports;
