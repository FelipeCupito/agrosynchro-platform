import React, { useEffect, useState } from "react";
import { getDroneImages } from "../services/api";
import { Camera, AlertTriangle, RefreshCw, Image as ImageIcon, Flame } from "lucide-react";

const DroneImages = ({ userId }) => {
  const [images, setImages] = useState([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);

  const loadImages = async () => {
    if (!userId) return;
    
    setLoading(true);
    setError(null);
    
    try {
      const response = await getDroneImages(userId);
      const data = response?.data?.images || [];
      setImages(data);
      console.log("✅ Drone images loaded:", data);
    } catch (err) {
      console.error("❌ Error loading drone images:", err);
      setError(err.response?.data?.error || "Error al cargar las imágenes");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadImages();
  }, [userId]);

  // Helper para obtener el color del badge según el estado
  const getStatusColor = (status) => {
    switch(status?.toLowerCase()) {
      case 'excellent': return '#27ae60';
      case 'good': return '#2ecc71';
      case 'fair': return '#f39c12';
      case 'poor': return '#e67e22';
      case 'critical': return '#c0392b';
      case 'fire_detected': return '#e74c3c';
      default: return '#95a5a6';
    }
  };

  // Helper para obtener texto legible del estado
  const getStatusText = (status) => {
    switch(status?.toLowerCase()) {
      case 'excellent': return 'Excelente';
      case 'good': return 'Bueno';
      case 'fair': return 'Regular';
      case 'poor': return 'Malo';
      case 'critical': return 'Crítico';
      case 'fire_detected': return '🔥 FUEGO DETECTADO';
      default: return status || 'Desconocido';
    }
  };

  // Formatear fecha
  const formatDate = (dateString) => {
    if (!dateString) return 'N/A';
    const date = new Date(dateString);
    return date.toLocaleString('es-AR', {
      day: '2-digit',
      month: '2-digit',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit'
    });
  };

  return (
    <div>
      {/* Header */}
      <div style={{ marginBottom: '2rem', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <div>
          <h1 style={{ fontSize: 'var(--font-size-3xl)', fontWeight: '700', marginBottom: '0.5rem', color: 'var(--text-primary)' }}>
            <Camera size={32} style={{ marginRight: '0.75rem', verticalAlign: 'middle' }} />
            Imágenes de Drones
          </h1>
          <p style={{ color: 'var(--text-secondary)', fontSize: 'var(--font-size-lg)' }}>
            Análisis visual del estado de tu campo
          </p>
        </div>
        <button 
          className="btn btn-primary"
          onClick={loadImages}
          disabled={loading || !userId}
          style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}
        >
          <RefreshCw size={16} style={{ animation: loading ? 'spin 1s linear infinite' : 'none' }} />
          {loading ? 'Cargando...' : 'Actualizar'}
        </button>
      </div>

      {/* No userId */}
      {!userId && (
        <div className="card">
          <div className="card-content text-center">
            <AlertTriangle size={48} style={{ color: 'var(--warning)', marginBottom: '1rem' }} />
            <p style={{ fontSize: 'var(--font-size-lg)', marginBottom: '0' }}>
              Iniciá sesión para ver las imágenes de tu campo
            </p>
          </div>
        </div>
      )}

      {/* Error */}
      {error && (
        <div className="card" style={{ borderLeft: '4px solid var(--error)', marginBottom: '2rem' }}>
          <div className="card-content">
            <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem' }}>
              <AlertTriangle size={24} style={{ color: 'var(--error)' }} />
              <div>
                <h3 style={{ margin: 0, marginBottom: '0.25rem', color: 'var(--error)' }}>Error</h3>
                <p style={{ margin: 0, color: 'var(--text-secondary)' }}>{error}</p>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Loading */}
      {loading && userId && (
        <div className="card">
          <div className="card-content text-center">
            <RefreshCw size={48} style={{ color: 'var(--primary)', marginBottom: '1rem', animation: 'spin 1s linear infinite' }} />
            <p style={{ fontSize: 'var(--font-size-lg)', marginBottom: '0' }}>
              Cargando imágenes...
            </p>
          </div>
        </div>
      )}

      {/* No images */}
      {!loading && userId && images.length === 0 && !error && (
        <div className="card">
          <div className="card-content text-center">
            <ImageIcon size={48} style={{ color: 'var(--text-secondary)', marginBottom: '1rem' }} />
            <p style={{ fontSize: 'var(--font-size-lg)', marginBottom: '0' }}>
              No hay imágenes disponibles aún
            </p>
            <p style={{ fontSize: 'var(--font-size-sm)', color: 'var(--text-secondary)', marginTop: '0.5rem' }}>
              Las imágenes capturadas por los drones aparecerán aquí
            </p>
          </div>
        </div>
      )}

      {/* Images Grid */}
      {!loading && userId && images.length > 0 && (
        <div style={{ display: 'grid', gap: '2rem' }}>
          {images.map((image) => (
            <div 
              key={image.id} 
              className="card"
              style={{ 
                borderLeft: image.field_status === 'FIRE_DETECTED' ? '4px solid #e74c3c' : '4px solid var(--primary)'
              }}
            >
              <div className="card-header">
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '1rem' }}>
                  <div>
                    <h3 className="card-title" style={{ marginBottom: '0.5rem' }}>
                      Imagen #{image.id}
                    </h3>
                    <p className="card-description">
                      📅 {formatDate(image.processed_at)}
                    </p>
                  </div>
                  <div style={{ display: 'flex', gap: '0.75rem', flexWrap: 'wrap' }}>
                    {/* Estado del campo */}
                    <span 
                      style={{
                        padding: '0.5rem 1rem',
                        borderRadius: 'var(--radius)',
                        backgroundColor: getStatusColor(image.field_status),
                        color: 'white',
                        fontWeight: '600',
                        fontSize: 'var(--font-size-sm)',
                        display: 'flex',
                        alignItems: 'center',
                        gap: '0.5rem'
                      }}
                    >
                      {image.field_status === 'FIRE_DETECTED' && <Flame size={16} />}
                      {getStatusText(image.field_status)}
                    </span>
                    {/* Confianza */}
                    {image.analysis_confidence > 0 && (
                      <span 
                        style={{
                          padding: '0.5rem 1rem',
                          borderRadius: 'var(--radius)',
                          backgroundColor: 'var(--background-secondary)',
                          color: 'var(--text-primary)',
                          fontWeight: '600',
                          fontSize: 'var(--font-size-sm)'
                        }}
                      >
                        Confianza: {(image.analysis_confidence * 100).toFixed(1)}%
                      </span>
                    )}
                  </div>
                </div>
              </div>

              <div className="card-content">
                {/* Grid de imágenes: Raw y Processed lado a lado */}
                <div style={{ 
                  display: 'grid', 
                  gridTemplateColumns: 'repeat(auto-fit, minmax(300px, 1fr))',
                  gap: '1.5rem'
                }}>
                  {/* Imagen Raw */}
                  {image.raw_url && (
                    <div>
                      <h4 style={{ 
                        marginBottom: '0.75rem', 
                        color: 'var(--text-secondary)', 
                        fontSize: 'var(--font-size-sm)',
                        fontWeight: '600',
                        textTransform: 'uppercase',
                        letterSpacing: '0.05em'
                      }}>
                        📸 Original
                      </h4>
                      <div style={{
                        borderRadius: 'var(--radius)',
                        overflow: 'hidden',
                        border: '2px solid var(--border)',
                        boxShadow: '0 4px 6px rgba(0,0,0,0.1)'
                      }}>
                        <img 
                          src={image.raw_url} 
                          alt="Imagen original del campo"
                          style={{
                            width: '100%',
                            height: 'auto',
                            display: 'block',
                            backgroundColor: 'var(--background-secondary)'
                          }}
                          onError={(e) => {
                            e.target.style.display = 'none';
                            e.target.nextSibling.style.display = 'flex';
                          }}
                        />
                        <div style={{
                          display: 'none',
                          alignItems: 'center',
                          justifyContent: 'center',
                          height: '300px',
                          backgroundColor: 'var(--background-secondary)',
                          color: 'var(--text-secondary)'
                        }}>
                          <div style={{ textAlign: 'center' }}>
                            <ImageIcon size={48} style={{ marginBottom: '0.5rem' }} />
                            <p>Error al cargar imagen</p>
                          </div>
                        </div>
                      </div>
                      <p style={{ 
                        marginTop: '0.5rem', 
                        fontSize: 'var(--font-size-xs)', 
                        color: 'var(--text-secondary)',
                        fontFamily: 'monospace'
                      }}>
                        {image.raw_s3_key}
                      </p>
                    </div>
                  )}

                  {/* Imagen Procesada */}
                  {image.processed_url && (
                    <div>
                      <h4 style={{ 
                        marginBottom: '0.75rem', 
                        color: 'var(--text-secondary)', 
                        fontSize: 'var(--font-size-sm)',
                        fontWeight: '600',
                        textTransform: 'uppercase',
                        letterSpacing: '0.05em'
                      }}>
                        🔍 Procesada {image.field_status === 'FIRE_DETECTED' && '🔥'}
                      </h4>
                      <div style={{
                        borderRadius: 'var(--radius)',
                        overflow: 'hidden',
                        border: image.field_status === 'FIRE_DETECTED' 
                          ? '3px solid #e74c3c' 
                          : '2px solid var(--primary)',
                        boxShadow: image.field_status === 'FIRE_DETECTED'
                          ? '0 0 20px rgba(231, 76, 60, 0.5)'
                          : '0 4px 6px rgba(0,0,0,0.1)'
                      }}>
                        <img 
                          src={image.processed_url} 
                          alt="Imagen procesada con análisis"
                          style={{
                            width: '100%',
                            height: 'auto',
                            display: 'block',
                            backgroundColor: 'var(--background-secondary)'
                          }}
                          onError={(e) => {
                            e.target.style.display = 'none';
                            e.target.nextSibling.style.display = 'flex';
                          }}
                        />
                        <div style={{
                          display: 'none',
                          alignItems: 'center',
                          justifyContent: 'center',
                          height: '300px',
                          backgroundColor: 'var(--background-secondary)',
                          color: 'var(--text-secondary)'
                        }}>
                          <div style={{ textAlign: 'center' }}>
                            <ImageIcon size={48} style={{ marginBottom: '0.5rem' }} />
                            <p>Error al cargar imagen</p>
                          </div>
                        </div>
                      </div>
                      <p style={{ 
                        marginTop: '0.5rem', 
                        fontSize: 'var(--font-size-xs)', 
                        color: 'var(--text-secondary)',
                        fontFamily: 'monospace'
                      }}>
                        {image.processed_s3_key}
                      </p>
                    </div>
                  )}
                </div>

                {/* Metadatos adicionales */}
                {image.analyzed_at && (
                  <div style={{ 
                    marginTop: '1.5rem', 
                    paddingTop: '1.5rem', 
                    borderTop: '1px solid var(--border)',
                    fontSize: 'var(--font-size-sm)',
                    color: 'var(--text-secondary)'
                  }}>
                    <p style={{ margin: 0 }}>
                      <strong>Analizada:</strong> {formatDate(image.analyzed_at)}
                    </p>
                  </div>
                )}
              </div>
            </div>
          ))}
        </div>
      )}

      <style jsx>{`
        @keyframes spin {
          from { transform: rotate(0deg); }
          to { transform: rotate(360deg); }
        }
      `}</style>
    </div>
  );
};

export default DroneImages;
