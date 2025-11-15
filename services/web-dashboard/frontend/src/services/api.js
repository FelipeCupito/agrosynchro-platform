import axios from "axios";
import { getAccessToken } from "../auth";

// Crear una instancia de axios con la configuración personalizada
const axiosInstance = axios.create({
  headers: {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  }
});

// Attach Authorization header if access token exists
axiosInstance.interceptors.request.use((config) => {
  const token = getAccessToken();
  if (token) {
    config.headers = config.headers || {};
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

const getApiUrl = () => {
  return window.ENV?.API_URL || 'http://localhost:3000/api';

  return window.ENV.API_URL;
};

const API_URL = getApiUrl();

export const getUsers = () => axiosInstance.get(`${API_URL}/users`);
export const getSensorData = (userId) => axiosInstance.get(`${API_URL}/sensor_data?user_id=${userId}`);
export const getParameters = (userId) => axiosInstance.get(`${API_URL}/parameters?user_id=${userId}`);

// Crear usuario
export const createUser = (email) => axiosInstance.post(`${API_URL}/users`, { mail: email, username:"test" });

// Crear parámetros asociados a un usuario
export const createParameters = (userId, parameters) => {
  // Mapear el objeto anidado a los campos planos que espera el backend
  return axiosInstance.post(`${API_URL}/parameters`, {
    userid: userId,
    min_temperature: parameters.temperature.min,
    max_temperature: parameters.temperature.max,
    min_humidity: parameters.humidity.min,
    max_humidity: parameters.humidity.max,
    min_soil_moisture: parameters.soil_moisture.min,
    max_soil_moisture: parameters.soil_moisture.max
  });
};

// Reportes
export const getReports = (userId) => {
  const url = userId ? `${API_URL}/reports?user_id=${userId}` : `${API_URL}/reports`;
  return axiosInstance.get(url);
};
export const postReport = ({ userid, date }) => axiosInstance.post(`${API_URL}/reports?user_id=${userid}&date=${date}`);

// Imágenes de drones
export const getDroneImages = (userId) => axiosInstance.get(`${API_URL}/images?user_id=${userId}`);
