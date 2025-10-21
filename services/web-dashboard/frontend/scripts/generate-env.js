const fs = require('fs');

// Intentar leer el archivo existente primero
let apiUrl = 'http://localhost:3000/api';
try {
  const existingContent = fs.readFileSync('./public/env.js', 'utf8');
  const match = existingContent.match(/API_URL: "(.*?)"/);
  if (match && match[1]) {
    apiUrl = match[1];
    console.log('Using existing API URL:', apiUrl);
  }
} catch (error) {
  console.log('No existing env.js found, using default URL');
}

// Si tenemos una URL en las variables de entorno, usarla
if (process.env.REACT_APP_API_URL) {
  apiUrl = process.env.REACT_APP_API_URL;
  console.log('Using API URL from environment:', apiUrl);
}

const envConfig = `window.ENV = {
  API_URL: "${apiUrl}"
};`;

// Copiar a public y build
fs.writeFileSync('./public/env.js', envConfig);
if (fs.existsSync('./build')) {
  fs.writeFileSync('./build/env.js', envConfig);
}
console.log('env.js files generated successfully');