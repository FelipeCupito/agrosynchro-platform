import axios from "axios";

const API_URL = "http://localhost:3000/api"; // ajustá al host correcto

export const getUsers = () => axios.get(`${API_URL}/users`);
export const getSensorData = (userId) => axios.get(`${API_URL}/sensor_data?user_id=${userId}`);
export const getParameters = (userId) => axios.get(`${API_URL}/parameters?user_id=${userId}`);
