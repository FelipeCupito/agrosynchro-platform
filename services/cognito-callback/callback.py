"""
Lambda function to handle Cognito OAuth callback
Intercambia el authorization code por tokens y redirige al frontend
"""
import json
import os
import urllib.request
import urllib.parse
import base64

# Variables de entorno
COGNITO_DOMAIN = os.environ['COGNITO_DOMAIN']
CLIENT_ID = os.environ['CLIENT_ID']
FRONTEND_URL = os.environ['FRONTEND_URL']
REGION = os.environ.get('AWS_REGION', 'us-east-1')

def lambda_handler(event, context):
    """
    Maneja el callback de Cognito OAuth
    """
    print(f"Event: {json.dumps(event)}")
    
    # Obtener parámetros de query string
    params = event.get('queryStringParameters', {})
    
    # Verificar si hay un error
    if 'error' in params:
        error_description = params.get('error_description', 'Unknown error')
        return redirect_to_frontend(
            error=params['error'],
            error_description=error_description
        )
    
    # Obtener el authorization code
    code = params.get('code')
    if not code:
        return {
            'statusCode': 400,
            'body': json.dumps({'error': 'Missing authorization code'})
        }
    
    # Intercambiar code por tokens
    try:
        tokens = exchange_code_for_tokens(code, event)
        
        # Redirigir al frontend con los tokens
        return redirect_to_frontend(
            access_token=tokens.get('access_token'),
            id_token=tokens.get('id_token'),
            refresh_token=tokens.get('refresh_token'),
            expires_in=tokens.get('expires_in')
        )
        
    except Exception as e:
        print(f"Error exchanging code: {str(e)}")
        return redirect_to_frontend(
            error='token_exchange_failed',
            error_description=str(e)
        )

def exchange_code_for_tokens(code, event):
    """
    Intercambia el authorization code por tokens de acceso
    """
    # Construir la URL del callback (debe coincidir con la registrada en Cognito)
    headers = event.get('headers', {})
    host = headers.get('Host', '')
    stage = event.get('requestContext', {}).get('stage', '')
    
    # Construir redirect_uri
    redirect_uri = f"https://{host}/{stage}/callback"
    
    # Endpoint de token de Cognito
    token_url = f"https://{COGNITO_DOMAIN}/oauth2/token"
    
    # Preparar datos para el POST
    data = {
        'grant_type': 'authorization_code',
        'client_id': CLIENT_ID,
        'code': code,
        'redirect_uri': redirect_uri
    }
    
    # Hacer request POST
    encoded_data = urllib.parse.urlencode(data).encode('utf-8')
    
    req = urllib.request.Request(
        token_url,
        data=encoded_data,
        headers={
            'Content-Type': 'application/x-www-form-urlencoded'
        },
        method='POST'
    )
    
    with urllib.request.urlopen(req) as response:
        response_data = response.read().decode('utf-8')
        return json.loads(response_data)

def redirect_to_frontend(access_token=None, id_token=None, refresh_token=None, 
                         expires_in=None, error=None, error_description=None):
    """
    Redirige al frontend con los tokens en el hash de la URL
    """
    # Construir parámetros
    params = {}
    
    if error:
        params['error'] = error
        if error_description:
            params['error_description'] = error_description
    else:
        if access_token:
            params['access_token'] = access_token
        if id_token:
            params['id_token'] = id_token
        if refresh_token:
            params['refresh_token'] = refresh_token
        if expires_in:
            params['expires_in'] = str(expires_in)
    
    # Crear URL de redirección con hash
    redirect_url = f"{FRONTEND_URL}#" + urllib.parse.urlencode(params)
    
    return {
        'statusCode': 302,
        'headers': {
            'Location': redirect_url,
            'Access-Control-Allow-Origin': '*'
        },
        'body': ''
    }
