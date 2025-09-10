import axios from "axios";

const API_URL = "http://load-balancer-agro-1197193656.us-east-1.elb.amazonaws.com:3000/api"; // ajustá al host correcto

export const getUsers = () => axios.get(`${API_URL}/users`);
export const getSensorData = (userId) => axios.get(`${API_URL}/sensor_data?user_id=${userId}`);
export const getParameters = (userId) => axios.get(`${API_URL}/parameters?user_id=${userId}`);

// Crear usuario
export const createUser = (email) => axios.post(`${API_URL}/users`, { email:email, username:"test" });

// Crear parámetros asociados a un usuario
export const createParameters = (userId, parameters) =>
  axios.post(`${API_URL}/parameters`, { user_id: userId, parameters });
